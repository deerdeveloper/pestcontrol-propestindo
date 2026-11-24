// Package api berisi semua handler HTTP REST.
package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/config"
	"github.com/propestindo/pestcontrol/internal/httpx"
	"github.com/propestindo/pestcontrol/internal/landing"
	"github.com/propestindo/pestcontrol/internal/pdf"
	"github.com/propestindo/pestcontrol/internal/storage"
	"github.com/propestindo/pestcontrol/internal/updater"
)

type Server struct {
	cfg   config.Config
	db    *pgxpool.Pool
	auth  *auth.Manager
	store storage.Store
	pdf   *pdf.Renderer

	updater *updater.Updater
	web     http.Handler
}

func NewServer(cfg config.Config, db *pgxpool.Pool, store storage.Store, renderer *pdf.Renderer) *Server {
	return &Server{cfg: cfg, db: db, auth: auth.NewManager(cfg.JWTSecret, cfg.JWTTTL), store: store, pdf: renderer}
}

// WithUpdater memasang updater binary (fitur update dari halaman super admin dan update APK).
func (s *Server) WithUpdater(u *updater.Updater) *Server { s.updater = u; return s }

// WithWeb menyajikan aplikasi web di "/app/" (web yang tertanam di binary).
// Halaman publik (landing page) selalu disajikan di "/".
func (s *Server) WithWeb(h http.Handler) *Server { s.web = h; return s }

func (s *Server) Routes() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.RealIP, middleware.Logger, middleware.Recoverer)
	r.Use(s.cors)

	h := func(f httpx.Handler) http.Handler { return f }
	staff := auth.Require(auth.Staff...)
	admins := auth.Require(auth.RoleSuperAdmin, auth.RoleAdmin)

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte("ok")) })
	r.Method(http.MethodPost, "/api/auth/login", h(s.login))
	r.Method(http.MethodGet, "/api/version", h(s.version))
	r.Method(http.MethodGet, "/api/app/android", h(s.androidLatest))
	r.Method(http.MethodGet, "/api/app/android/apk", h(s.androidAPK))
	if s.web != nil {
		r.Get("/app", func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, "/app/", http.StatusMovedPermanently)
		})
		r.Handle("/app/*", http.StripPrefix("/app", s.web))
	}
	r.NotFound(landing.Handler().ServeHTTP)

	r.Route("/api", func(r chi.Router) {
		r.Use(s.auth.Middleware)
		r.Method(http.MethodGet, "/auth/me", h(s.me))
		r.Method(http.MethodGet, "/catalog", h(s.catalog))

		// Pengguna (admin)
		r.With(admins).Method(http.MethodGet, "/users", h(s.listUsers))
		r.With(admins).Method(http.MethodPost, "/users", h(s.createUser))
		r.With(admins).Method(http.MethodPatch, "/users/{id}", h(s.updateUser))

		// Update server (super admin)
		r.Route("/system/update", func(r chi.Router) {
			r.Use(auth.Require(auth.RoleSuperAdmin))
			r.Method(http.MethodGet, "/", h(s.updateStatus))
			r.Method(http.MethodPost, "/check", h(s.updateCheck))
			r.Method(http.MethodPost, "/apply", h(s.updateApply))
			r.Method(http.MethodPut, "/settings", h(s.updateSettings))
		})

		// Data master: staf boleh baca, admin boleh ubah
		r.Route("/master/{resource}", func(r chi.Router) {
			r.With(staff).Method(http.MethodGet, "/", h(s.masterList))
			r.With(admins).Method(http.MethodPost, "/", h(s.masterCreate))
			r.With(staff).Method(http.MethodGet, "/{id}", h(s.masterGet))
			r.With(admins).Method(http.MethodPatch, "/{id}", h(s.masterUpdate))
			r.With(admins).Method(http.MethodDelete, "/{id}", h(s.masterDelete))
		})

		// Kunjungan
		r.With(staff).Method(http.MethodGet, "/visits", h(s.listVisits))
		r.With(staff).Method(http.MethodPost, "/visits", h(s.createVisit))
		r.With(staff).Method(http.MethodPatch, "/visits/{id}", h(s.updateVisit))
		r.Method(http.MethodGet, "/visits/{id}", h(s.getVisit))
		r.Method(http.MethodGet, "/visits/{id}/bundle", h(s.visitBundle))
		r.Method(http.MethodGet, "/visits/{id}/pdf", h(s.visitPDF))

		// Alur teknisi
		r.With(auth.Require(auth.RoleTechnician)).Method(http.MethodGet, "/me/visits", h(s.myVisits))
		r.With(auth.Require(auth.RoleTechnician)).Method(http.MethodPost, "/visits/{id}/start", h(s.startVisit))
		r.Method(http.MethodPut, "/visits/{id}/report", h(s.saveReport))
		r.Method(http.MethodPost, "/visits/{id}/attachments", h(s.uploadAttachment))
		r.Method(http.MethodPost, "/visits/{id}/signatures", h(s.uploadSignature))
		r.With(auth.Require(auth.RoleTechnician)).Method(http.MethodPost, "/visits/{id}/submit", h(s.submitVisit))
		r.Method(http.MethodGet, "/files/{kind}/{id}", h(s.serveFile))

		// Review oleh staf
		r.With(staff).Method(http.MethodPost, "/visits/{id}/return", h(s.returnVisit))
		r.With(staff).Method(http.MethodPost, "/visits/{id}/publish", h(s.publishVisit))

		// Portal pelanggan
		r.Route("/portal", func(r chi.Router) {
			r.Use(auth.Require(auth.RoleCustomer))
			r.Method(http.MethodGet, "/sites", h(s.portalSites))
			r.Method(http.MethodGet, "/visits", h(s.portalVisits))
			r.Method(http.MethodGet, "/reports", h(s.portalReports))
			r.Method(http.MethodGet, "/recommendations", h(s.portalRecommendations))
			r.Method(http.MethodPatch, "/recommendations/{id}", h(s.portalUpdateRecommendation))
		})
	})
	return r
}

func (s *Server) cors(next http.Handler) http.Handler {
	allowed := strings.Split(s.cfg.CORSOrigins, ",")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		for _, a := range allowed {
			if a = strings.TrimSpace(a); a == "*" || a == origin {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				break
			}
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// audit mencatat perubahan data. Kegagalan hanya dicatat di log, tidak menggagalkan request.
func (s *Server) audit(r *http.Request, action, entity, id string, detail any) {
	u := auth.FromContext(r.Context())
	var d []byte
	if detail != nil {
		d, _ = json.Marshal(detail)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	var uid any
	if u.ID != "" {
		uid = u.ID
	}
	if _, err := s.db.Exec(ctx, `INSERT INTO audit_logs (user_id, action, entity, entity_id, detail)
		VALUES ($1, $2, $3, $4, $5)`, uid, action, entity, id, d); err != nil {
		log.Printf("audit log gagal: %v", err)
	}
}
