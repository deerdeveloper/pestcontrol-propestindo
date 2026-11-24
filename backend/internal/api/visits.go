package api

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/httpx"
)

type rawJSON = json.RawMessage

// visitInfo adalah data ringkas kunjungan untuk pengecekan akses dan status.
type visitInfo struct {
	ID           string
	Status       string
	TechnicianID *string
	CustomerID   string
	ReportID     *string
}

func (s *Server) loadVisit(ctx context.Context, id string) (visitInfo, error) {
	var v visitInfo
	err := s.db.QueryRow(ctx, `SELECT v.id, v.status, v.technician_id, s.customer_id, r.id
		FROM visits v JOIN sites s ON s.id = v.site_id LEFT JOIN visit_reports r ON r.visit_id = v.id
		WHERE v.id = $1`, id).Scan(&v.ID, &v.Status, &v.TechnicianID, &v.CustomerID, &v.ReportID)
	return v, err
}

// canView: staf melihat semua, teknisi hanya tugasnya, pelanggan hanya laporan terbit miliknya.
func canView(u auth.User, v visitInfo) bool {
	switch {
	case u.Is(auth.Staff...):
		return true
	case u.Is(auth.RoleTechnician):
		return v.TechnicianID != nil && *v.TechnicianID == u.ID
	case u.Is(auth.RoleCustomer):
		return v.CustomerID == u.CustomerID && v.Status == "published"
	}
	return false
}

// canEditReport: teknisi saat mengerjakan atau revisi, staf saat review (koreksi).
func canEditReport(u auth.User, v visitInfo) bool {
	switch {
	case u.Is(auth.RoleTechnician):
		return v.TechnicianID != nil && *v.TechnicianID == u.ID && (v.Status == "in_progress" || v.Status == "revision")
	case u.Is(auth.Staff...):
		return v.Status == "in_progress" || v.Status == "pending_review" || v.Status == "revision"
	}
	return false
}

func (s *Server) visitFor(r *http.Request, check func(auth.User, visitInfo) bool) (visitInfo, error) {
	v, err := s.loadVisit(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		return v, err
	}
	u := auth.FromContext(r.Context())
	if !canView(u, v) {
		return v, httpx.ErrNotFound
	}
	if check != nil && !check(u, v) {
		return v, httpx.E(http.StatusConflict, "kunjungan dengan status '"+v.Status+"' tidak bisa diubah oleh Anda")
	}
	return v, nil
}

const visitListSQL = `SELECT coalesce(jsonb_agg(jsonb_build_object(
		'id', v.id, 'visit_type', v.visit_type, 'scheduled_date', v.scheduled_date, 'status', v.status,
		'notes', v.notes, 'site_id', s.id, 'site_name', s.name, 'site_address', s.address,
		'customer_id', c.id, 'customer_name', c.name, 'technician_id', u.id, 'technician_name', u.name,
		'report_no', r.report_no, 'submitted_at', r.submitted_at, 'published_at', r.published_at
	) ORDER BY v.scheduled_date, c.name), '[]')
	FROM visits v JOIN sites s ON s.id = v.site_id JOIN customers c ON c.id = s.customer_id
	LEFT JOIN users u ON u.id = v.technician_id LEFT JOIN visit_reports r ON r.visit_id = v.id`

