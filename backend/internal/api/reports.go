package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/httpx"
	"github.com/propestindo/pestcontrol/internal/pdf"
)

// startVisit dipanggil teknisi saat check-in di lokasi. Aman dipanggil ulang (offline retry).
func (s *Server) startVisit(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, func(u auth.User, v visitInfo) bool {
		return v.Status == "scheduled" || v.Status == "in_progress" || v.Status == "revision" ||
			v.Status == "pending_review" || v.Status == "published"
	})
	if err != nil {
		return err
	}
	if v.Status == "pending_review" || v.Status == "published" {
		// Check-in yang terkirim ulang setelah laporan dikirim: tidak ada yang perlu diubah.
		return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
	}
	var in struct {
		StartedAt *time.Time `json:"started_at"`
		Lat       *float64   `json:"lat"`
		Lng       *float64   `json:"lng"`
	}
	if r.ContentLength != 0 {
		if err := httpx.Decode(r, &in); err != nil {
			return err
		}
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	if _, err := tx.Exec(r.Context(), `INSERT INTO visit_reports (visit_id, started_at, checkin_lat, checkin_lng)
		VALUES ($1, coalesce($2, now()), $3, $4) ON CONFLICT (visit_id) DO NOTHING`, v.ID, in.StartedAt, in.Lat, in.Lng); err != nil {
		return err
	}
	if _, err := tx.Exec(r.Context(), `UPDATE visits SET status = 'in_progress', updated_at = now()
		WHERE id = $1 AND status = 'scheduled'`, v.ID); err != nil {
		return err
	}
	if err := tx.Commit(r.Context()); err != nil {
		return err
	}
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

type reportInput struct {
	PICName         *string         `json:"pic_name"`
	GeneralNotes    *string         `json:"general_notes"`
	StartedAt       *time.Time      `json:"started_at"`
	FinishedAt      *time.Time      `json:"finished_at"`
	Findings        json.RawMessage `json:"findings"`
	Treatments      json.RawMessage `json:"treatments"`
	Recommendations json.RawMessage `json:"recommendations"`
	StationChecks   json.RawMessage `json:"station_checks"`
}

// Setiap daftar baris diganti utuh. Id baris dari aplikasi dipertahankan supaya foto
// yang diunggah untuk temuan/rekomendasi tetap terhubung.
var childInserts = []struct {
	field func(*reportInput) json.RawMessage
	table string
	sql   string
}{
	{func(i *reportInput) json.RawMessage { return i.Findings }, "report_findings", `
		INSERT INTO report_findings (id, report_id, pest_type_id, area_id, area_text, level, is_active, remarks, sort_order)
		SELECT coalesce(x.id, gen_random_uuid()), $1, x.pest_type_id, x.area_id, x.area_text, x.level,
		       coalesce(x.is_active, true), x.remarks, e.ord
		FROM jsonb_array_elements($2::jsonb) WITH ORDINALITY e(val, ord),
		     LATERAL jsonb_populate_record(NULL::report_findings, e.val) x`},
	{func(i *reportInput) json.RawMessage { return i.Treatments }, "report_treatments", `
		INSERT INTO report_treatments (id, report_id, method_id, area_id, area_text, chemical_id, dose_text, quantity_used, equipment, sort_order)
		SELECT coalesce(x.id, gen_random_uuid()), $1, x.method_id, x.area_id, x.area_text, x.chemical_id, x.dose_text,
		       x.quantity_used, x.equipment, e.ord
		FROM jsonb_array_elements($2::jsonb) WITH ORDINALITY e(val, ord),
		     LATERAL jsonb_populate_record(NULL::report_treatments, e.val) x`},
	{func(i *reportInput) json.RawMessage { return i.Recommendations }, "report_recommendations", `
		INSERT INTO report_recommendations (id, report_id, category, risk_finding, recommendation, sort_order)
		SELECT coalesce(x.id, gen_random_uuid()), $1, x.category, x.risk_finding, x.recommendation, e.ord
		FROM jsonb_array_elements($2::jsonb) WITH ORDINALITY e(val, ord),
		     LATERAL jsonb_populate_record(NULL::report_recommendations, e.val) x`},
	{func(i *reportInput) json.RawMessage { return i.StationChecks }, "report_station_checks", `
		INSERT INTO report_station_checks (id, report_id, station_id, status, bait_consumption, finding)
		SELECT coalesce(x.id, gen_random_uuid()), $1, x.station_id, x.status, coalesce(x.bait_consumption, 'none'), x.finding
		FROM jsonb_array_elements($2::jsonb) WITH ORDINALITY e(val, ord),
		     LATERAL jsonb_populate_record(NULL::report_station_checks, e.val) x`},
}

func (s *Server) saveReport(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, canEditReport)
	if err != nil {
		return err
	}
	if v.ReportID == nil {
		return httpx.E(http.StatusConflict, "kunjungan belum dimulai (check-in)")
	}
	u := auth.FromContext(r.Context())
	if u.Is(auth.RoleTechnician) && v.Status == "in_progress" {
		var signed bool
		if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM signatures WHERE report_id=$1 AND signer_role='pic')`,
			*v.ReportID).Scan(&signed); err != nil {
			return err
		}
		if signed {
			// Aplikasi selalu mengirim isi laporan sebelum tanda tangan PIC, jadi isi yang
			// tersimpan di server sudah versi terakhir. Kode ini membuat aplikasi tahu
			// bahwa pengiriman ulang boleh dilewati.
			return httpx.EC(http.StatusConflict, "report_locked", "laporan sudah ditandatangani PIC dan terkunci")
		}
	}
	var in reportInput
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	if _, err := tx.Exec(r.Context(), `UPDATE visit_reports SET pic_name = coalesce($2, pic_name),
		general_notes = coalesce($3, general_notes), started_at = coalesce($4, started_at),
		finished_at = coalesce($5, finished_at), updated_at = now() WHERE id = $1`,
		*v.ReportID, in.PICName, in.GeneralNotes, in.StartedAt, in.FinishedAt); err != nil {
		return err
	}
	for _, c := range childInserts {
		raw := c.field(&in)
		if len(raw) == 0 || string(raw) == "null" {
			continue // daftar tidak dikirim berarti tidak diubah
		}
		if _, err := tx.Exec(r.Context(), fmt.Sprintf(`DELETE FROM %s WHERE report_id = $1`, c.table), *v.ReportID); err != nil {
			return err
		}
		if _, err := tx.Exec(r.Context(), c.sql, *v.ReportID, string(raw)); err != nil {
			return fmt.Errorf("%s: %w", c.table, err)
		}
	}
	if err := tx.Commit(r.Context()); err != nil {
		return err
	}
	s.audit(r, "save_report", "visit_reports", *v.ReportID, nil)
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

const maxUpload = 15 << 20

var imageExt = map[string]string{"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp"}

// readImage membaca field "file" dari form multipart dan memastikan isinya gambar.
func readImage(r *http.Request) ([]byte, string, error) {
	r.Body = http.MaxBytesReader(nil, r.Body, maxUpload)
	if err := r.ParseMultipartForm(maxUpload); err != nil {
		return nil, "", httpx.E(http.StatusBadRequest, "upload tidak valid atau lebih dari 15 MB")
	}
	f, _, err := r.FormFile("file")
	if err != nil {
		return nil, "", httpx.E(http.StatusBadRequest, "field 'file' wajib diisi")
	}
	defer f.Close()
	b, err := io.ReadAll(f)
	if err != nil {
		return nil, "", err
	}
	ct := http.DetectContentType(b)
	if _, ok := imageExt[ct]; !ok {
		return nil, "", httpx.E(http.StatusBadRequest, "file harus gambar JPG, PNG, atau WEBP")
	}
	return b, ct, nil
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func (s *Server) uploadAttachment(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, canEditReport)
	if err != nil {
		return err
	}
	if v.ReportID == nil {
		return httpx.E(http.StatusConflict, "kunjungan belum dimulai (check-in)")
	}
	b, ct, err := readImage(r)
	if err != nil {
		return err
	}
	ownerType := r.FormValue("owner_type")
	if ownerType == "" {
		ownerType = "report"
	}
	path, err := s.store.Save(filepath.Join("reports", *v.ReportID), imageExt[ct], bytes.NewReader(b))
	if err != nil {
		return err
	}
	var id string
	err = s.db.QueryRow(r.Context(), `INSERT INTO attachments (id, report_id, owner_type, owner_id, file_path, content_type, caption)
		VALUES (coalesce($1::uuid, gen_random_uuid()), $2, $3, $4, $5, $6, $7)
		ON CONFLICT (id) DO UPDATE SET caption = EXCLUDED.caption RETURNING id`,
		nullable(r.FormValue("id")), *v.ReportID, ownerType, nullable(r.FormValue("owner_id")), path, ct,
		nullable(r.FormValue("caption"))).Scan(&id)
	if err != nil {
		return err
	}
	httpx.JSON(w, http.StatusCreated, map[string]string{"id": id})
	return nil
}

func (s *Server) uploadSignature(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, canEditReport)
	if err != nil {
		return err
	}
	if v.ReportID == nil {
		return httpx.E(http.StatusConflict, "kunjungan belum dimulai (check-in)")
	}
	b, ct, err := readImage(r)
	if err != nil {
		return err
	}
	role, name := r.FormValue("signer_role"), strings.TrimSpace(r.FormValue("signer_name"))
	if (role != "technician" && role != "pic") || name == "" {
		return httpx.E(http.StatusBadRequest, "signer_role (technician/pic) dan signer_name wajib diisi")
	}
	path, err := s.store.Save(filepath.Join("signatures", *v.ReportID), imageExt[ct], bytes.NewReader(b))
	if err != nil {
		return err
	}
	signedAt := time.Now()
	if t, err := time.Parse(time.RFC3339, r.FormValue("signed_at")); err == nil {
		signedAt = t
	}
	var id string
	err = s.db.QueryRow(r.Context(), `INSERT INTO signatures (report_id, signer_role, signer_name, file_path, signed_at)
		VALUES ($1, $2, $3, $4, $5) ON CONFLICT (report_id, signer_role)
		DO UPDATE SET signer_name = EXCLUDED.signer_name, file_path = EXCLUDED.file_path, signed_at = EXCLUDED.signed_at
		RETURNING id`, *v.ReportID, role, name, path, signedAt).Scan(&id)
	if err != nil {
		return err
	}
	if role == "pic" {
		if _, err := s.db.Exec(r.Context(), `UPDATE visit_reports SET pic_name = $2 WHERE id = $1`, *v.ReportID, name); err != nil {
			return err
		}
	}
	httpx.JSON(w, http.StatusCreated, map[string]string{"id": id})
	return nil
}

func (s *Server) submitVisit(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, nil)
	if err != nil {
		return err
	}
	// Aman dipanggil ulang: jika kiriman sebelumnya sudah sampai tapi balasannya hilang
	// (sinyal putus), aplikasi akan mengulang. Jangan sampai antrian di HP macet karena itu.
	if v.Status == "pending_review" || v.Status == "published" {
		return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
	}
	if !canEditReport(auth.FromContext(r.Context()), v) {
		return httpx.E(http.StatusConflict, "kunjungan dengan status '"+v.Status+"' tidak bisa dikirim")
	}
	if v.ReportID == nil {
		return httpx.E(http.StatusConflict, "kunjungan belum dimulai (check-in)")
	}
	var hasTechSig bool
	if err := s.db.QueryRow(r.Context(), `SELECT EXISTS(SELECT 1 FROM signatures WHERE report_id=$1 AND signer_role='technician')`,
		*v.ReportID).Scan(&hasTechSig); err != nil {
		return err
	}
	if !hasTechSig {
		return httpx.E(http.StatusBadRequest, "tanda tangan teknisi wajib sebelum laporan dikirim")
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	if _, err := tx.Exec(r.Context(), `UPDATE visit_reports SET submitted_at = now(), finished_at = coalesce(finished_at, now()),
		updated_at = now() WHERE id = $1`, *v.ReportID); err != nil {
		return err
	}
	if _, err := tx.Exec(r.Context(), `UPDATE visits SET status = 'pending_review', updated_at = now() WHERE id = $1`, v.ID); err != nil {
		return err
	}
	if err := tx.Commit(r.Context()); err != nil {
		return err
	}
	s.audit(r, "submit", "visits", v.ID, nil)
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

func (s *Server) returnVisit(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, func(_ auth.User, v visitInfo) bool { return v.Status == "pending_review" })
	if err != nil {
		return err
	}
	var in struct {
		Notes string `json:"notes"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if strings.TrimSpace(in.Notes) == "" {
		return httpx.E(http.StatusBadRequest, "catatan revisi wajib diisi")
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	if _, err := tx.Exec(r.Context(), `UPDATE visit_reports SET review_notes = $2, updated_at = now() WHERE id = $1`, *v.ReportID, in.Notes); err != nil {
		return err
	}
	if _, err := tx.Exec(r.Context(), `UPDATE visits SET status = 'revision', updated_at = now() WHERE id = $1`, v.ID); err != nil {
		return err
	}
	if err := tx.Commit(r.Context()); err != nil {
		return err
	}
	s.audit(r, "return", "visits", v.ID, in)
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

// publishVisit memberi nomor laporan, membuat PDF, dan menerbitkan laporan ke pelanggan.
func (s *Server) publishVisit(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, func(_ auth.User, v visitInfo) bool { return v.Status == "pending_review" })
	if err != nil {
		return err
	}
	ctx := r.Context()
	tx, err := s.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	_, err = tx.Exec(ctx, `UPDATE visit_reports SET
		report_no = coalesce(report_no, 'PPI/LKP/' || to_char(now() AT TIME ZONE 'Asia/Jakarta', 'YYYY/MM/') ||
		            lpad(nextval('report_number_seq')::text, 4, '0')),
		published_at = now(), published_by = $2, updated_at = now() WHERE id = $1`,
		*v.ReportID, auth.FromContext(ctx).ID)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE visits SET status = 'published', updated_at = now() WHERE id = $1`, v.ID); err != nil {
		return err
	}
	file, err := s.renderPDF(ctx, tx, v.ID)
	if err != nil {
		return fmt.Errorf("generate PDF: %w", err)
	}
	path, err := s.store.Save("pdf", ".pdf", bytes.NewReader(file))
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE visit_reports SET pdf_path = $2 WHERE id = $1`, *v.ReportID, path); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	s.audit(r, "publish", "visits", v.ID, nil)
	return s.writeDocument(w, ctx, v.ID, http.StatusOK)
}

