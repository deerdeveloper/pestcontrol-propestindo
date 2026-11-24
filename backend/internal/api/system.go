package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"strconv"
	"time"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/buildinfo"
	"github.com/propestindo/pestcontrol/internal/httpx"
	"github.com/propestindo/pestcontrol/internal/updater"
)

// androidAsset adalah nama file APK aplikasi teknisi di GitHub Release (pola tool/build.sh).
func androidAsset(tag string) string { return "propestindo-teknisi_" + tag + "_android.apk" }

const settingAutoUpdate = "server_auto_update"

// LoadSettings membaca pengaturan update otomatis dari database (jika pernah diubah di web).
func (s *Server) LoadSettings(ctx context.Context) {
	if s.updater == nil {
		return
	}
	var raw []byte
	if err := s.db.QueryRow(ctx, `SELECT value FROM app_settings WHERE key=$1`, settingAutoUpdate).Scan(&raw); err == nil {
		var v bool
		if json.Unmarshal(raw, &v) == nil {
			s.updater.SetAuto(v)
		}
	}
}

func (s *Server) version(w http.ResponseWriter, _ *http.Request) error {
	httpx.JSON(w, http.StatusOK, map[string]string{
		"version": buildinfo.Version, "commit": buildinfo.Commit, "date": buildinfo.Date,
	})
	return nil
}

func (s *Server) updateStatus(w http.ResponseWriter, _ *http.Request) error {
	httpx.JSON(w, http.StatusOK, map[string]any{
		"build":   map[string]string{"version": buildinfo.Version, "commit": buildinfo.Commit, "date": buildinfo.Date},
		"updater": s.updater.Status(),
	})
	return nil
}

func (s *Server) updateCheck(w http.ResponseWriter, r *http.Request) error {
	if _, err := s.updater.Check(r.Context()); err != nil {
		return httpx.E(http.StatusBadGateway, "gagal cek update: "+err.Error())
	}
	return s.updateStatus(w, r)
}

func (s *Server) updateApply(w http.ResponseWriter, r *http.Request) error {
	err := s.updater.Start(r.Context())
	switch {
	case errors.Is(err, updater.ErrBusy), errors.Is(err, updater.ErrUpToDate):
		return httpx.E(http.StatusConflict, err.Error())
	case err != nil:
		return httpx.E(http.StatusBadGateway, err.Error())
	}
	st := s.updater.Status()
	s.audit(r, "server_update", "system", "", map[string]any{"from": st.Current, "to": st.Latest.Tag})
	httpx.JSON(w, http.StatusAccepted, map[string]any{"updater": st})
	return nil
}

func (s *Server) updateSettings(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Auto *bool `json:"auto"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if in.Auto == nil {
		return httpx.E(http.StatusBadRequest, "isi field auto")
	}
	v, _ := json.Marshal(*in.Auto)
	u := auth.FromContext(r.Context())
	if _, err := s.db.Exec(r.Context(), `INSERT INTO app_settings (key, value, updated_by, updated_at)
		VALUES ($1, $2, $3, now())
		ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value, updated_by=EXCLUDED.updated_by, updated_at=now()`,
		settingAutoUpdate, v, u.ID); err != nil {
		return err
	}
	s.updater.SetAuto(*in.Auto)
	s.audit(r, "update_settings", "system", "", in)
	return s.updateStatus(w, r)
}

// androidLatest memberi info APK terbaru untuk aplikasi teknisi. Endpoint publik supaya
// aplikasi yang belum login atau yang sesinya habis tetap bisa update.
func (s *Server) androidLatest(w http.ResponseWriter, r *http.Request) error {
	if !s.updater.Enabled() {
		return httpx.E(http.StatusServiceUnavailable, "update aplikasi belum diatur di server")
	}
	rel, err := s.updater.Latest(r.Context(), 10*time.Minute)
	if err != nil {
		return httpx.E(http.StatusBadGateway, "gagal cek rilis: "+err.Error())
	}
	a, ok := rel.Asset(androidAsset(rel.Tag))
	if !ok {
		return httpx.E(http.StatusNotFound, "rilis "+rel.Tag+" belum punya APK")
	}
	sha := ""
	if sums, err := s.updater.Checksums(r.Context(), rel); err == nil {
		sha = sums[a.Name]
	}
	// Repo public: HP langsung unduh dari GitHub. Repo private: lewat server ini
	// (server yang memegang token), sumbernya tetap GitHub Release.
	url := a.DownloadURL
	if s.cfg.UpdateToken != "" {
		url = "/api/app/android/apk"
	}
	httpx.JSON(w, http.StatusOK, map[string]any{
		"version": rel.Tag, "notes": rel.Notes, "published_at": rel.PublishedAt,
		"size": a.Size, "sha256": sha, "download_url": url,
	})
	return nil
}

func (s *Server) androidAPK(w http.ResponseWriter, r *http.Request) error {
	if !s.updater.Enabled() {
		return httpx.E(http.StatusServiceUnavailable, "update aplikasi belum diatur di server")
	}
	rel, err := s.updater.Latest(r.Context(), 10*time.Minute)
	if err != nil {
		return httpx.E(http.StatusBadGateway, "gagal cek rilis: "+err.Error())
	}
	a, ok := rel.Asset(androidAsset(rel.Tag))
	if !ok {
		return httpx.E(http.StatusNotFound, "rilis "+rel.Tag+" belum punya APK")
	}
	body, size, err := s.updater.Open(r.Context(), a)
	if err != nil {
		return httpx.E(http.StatusBadGateway, "gagal unduh dari GitHub: "+err.Error())
	}
	defer body.Close()
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", `attachment; filename="propestindo-teknisi-`+rel.Tag+`.apk"`)
	if size > 0 {
		w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
	}
	if _, err := io.Copy(w, body); err != nil {
		log.Printf("kirim APK terputus: %v", err)
	}
	return nil
}
