// Package landing menyajikan halaman publik (company profile) Propestindo di "/".
// Aplikasi web (admin, supervisor, portal pelanggan) pindah ke /app/.
//
// File halaman ada di folder static dan selalu ikut tertanam di binary, jadi
// landing page tetap tampil walaupun web Vue tidak ikut di-build.
package landing

import (
	"embed"
	"io/fs"
	"net/http"
	"path"
	"strings"
)

//go:embed static
var static embed.FS

// Rute lama aplikasi web sebelum pindah ke /app. Bookmark / tautan lama diarahkan ulang.
var legacyApp = []string{"login", "dashboard", "visits", "customers", "sites", "master", "users", "system", "portal"}

// swKill menggantikan service worker lama di /sw.js (dulu scope "/").
// Browser yang pernah memasang PWA lama akan mengambil file ini, lalu service worker
// lama dihapus beserta cache-nya sehingga landing page baru langsung tampil.
const swKill = `self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) await caches.delete(k);
    await self.registration.unregister();
    for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url);
  })());
});
`

// Handler menyajikan landing page, aset /site/*, ikon di root, dan pengalihan rute lama.
// Path lain yang tidak dikenal dijawab halaman 404.
func Handler() http.Handler {
	root, err := fs.Sub(static, "static")
	if err != nil {
		panic(err)
	}
	files := http.FileServer(http.FS(root))
	index, _ := fs.ReadFile(root, "index.html")
	notFound, _ := fs.ReadFile(root, "404.html")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
		if p == "." {
			p = ""
		}
		if p == "api" || strings.HasPrefix(p, "api/") {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error":"endpoint tidak ditemukan"}`))
			return
		}
		switch {
		case p == "" || p == "index.html":
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Header().Set("Cache-Control", "no-cache")
			if r.Method != http.MethodHead {
				w.Write(index)
			}
			return
		case p == "sw.js":
			w.Header().Set("Content-Type", "application/javascript")
			w.Header().Set("Cache-Control", "no-cache")
			w.Write([]byte(swKill))
			return
		case p == "favicon.ico" || p == "favicon.svg" || p == "apple-touch-icon.png" || p == "robots.txt" || p == "sitemap.xml":
			w.Header().Set("Cache-Control", "public, max-age=86400")
			files.ServeHTTP(w, r)
			return
		case strings.HasPrefix(p, "site/"):
			r2 := r.Clone(r.Context())
			r2.URL.Path = "/" + strings.TrimPrefix(p, "site/")
			if _, err := fs.Stat(root, strings.TrimPrefix(p, "site/")); err == nil && !strings.HasSuffix(p, ".html") {
				w.Header().Set("Cache-Control", "public, max-age=3600")
				files.ServeHTTP(w, r2)
				return
			}
		}
		first, _, _ := strings.Cut(p, "/")
		for _, l := range legacyApp {
			if first == l {
				target := "/app/" + p
				if r.URL.RawQuery != "" {
					target += "?" + r.URL.RawQuery
				}
				http.Redirect(w, r, target, http.StatusFound)
				return
			}
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusNotFound)
		w.Write(notFound)
	})
}