type queryer interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
}

func (s *Server) renderPDF(ctx context.Context, q queryer, visitID string) ([]byte, error) {
	var raw []byte
	if err := q.QueryRow(ctx, `SELECT report_document($1)`, visitID).Scan(&raw); err != nil {
		return nil, err
	}
	var doc pdf.Document
	if err := json.Unmarshal(raw, &doc); err != nil {
		return nil, err
	}
	// Lokasi file foto dan tanda tangan di disk, untuk ditanam ke PDF.
	files := map[string]string{}
	if doc.Report != nil {
		rows, err := q.Query(ctx, `SELECT id::text, file_path FROM attachments WHERE report_id = $1
			UNION ALL SELECT id::text, file_path FROM signatures WHERE report_id = $1`, doc.Report.ID)
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			var id, p string
			if err := rows.Scan(&id, &p); err != nil {
				rows.Close()
				return nil, err
			}
			files[id] = s.store.AbsPath(p)
		}
		rows.Close()
	}
	return s.pdf.Render(ctx, doc, files)
}

// visitPDF mengunduh PDF laporan terbit. Staf bisa melihat pratinjau (?preview=1) sebelum terbit.
func (s *Server) visitPDF(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, nil)
	if err != nil {
		return err
	}
	u := auth.FromContext(r.Context())
	var body []byte
	var name string
	if v.Status == "published" && r.URL.Query().Get("preview") == "" {
		var path, no string
		if err := s.db.QueryRow(r.Context(), `SELECT coalesce(pdf_path, ''), coalesce(report_no, '') FROM visit_reports WHERE id = $1`,
			*v.ReportID).Scan(&path, &no); err != nil {
			return err
		}
		if path == "" {
			return httpx.ErrNotFound
		}
		f, err := s.store.Open(path)
		if err != nil {
			return err
		}
		defer f.Close()
		if body, err = io.ReadAll(f); err != nil {
			return err
		}
		name = strings.ReplaceAll(no, "/", "-") + ".pdf"
	} else {
		if !u.Is(auth.Staff...) {
			return httpx.ErrNotFound
		}
		if body, err = s.renderPDF(r.Context(), s.db, v.ID); err != nil {
			return err
		}
		name = "pratinjau-" + v.ID + ".pdf"
	}
	w.Header().Set("Content-Type", "application/pdf")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`inline; filename="%s"`, name))
	_, err = w.Write(body)
	return err
}

// serveFile mengirim foto (kind=attachments) atau tanda tangan (kind=signatures) setelah cek akses.
func (s *Server) serveFile(w http.ResponseWriter, r *http.Request) error {
	table := map[string]string{"attachments": "attachments", "signatures": "signatures"}[chi.URLParam(r, "kind")]
	if table == "" {
		return httpx.ErrNotFound
	}
	var path, visitID string
	err := s.db.QueryRow(r.Context(), fmt.Sprintf(`SELECT f.file_path, rp.visit_id FROM %s f
		JOIN visit_reports rp ON rp.id = f.report_id WHERE f.id = $1`, table), chi.URLParam(r, "id")).Scan(&path, &visitID)
	if err != nil {
		return err
	}
	v, err := s.loadVisit(r.Context(), visitID)
	if err != nil {
		return err
	}
	if !canView(auth.FromContext(r.Context()), v) {
		return httpx.ErrNotFound
	}
	w.Header().Set("Cache-Control", "private, max-age=86400")
	http.ServeFile(w, r, s.store.AbsPath(path))
	return nil
}
