package updater

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestNewer(t *testing.T) {
	cases := []struct {
		latest, current string
		want            bool
	}{
		{"v1.2.0", "v1.1.9", true},
		{"v1.2.0", "v1.2.0", false},
		{"v1.10.0", "v1.9.0", true},
		{"v1.0.0", "dev", true},
		{"v1.0.0", "v1.0.0-rc.1", true},
		{"v1.0.0-rc.2", "v1.0.0-rc.1", true},
		{"v0.9.0", "v1.0.0", false},
		{"1.2.3", "v1.2.2", true},
	}
	for _, c := range cases {
		if got := Newer(c.latest, c.current); got != c.want {
			t.Errorf("Newer(%q, %q) = %v, want %v", c.latest, c.current, got, c.want)
		}
	}
}

func TestInWindow(t *testing.T) {
	u := New(Options{AutoFrom: 22, AutoTo: 4})
	at := func(h int) time.Time { return time.Date(2026, 1, 1, h, 0, 0, 0, time.UTC) }
	for h, want := range map[int]bool{21: false, 22: true, 23: true, 0: true, 3: true, 4: false, 12: false} {
		if got := u.inWindow(at(h)); got != want {
			t.Errorf("jam %d: %v, want %v", h, got, want)
		}
	}
	if !New(Options{}).inWindow(at(13)) {
		t.Error("jendela kosong seharusnya kapan saja")
	}
}

// fakeGitHub meniru API rilis GitHub dengan satu rilis berisi binary (script shell).
func fakeGitHub(t *testing.T, tag string, binary []byte, sum string) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	var base string
	mux.HandleFunc("/repos/acme/app/releases/latest", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{
			"tag_name": tag, "name": tag, "body": "catatan",
			"assets": []map[string]any{
				{"name": assetName(tag), "size": len(binary), "url": base + "/assets/1", "browser_download_url": base + "/dl/bin"},
				{"name": "SHA256SUMS", "size": 10, "url": base + "/assets/2", "browser_download_url": base + "/dl/sums"},
			},
		})
	})
	mux.HandleFunc("/assets/1", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Accept") != "application/octet-stream" {
			http.Error(w, "accept salah", 400)
			return
		}
		w.Write(binary)
	})
	mux.HandleFunc("/assets/2", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s  %s\n", sum, assetName(tag))
	})
	srv := httptest.NewServer(mux)
	base = srv.URL
	t.Cleanup(srv.Close)
	return srv
}

func assetName(tag string) string { return "pestcontrol-api_" + tag + "_linux_arm64.tar.gz" }

// targz membuat arsip rilis berisi binary pestcontrol-api.
func targz(t *testing.T, bin []byte) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	tw.WriteHeader(&tar.Header{Name: "pestcontrol-api", Mode: 0o755, Size: int64(len(bin)), Typeflag: tar.TypeReg})
	tw.Write(bin)
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func TestInstall(t *testing.T) {
	newBin := []byte("#!/bin/sh\necho v1.1.0 abc\n")
	archive := targz(t, newBin)
	h := sha256.Sum256(archive)
	gh := fakeGitHub(t, "v1.1.0", archive, hex.EncodeToString(h[:]))

	dir := t.TempDir()
	exe := filepath.Join(dir, "pestcontrol-api")
	os.WriteFile(exe, []byte("lama"), 0o755)
	restarted := make(chan struct{}, 1)
	u := New(Options{
		GitHub:  &GitHub{Repo: "acme/app", API: gh.URL},
		Current: "v1.0.0", Asset: assetName, BinaryName: "pestcontrol-api", ExePath: exe,
		Restart: func() { restarted <- struct{}{} },
	})
	if err := u.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	select {
	case <-restarted:
	case <-time.After(5 * time.Second):
		t.Fatalf("tidak restart, status: %+v", u.Status())
	}
	if b, _ := os.ReadFile(exe); string(b) != string(newBin) {
		t.Errorf("binary belum diganti: %q", b)
	}
	if b, _ := os.ReadFile(exe + ".bak"); string(b) != "lama" {
		t.Errorf("backup salah: %q", b)
	}
}

func TestInstallChecksumMismatch(t *testing.T) {
	gh := fakeGitHub(t, "v1.1.0", targz(t, []byte("#!/bin/sh\necho v1.1.0\n")), "0000")
	dir := t.TempDir()
	exe := filepath.Join(dir, "pestcontrol-api")
	os.WriteFile(exe, []byte("lama"), 0o755)
	u := New(Options{GitHub: &GitHub{Repo: "acme/app", API: gh.URL}, Current: "v1.0.0",
		Asset: assetName, BinaryName: "pestcontrol-api", ExePath: exe})
	if err := u.Start(context.Background()); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for u.Status().LastError == "" && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if u.Status().LastError == "" {
		t.Fatal("seharusnya gagal karena checksum")
	}
	if b, _ := os.ReadFile(exe); string(b) != "lama" {
		t.Errorf("binary lama tidak boleh berubah")
	}
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Errorf("file sementara tertinggal: %v", entries)
	}
}

func TestUpToDate(t *testing.T) {
	gh := fakeGitHub(t, "v1.0.0", []byte("x"), "x")
	u := New(Options{GitHub: &GitHub{Repo: "acme/app", API: gh.URL}, Current: "v1.0.0", ExePath: "/tmp/x"})
	if err := u.Start(context.Background()); err != ErrUpToDate {
		t.Fatalf("err = %v, want ErrUpToDate", err)
	}
}
