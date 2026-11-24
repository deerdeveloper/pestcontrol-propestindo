// Package webui menyajikan aplikasi web Vue yang ikut tertanam di binary.
// Folder dist diisi oleh `make build-server` (salinan web/dist). Jika kosong,
// binary tetap jalan sebagai API saja dan web disajikan terpisah (nginx / Docker).
package webui

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var dist embed.FS

// Handler mengembalikan handler web, atau nil jika web tidak ikut di-build.
func Handler() http.Handler {
	root, err := fs.Sub(dist, "dist")
	if err != nil {
		return nil
	}
	if _, err := fs.Stat(root, "index.html"); err != nil {
		return nil
	}
	files := http.FileServer(http.FS(root))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if strings.HasPrefix(p, "api/") || p == "api" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"endpoint tidak ditemukan"}`))
			return
		}
		switch {
		case p == "sw.js" || p == "index.html" || p == "" || strings.HasPrefix(p, "workbox-") || p == "manifest.webmanifest":
			w.Header().Set("Cache-Control", "no-cache")
		case strings.HasPrefix(p, "assets/"):
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		}
		if p != "" {
			if _, err := fs.Stat(root, p); err == nil {
				files.ServeHTTP(w, r)
				return
			}
		}
		// Rute SPA (misalnya /visits/123) selalu dijawab dengan index.html.
		r2 := r.Clone(r.Context())
		r2.URL.Path = "/"
		w.Header().Set("Cache-Control", "no-cache")
		files.ServeHTTP(w, r2)
	})
}
