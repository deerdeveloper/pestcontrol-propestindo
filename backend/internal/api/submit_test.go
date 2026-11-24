package api

// Uji alur kirim laporan dari aplikasi teknisi, termasuk pengiriman ulang dari antrian
// offline. Butuh PostgreSQL kosong; dilewati jika TEST_DATABASE_URL tidak diisi:
//
//	TEST_DATABASE_URL=postgres://pest:pest@localhost:5432/pest_test?sslmode=disable go test ./internal/api/

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"

	"github.com/google/uuid"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/config"
	"github.com/propestindo/pestcontrol/internal/db"
	"github.com/propestindo/pestcontrol/internal/pdf"
	"github.com/propestindo/pestcontrol/internal/storage"
	"github.com/propestindo/pestcontrol/migrations"
)

type testEnv struct {
	t     *testing.T
	srv   *httptest.Server
	token string
	visit string
}

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL tidak diisi")
	}
	ctx := context.Background()
	pool, err := db.Connect(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if err := db.Migrate(ctx, pool, migrations.FS); err != nil {
		t.Fatal(err)
	}

	// Data minimal: pelanggan, lokasi, teknisi, satu kunjungan terjadwal.
	email := "tek-" + uuid.NewString()[:8] + "@test.local"
	hash, _ := auth.HashPassword("rahasia123")
	var customer, site, tech, visit string
	q := func(sql string, dst *string, args ...any) {
		t.Helper()
		if err := pool.QueryRow(ctx, sql, args...).Scan(dst); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
	}
	q(`INSERT INTO customers (name) VALUES ('PT Uji') RETURNING id`, &customer)
	q(`INSERT INTO sites (customer_id, name, address) VALUES ($1, 'Lokasi Uji', 'Jl. Uji') RETURNING id`, &site, customer)
	q(`INSERT INTO users (email, password_hash, name, role) VALUES ($1, $2, 'Teknisi Uji', 'technician') RETURNING id`, &tech, email, hash)
	q(`INSERT INTO visits (site_id, technician_id, visit_type, scheduled_date) VALUES ($1, $2, 'routine_monthly', current_date) RETURNING id`, &visit, site, tech)

	cfg := config.Load()
	cfg.JWTSecret = "uji"
	s := NewServer(cfg, pool, storage.Local{Root: t.TempDir()}, pdf.New("chromium", "Uji"))
	srv := httptest.NewServer(s.Routes())
	t.Cleanup(srv.Close)

	e := &testEnv{t: t, srv: srv, visit: visit}
	var login struct{ Token string }
	e.json(http.MethodPost, "/api/auth/login", map[string]string{"email": email, "password": "rahasia123"}, http.StatusOK, &login)
	e.token = login.Token
	return e
}

func (e *testEnv) do(req *http.Request, want int, out any) {
	e.t.Helper()
	if e.token != "" {
		req.Header.Set("Authorization", "Bearer "+e.token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	var body bytes.Buffer
	body.ReadFrom(res.Body)
	if res.StatusCode != want {
		e.t.Fatalf("%s %s: status %d, ingin %d: %s", req.Method, req.URL.Path, res.StatusCode, want, body.String())
	}
	if out != nil {
		if err := json.Unmarshal(body.Bytes(), out); err != nil {
			e.t.Fatalf("%s: %v", body.String(), err)
		}
	}
}

func (e *testEnv) json(method, path string, in any, want int, out any) {
	e.t.Helper()
	b, _ := json.Marshal(in)
	req, _ := http.NewRequest(method, e.srv.URL+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	e.do(req, want, out)
}

func (e *testEnv) upload(path string, fields map[string]string, want int) {
	e.t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for k, v := range fields {
		mw.WriteField(k, v)
	}
	fw, _ := mw.CreateFormFile("file", "ttd.png")
	png.Encode(fw, image.NewRGBA(image.Rect(0, 0, 20, 10)))
	mw.Close()
	req, _ := http.NewRequest(http.MethodPost, e.srv.URL+path, &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	e.do(req, want, nil)
}

func (e *testEnv) status() string {
	var doc struct {
		Visit struct{ Status string } `json:"visit"`
	}
	e.json(http.MethodGet, "/api/visits/"+e.visit, nil, http.StatusOK, &doc)
	return doc.Visit.Status
}

// Urutan persis seperti antrian aplikasi: check-in, isi laporan, tanda tangan teknisi,
// tanda tangan PIC, kirim. Lalu seluruh antrian diulang seperti setelah sinyal putus.
func TestSubmitFlowFromAppIsRetrySafe(t *testing.T) {
	e := newTestEnv(t)
	base := "/api/visits/" + e.visit
	report := map[string]any{"general_notes": "uji", "findings": []any{}, "treatments": []any{},
		"recommendations": []any{}, "station_checks": []any{}}

	e.json(http.MethodPost, base+"/start", map[string]any{"started_at": "2026-11-24T03:00:00.000Z"}, http.StatusOK, nil)
	if got := e.status(); got != "in_progress" {
		t.Fatalf("status setelah check-in %q", got)
	}
	e.json(http.MethodPut, base+"/report", report, http.StatusOK, nil)
	e.upload(base+"/signatures", map[string]string{"signer_role": "technician", "signer_name": "Teknisi", "signed_at": "2026-11-24T03:31:00.123456Z"}, http.StatusCreated)
	e.upload(base+"/signatures", map[string]string{"signer_role": "pic", "signer_name": "PIC", "signed_at": "2026-11-24T03:32:00.123456Z"}, http.StatusCreated)

	// Isi laporan terkunci setelah PIC tanda tangan; aplikasi mengenalinya dari kode error.
	var locked struct{ Code string }
	e.json(http.MethodPut, base+"/report", report, http.StatusConflict, &locked)
	if locked.Code != "report_locked" {
		t.Fatalf("kode error %q, ingin report_locked", locked.Code)
	}

	e.json(http.MethodPost, base+"/submit", nil, http.StatusOK, nil)
	if got := e.status(); got != "pending_review" {
		t.Fatalf("status setelah kirim %q, ingin pending_review", got)
	}

	// Kiriman ulang (balasan pertama hilang) tidak boleh gagal, supaya antrian tidak macet.
	e.json(http.MethodPost, base+"/start", map[string]any{}, http.StatusOK, nil)
	e.json(http.MethodPost, base+"/submit", nil, http.StatusOK, nil)
	if got := e.status(); got != "pending_review" {
		t.Fatalf("status setelah kirim ulang %q", got)
	}
}

func TestSubmitNeedsTechnicianSignature(t *testing.T) {
	e := newTestEnv(t)
	base := "/api/visits/" + e.visit
	e.json(http.MethodPost, base+"/start", map[string]any{}, http.StatusOK, nil)
	e.json(http.MethodPost, base+"/submit", nil, http.StatusBadRequest, nil)
	if got := e.status(); got != "in_progress" {
		t.Fatalf("status %q, ingin tetap in_progress", got)
	}
}
