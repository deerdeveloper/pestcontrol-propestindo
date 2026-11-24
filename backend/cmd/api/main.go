// Command api menjalankan server REST API sistem laporan pest control.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"

	"github.com/propestindo/pestcontrol/internal/api"
	"github.com/propestindo/pestcontrol/internal/buildinfo"
	"github.com/propestindo/pestcontrol/internal/config"
	"github.com/propestindo/pestcontrol/internal/db"
	"github.com/propestindo/pestcontrol/internal/pdf"
	"github.com/propestindo/pestcontrol/internal/storage"
	"github.com/propestindo/pestcontrol/internal/updater"
	"github.com/propestindo/pestcontrol/internal/webui"
	"github.com/propestindo/pestcontrol/migrations"
)

func main() {
	showVersion := flag.Bool("version", false, "tampilkan versi lalu keluar")
	flag.Parse()
	if *showVersion {
		// Baris pertama harus diawali tag versi; dipakai updater untuk memeriksa binary baru.
		fmt.Printf("%s %s %s %s/%s\n", buildinfo.Version, buildinfo.Commit, buildinfo.Date, runtime.GOOS, runtime.GOARCH)
		return
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	cfg := config.Load()
	log.Printf("pestcontrol-api %s (%s) %s/%s", buildinfo.Version, buildinfo.Commit, runtime.GOOS, runtime.GOARCH)
	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database: %v", err)
	}
	if err := db.Migrate(ctx, pool, migrations.FS); err != nil {
		log.Fatalf("migrasi: %v", err)
	}

	exe, err := os.Executable()
	if err == nil {
		exe, err = filepath.EvalSymlinks(exe)
	}
	if err != nil {
		log.Fatalf("lokasi binary: %v", err)
	}

	restart := make(chan struct{}, 1)
	from, to := cfg.UpdateWindow()
	upd := updater.New(updater.Options{
		GitHub:  &updater.GitHub{Repo: cfg.UpdateRepo, Token: cfg.UpdateToken, API: cfg.UpdateAPI},
		Current: buildinfo.Version,
		// Pola nama file sama dengan tool/build.sh: pestcontrol-api_<tag>_linux_<arch>.tar.gz
		Asset: func(tag string) string {
			return fmt.Sprintf("pestcontrol-api_%s_%s_%s.tar.gz", tag, runtime.GOOS, runtime.GOARCH)
		},
		BinaryName: "pestcontrol-api",
		ExePath:    exe,
		Interval:   cfg.UpdateInterval,
		AutoFrom:   from,
		AutoTo:     to,
		Restart:    func() { restart <- struct{}{} },
	})
	upd.SetAuto(cfg.UpdateAuto)

	srv := api.NewServer(cfg, pool, storage.Local{Root: cfg.StorageDir}, pdf.New(cfg.ChromePath, cfg.CompanyName)).
		WithUpdater(upd)
	if web := webui.Handler(); web != nil {
		srv.WithWeb(web)
		log.Printf("aplikasi web tertanam ikut disajikan di /app/ (landing page di /)")
	}
	srv.LoadSettings(ctx)
	go upd.Run(ctx)

	httpSrv := &http.Server{Addr: cfg.Addr, Handler: srv.Routes(), ReadHeaderTimeout: 10 * time.Second}
	errCh := make(chan error, 1)
	go func() {
		log.Printf("API berjalan di %s", cfg.Addr)
		if err := httpSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	doRestart := false
	select {
	case <-ctx.Done():
	case <-restart:
		doRestart = true
	case err := <-errCh:
		log.Fatal(err)
	}

	shutdown, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	httpSrv.Shutdown(shutdown)
	cancel()
	pool.Close()

	if doRestart {
		// Jalankan binary baru di proses yang sama (PID tetap), jadi systemd, Docker,
		// atau terminal tidak perlu tahu ada update.
		log.Printf("menjalankan ulang %s", exe)
		if err := syscall.Exec(exe, os.Args, os.Environ()); err != nil {
			log.Fatalf("restart gagal: %v (jalankan ulang service secara manual)", err)
		}
	}
}
