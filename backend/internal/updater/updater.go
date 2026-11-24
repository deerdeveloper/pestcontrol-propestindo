// Package updater mengganti binary server dengan versi terbaru dari GitHub Releases.
//
// Alur: cek rilis terbaru → unduh file binary yang cocok dengan OS/arsitektur →
// cocokkan SHA-256 dengan SHA256SUMS → ambil binary dari tar.gz → jalankan "binary -version" untuk memastikan
// bisa jalan di mesin ini → simpan binary lama sebagai .bak → ganti → restart.
package updater

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Options mengatur perilaku updater.
type Options struct {
	GitHub  *GitHub
	Current string // versi yang sedang jalan, misalnya v0.2.0
	// Asset memberi nama file rilis untuk tag tertentu, misalnya
	// pestcontrol-api_v0.2.0_linux_arm64.tar.gz. File itu berisi binary BinaryName.
	Asset      func(tag string) string
	BinaryName string        // nama binary di dalam tar.gz, misalnya pestcontrol-api
	ExePath    string        // lokasi binary yang sedang jalan
	Interval   time.Duration // jeda cek otomatis
	// AutoFrom dan AutoTo adalah jam (0-23, waktu server) saat update otomatis boleh dipasang.
	// Sama nilainya berarti kapan saja.
	AutoFrom, AutoTo int
	// Restart dipanggil setelah binary diganti. Server harus berhenti dengan rapi lalu
	// menjalankan ulang dirinya (lihat cmd/api).
	Restart func()
}

// Status adalah kondisi updater untuk ditampilkan di halaman super admin.
type Status struct {
	Enabled         bool       `json:"enabled"`
	Repo            string     `json:"repo"`
	Current         string     `json:"current"`
	Latest          *Release   `json:"latest,omitempty"`
	UpdateAvailable bool       `json:"update_available"`
	LastCheck       *time.Time `json:"last_check,omitempty"`
	LastError       string     `json:"last_error,omitempty"`
	State           string     `json:"state"` // idle | checking | downloading | restarting
	Progress        int64      `json:"progress"`
	Total           int64      `json:"total"`
	Auto            bool       `json:"auto"`
	AutoWindow      string     `json:"auto_window"`
	Interval        string     `json:"interval"`
	Asset           string     `json:"asset"`
}

type Updater struct {
	opt  Options
	auto atomic.Bool
	busy sync.Mutex // hanya satu proses update dalam satu waktu

	mu        sync.Mutex
	latest    *Release
	lastCheck time.Time
	lastErr   string
	state     string
	progress  atomic.Int64
	total     atomic.Int64
}

func New(opt Options) *Updater {
	if opt.Interval <= 0 {
		opt.Interval = time.Hour
	}
	return &Updater{opt: opt, state: "idle"}
}

// Enabled bernilai false jika repo sumber update belum diatur.
func (u *Updater) Enabled() bool { return u != nil && u.opt.GitHub != nil && u.opt.GitHub.Repo != "" }

func (u *Updater) SetAuto(v bool) { u.auto.Store(v) }
func (u *Updater) Auto() bool     { return u.auto.Load() }

func (u *Updater) setState(s string) {
	u.mu.Lock()
	u.state = s
	u.mu.Unlock()
}

func (u *Updater) Status() Status {
	u.mu.Lock()
	defer u.mu.Unlock()
	st := Status{
		Enabled: u.Enabled(), Current: u.opt.Current, Latest: u.latest, LastError: u.lastErr,
		State: u.state, Progress: u.progress.Load(), Total: u.total.Load(), Auto: u.auto.Load(),
		AutoWindow: fmt.Sprintf("%02d:00-%02d:00", u.opt.AutoFrom, u.opt.AutoTo),
		Interval:   human(u.opt.Interval), Asset: u.assetName("<tag>"),
	}
	if u.opt.AutoFrom == u.opt.AutoTo {
		st.AutoWindow = "kapan saja"
	}
	if u.opt.GitHub != nil {
		st.Repo = u.opt.GitHub.Repo
	}
	if !u.lastCheck.IsZero() {
		t := u.lastCheck
		st.LastCheck = &t
	}
	st.UpdateAvailable = u.latest != nil && Newer(u.latest.Tag, u.opt.Current)
	return st
}