func (s *Server) listVisits(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	var out []byte
	err := s.db.QueryRow(r.Context(), visitListSQL+`
		WHERE ($1 = '' OR v.scheduled_date >= $1::date) AND ($2 = '' OR v.scheduled_date <= $2::date)
		  AND ($3 = '' OR v.status = $3) AND ($4 = '' OR v.technician_id::text = $4)
		  AND ($5 = '' OR v.site_id::text = $5) AND ($6 = '' OR c.id::text = $6)`,
		q.Get("from"), q.Get("to"), q.Get("status"), q.Get("technician_id"), q.Get("site_id"), q.Get("customer_id")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) myVisits(w http.ResponseWriter, r *http.Request) error {
	q := r.URL.Query()
	var out []byte
	err := s.db.QueryRow(r.Context(), visitListSQL+`
		WHERE v.technician_id = $1 AND v.status <> 'cancelled'
		  AND ($2 = '' OR v.scheduled_date >= $2::date) AND ($3 = '' OR v.scheduled_date <= $3::date)`,
		auth.FromContext(r.Context()).ID, q.Get("from"), q.Get("to")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

type visitInput struct {
	SiteID        *string `json:"site_id"`
	TechnicianID  *string `json:"technician_id"`
	VisitType     *string `json:"visit_type"`
	ScheduledDate *string `json:"scheduled_date"`
	Notes         *string `json:"notes"`
	Status        *string `json:"status"`
}

func (s *Server) createVisit(w http.ResponseWriter, r *http.Request) error {
	var in visitInput
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if in.SiteID == nil || in.VisitType == nil || in.ScheduledDate == nil {
		return httpx.E(http.StatusBadRequest, "lokasi, tipe kunjungan, dan tanggal wajib diisi")
	}
	if err := s.checkTechnician(r.Context(), in.TechnicianID); err != nil {
		return err
	}
	var id string
	err := s.db.QueryRow(r.Context(), `INSERT INTO visits (site_id, technician_id, visit_type, scheduled_date, notes)
		VALUES ($1, $2, $3, $4::date, $5) RETURNING id`,
		in.SiteID, in.TechnicianID, in.VisitType, in.ScheduledDate, in.Notes).Scan(&id)
	if err != nil {
		return err
	}
	s.audit(r, "create", "visits", id, in)
	return s.writeDocument(w, r.Context(), id, http.StatusCreated)
}

func (s *Server) checkTechnician(ctx context.Context, id *string) error {
	if id == nil {
		return nil
	}
	var ok bool
	if err := s.db.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM users WHERE id::text = $1 AND role = 'technician' AND active)`, *id).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return httpx.E(http.StatusBadRequest, "teknisi tidak ditemukan atau tidak aktif")
	}
	return nil
}

func (s *Server) updateVisit(w http.ResponseWriter, r *http.Request) error {
	var in visitInput
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	v, err := s.loadVisit(r.Context(), chi.URLParam(r, "id"))
	if err != nil {
		return err
	}
	if v.Status == "published" {
		return httpx.E(http.StatusConflict, "laporan sudah terbit, kunjungan tidak bisa diubah")
	}
	// Dari endpoint ini status hanya boleh dibatalkan atau dikembalikan ke terjadwal.
	if in.Status != nil && *in.Status != "cancelled" && *in.Status != "scheduled" {
		return httpx.E(http.StatusBadRequest, "status hanya bisa diubah ke 'cancelled' atau 'scheduled' di sini")
	}
	if err := s.checkTechnician(r.Context(), in.TechnicianID); err != nil {
		return err
	}
	_, err = s.db.Exec(r.Context(), `UPDATE visits SET technician_id = coalesce($2, technician_id),
		visit_type = coalesce($3, visit_type), scheduled_date = coalesce($4::date, scheduled_date),
		notes = coalesce($5, notes), status = coalesce($6, status), site_id = coalesce($7, site_id), updated_at = now()
		WHERE id = $1`, v.ID, in.TechnicianID, in.VisitType, in.ScheduledDate, in.Notes, in.Status, in.SiteID)
	if err != nil {
		return err
	}
	s.audit(r, "update", "visits", v.ID, in)
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

func (s *Server) writeDocument(w http.ResponseWriter, ctx context.Context, visitID string, status int) error {
	var out []byte
	if err := s.db.QueryRow(ctx, `SELECT report_document($1)`, visitID).Scan(&out); err != nil {
		return err
	}
	if out == nil {
		return httpx.ErrNotFound
	}
	httpx.RawJSON(w, status, out)
	return nil
}

func (s *Server) getVisit(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, nil)
	if err != nil {
		return err
	}
	return s.writeDocument(w, r.Context(), v.ID, http.StatusOK)
}

// visitBundle berisi semua yang dibutuhkan teknisi untuk bekerja offline di lokasi:
// dokumen kunjungan, area, stasiun, kontak, temuan terakhir, dan rekomendasi yang belum selesai.
func (s *Server) visitBundle(w http.ResponseWriter, r *http.Request) error {
	v, err := s.visitFor(r, func(u auth.User, _ visitInfo) bool { return !u.Is(auth.RoleCustomer) })
	if err != nil {
		return err
	}
	var out []byte
	err = s.db.QueryRow(r.Context(), `
		WITH vv AS (SELECT * FROM visits WHERE id = $1),
		last_report AS (
			SELECT r.id, v2.scheduled_date FROM visit_reports r JOIN visits v2 ON v2.id = r.visit_id
			WHERE v2.site_id = (SELECT site_id FROM vv) AND v2.status = 'published' AND v2.id <> $1
			ORDER BY v2.scheduled_date DESC LIMIT 1)
		SELECT jsonb_build_object(
			'document', report_document($1),
			'areas', (SELECT coalesce(jsonb_agg(to_jsonb(a) ORDER BY a.name), '[]') FROM areas a
			          WHERE a.site_id = (SELECT site_id FROM vv) AND a.active),
			'stations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', st.id, 'code', st.code, 'qr_value', st.qr_value,
			             'area_id', st.area_id, 'area_name', a.name, 'equipment_type_id', st.equipment_type_id,
			             'equipment_type', et.name) ORDER BY st.code), '[]')
			             FROM stations st JOIN equipment_types et ON et.id = st.equipment_type_id
			             LEFT JOIN areas a ON a.id = st.area_id
			             WHERE st.site_id = (SELECT site_id FROM vv) AND st.active),
			'contacts', (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.is_primary DESC, c.name), '[]')
			             FROM site_contacts c WHERE c.site_id = (SELECT site_id FROM vv)),
			'previous_visit_date', (SELECT scheduled_date FROM last_report),
			'previous_findings', (SELECT coalesce(jsonb_agg(jsonb_build_object('pest_name_id', p.name_id,
			             'area_name', coalesce(a.name, f.area_text), 'level', f.level, 'is_active', f.is_active)), '[]')
			             FROM report_findings f JOIN pest_types p ON p.id = f.pest_type_id
			             LEFT JOIN areas a ON a.id = f.area_id WHERE f.report_id = (SELECT id FROM last_report)),
			'open_recommendations', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', rc.id, 'category', rc.category,
			             'risk_finding', rc.risk_finding, 'recommendation', rc.recommendation,
			             'visit_date', v2.scheduled_date) ORDER BY v2.scheduled_date DESC), '[]')
			             FROM report_recommendations rc JOIN visit_reports r ON r.id = rc.report_id
			             JOIN visits v2 ON v2.id = r.visit_id
			             WHERE v2.site_id = (SELECT site_id FROM vv) AND v2.status = 'published'
			               AND rc.customer_status = 'open' AND v2.id <> $1)
		)`, v.ID).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}