// Check selalu bertanya ke GitHub.
func (u *Updater) Check(ctx context.Context) (*Release, error) {
	if !u.Enabled() {
		return nil, errors.New("update belum diatur: isi UPDATE_REPO")
	}
	u.mu.Lock()
	prev := u.state
	if prev == "idle" {
		u.state = "checking"
	}
	u.mu.Unlock()
	rel, err := u.opt.GitHub.Latest(ctx)
	u.mu.Lock()
	defer u.mu.Unlock()
	if u.state == "checking" {
		u.state = "idle"
	}
	u.lastCheck = time.Now()
	if err != nil {
		u.lastErr = err.Error()
		return nil, err
	}
	u.lastErr = ""
	u.latest = rel
	return rel, nil
}

// Latest memakai hasil cek terakhir jika belum lebih tua dari maxAge.
func (u *Updater) Latest(ctx context.Context, maxAge time.Duration) (*Release, error) {
	u.mu.Lock()
	rel, at := u.latest, u.lastCheck
	u.mu.Unlock()
	if rel != nil && time.Since(at) < maxAge {
		return rel, nil
	}
	return u.Check(ctx)
}

// Open membuka file dari rilis (dipakai untuk meneruskan APK ke aplikasi HP).
func (u *Updater) Open(ctx context.Context, a Asset) (io.ReadCloser, int64, error) {
	return u.opt.GitHub.Open(ctx, a)
}

// Checksums membaca SHA256SUMS dari rilis.
func (u *Updater) Checksums(ctx context.Context, rel *Release) (map[string]string, error) {
	return u.opt.GitHub.Checksums(ctx, rel)
}

// ErrBusy dikembalikan jika update lain sedang berjalan.
var ErrBusy = errors.New("update sedang berjalan")

// ErrUpToDate dikembalikan jika tidak ada versi yang lebih baru.
var ErrUpToDate = errors.New("server sudah memakai versi terbaru")

// Start memulai update di background dan langsung kembali.
// Error validasi awal (sedang sibuk, tidak ada versi baru) dikembalikan langsung.
func (u *Updater) Start(ctx context.Context) error {
	if !u.Enabled() {
		return errors.New("update belum diatur: isi UPDATE_REPO")
	}
	if !u.busy.TryLock() {
		return ErrBusy
	}
	rel, err := u.Check(ctx)
	if err != nil {
		u.busy.Unlock()
		return err
	}
	if !Newer(rel.Tag, u.opt.Current) {
		u.busy.Unlock()
		return ErrUpToDate
	}
	go func() {
		defer u.busy.Unlock()
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Minute)
		defer cancel()
		if err := u.install(ctx, rel); err != nil {
			log.Printf("update ke %s gagal: %v", rel.Tag, err)
			u.mu.Lock()
			u.lastErr = err.Error()
			u.state = "idle"
			u.mu.Unlock()
		}
	}()
	return nil
}

func (u *Updater) assetName(tag string) string {
	if u.opt.Asset == nil {
		return ""
	}
	return u.opt.Asset(tag)
}

func (u *Updater) install(ctx context.Context, rel *Release) error {
	name := u.assetName(rel.Tag)
	asset, ok := rel.Asset(name)
	if !ok {
		return fmt.Errorf("rilis %s tidak punya file %s", rel.Tag, name)
	}
	sums, err := u.opt.GitHub.Checksums(ctx, rel)
	if err != nil {
		return err
	}
	want := sums[asset.Name]
	if want == "" {
		return fmt.Errorf("%s tidak tercantum di SHA256SUMS", asset.Name)
	}

	u.setState("downloading")
	u.progress.Store(0)
	u.total.Store(asset.Size)
	log.Printf("update: mengunduh %s %s", rel.Tag, asset.Name)

	exe := u.opt.ExePath
	dir := filepath.Dir(exe)
	archive, err := os.CreateTemp(dir, ".update-*.tar.gz")
	if err != nil {
		return fmt.Errorf("folder %s tidak bisa ditulis oleh user service: %w", dir, err)
	}
	defer os.Remove(archive.Name())
	body, _, err := u.opt.GitHub.Open(ctx, asset)
	if err != nil {
		archive.Close()
		return err
	}
	h := sha256.New()
	_, err = io.Copy(io.MultiWriter(archive, h, progressWriter{&u.progress}), body)
	body.Close()
	if err != nil {
		archive.Close()
		return fmt.Errorf("mengunduh: %w", err)
	}
	if got := hex.EncodeToString(h.Sum(nil)); got != want {
		archive.Close()
		return fmt.Errorf("checksum tidak cocok (dapat %s, seharusnya %s)", got, want)
	}

	tmpName := exe + ".new"
	installed := false
	defer func() {
		if !installed {
			os.Remove(tmpName)
		}
	}()
	if _, err := archive.Seek(0, io.SeekStart); err != nil {
		archive.Close()
		return err
	}
	err = extract(archive, u.opt.BinaryName, tmpName)
	archive.Close()
	if err != nil {
		return err
	}

	// Pastikan binary baru bisa jalan di mesin ini dan versinya benar.
	vctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	out, err := exec.CommandContext(vctx, tmpName, "-version").Output()
	cancel()
	if err != nil {
		return fmt.Errorf("binary baru gagal dijalankan: %w", err)
	}
	if got := strings.Fields(string(out)); len(got) == 0 || got[0] != rel.Tag {
		return fmt.Errorf("versi binary baru %q tidak sama dengan tag %s", strings.TrimSpace(string(out)), rel.Tag)
	}

	backup := exe + ".bak"
	if err := os.Rename(exe, backup); err != nil {
		return fmt.Errorf("menyimpan binary lama: %w", err)
	}
	if err := os.Rename(tmpName, exe); err != nil {
		os.Rename(backup, exe)
		return fmt.Errorf("memasang binary baru: %w", err)
	}
	installed = true
	log.Printf("update: %s terpasang (binary lama di %s), restart...", rel.Tag, backup)
	u.setState("restarting")
	if u.opt.Restart != nil {
		go func() {
			time.Sleep(time.Second) // beri waktu respons HTTP terakhir terkirim
			u.opt.Restart()
		}()
	}
	return nil
}

// Run mengecek update secara berkala sampai ctx selesai. Jika update otomatis aktif dan
// jam sekarang ada di jendela update, versi baru langsung dipasang.
func (u *Updater) Run(ctx context.Context) {
	if !u.Enabled() {
		log.Printf("update: nonaktif (UPDATE_REPO kosong)")
		return
	}
	timer := time.NewTimer(30 * time.Second)
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}
		rel, err := u.Check(ctx)
		if err != nil {
			log.Printf("update: cek gagal: %v", err)
		} else if Newer(rel.Tag, u.opt.Current) {
			log.Printf("update: versi baru %s tersedia (sekarang %s)", rel.Tag, u.opt.Current)
			if u.Auto() && u.inWindow(time.Now()) {
				if err := u.Start(ctx); err != nil && !errors.Is(err, ErrBusy) {
					log.Printf("update otomatis gagal: %v", err)
				}
			}
		}
		timer.Reset(u.opt.Interval)
	}
}

func (u *Updater) inWindow(t time.Time) bool {
	from, to, h := u.opt.AutoFrom, u.opt.AutoTo, t.Hour()
	switch {
	case from == to:
		return true
	case from < to:
		return h >= from && h < to
	default: // melewati tengah malam, misalnya 22-04
		return h >= from || h < to
	}
}

type progressWriter struct{ n *atomic.Int64 }

func (p progressWriter) Write(b []byte) (int, error) {
	p.n.Add(int64(len(b)))
	return len(b), nil
}

func human(d time.Duration) string {
	switch {
	case d%time.Hour == 0:
		return fmt.Sprintf("%d jam", d/time.Hour)
	case d%time.Minute == 0:
		return fmt.Sprintf("%d menit", d/time.Minute)
	}
	return d.String()
}

// extract menyalin satu file bernama name dari arsip tar.gz r ke dst (mode 0755).
func extract(r io.Reader, name, dst string) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return fmt.Errorf("arsip rilis rusak: %w", err)
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			return fmt.Errorf("%s tidak ada di dalam arsip rilis", name)
		}
		if err != nil {
			return fmt.Errorf("arsip rilis rusak: %w", err)
		}
		if hdr.Typeflag != tar.TypeReg || path.Clean(hdr.Name) != name {
			continue
		}
		f, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o755)
		if err != nil {
			return err
		}
		_, err = io.Copy(f, tr)
		if cerr := f.Close(); err == nil {
			err = cerr
		}
		return err
	}
}
