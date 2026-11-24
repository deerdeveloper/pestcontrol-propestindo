package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/httpx"
)

// Semua query portal difilter dengan customer_id dari token, jadi pelanggan
// hanya pernah melihat data miliknya sendiri.

func (s *Server) portalSites(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name,
		'address', s.address, 'stations', (SELECT count(*) FROM stations st WHERE st.site_id = s.id AND st.active))
		ORDER BY s.name), '[]') FROM sites s WHERE s.customer_id = $1 AND s.active`,
		auth.FromContext(r.Context()).CustomerID).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) portalVisits(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT coalesce(jsonb_agg(jsonb_build_object('id', v.id,
		'scheduled_date', v.scheduled_date, 'visit_type', v.visit_type, 'status', v.status,
		'site_name', s.name, 'technician_name', u.name) ORDER BY v.scheduled_date), '[]')
		FROM visits v JOIN sites s ON s.id = v.site_id LEFT JOIN users u ON u.id = v.technician_id
		WHERE s.customer_id = $1 AND v.status IN ('scheduled','in_progress') AND v.scheduled_date >= current_date - 7`,
		auth.FromContext(r.Context()).CustomerID).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) portalReports(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT coalesce(jsonb_agg(jsonb_build_object('visit_id', v.id,
		'report_no', rp.report_no, 'scheduled_date', v.scheduled_date, 'visit_type', v.visit_type,
		'site_id', s.id, 'site_name', s.name, 'technician_name', u.name, 'published_at', rp.published_at,
		'active_findings', (SELECT count(*) FROM report_findings f WHERE f.report_id = rp.id AND f.is_active AND f.level <> 'none'),
		'open_recommendations', (SELECT count(*) FROM report_recommendations rc WHERE rc.report_id = rp.id AND rc.customer_status = 'open')
		) ORDER BY v.scheduled_date DESC), '[]')
		FROM visits v JOIN sites s ON s.id = v.site_id JOIN visit_reports rp ON rp.visit_id = v.id
		LEFT JOIN users u ON u.id = v.technician_id
		WHERE s.customer_id = $1 AND v.status = 'published' AND ($2 = '' OR s.id::text = $2)`,
		auth.FromContext(r.Context()).CustomerID, r.URL.Query().Get("site_id")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) portalRecommendations(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT coalesce(jsonb_agg(jsonb_build_object('id', rc.id,
		'category', rc.category, 'risk_finding', rc.risk_finding, 'recommendation', rc.recommendation,
		'customer_status', rc.customer_status, 'customer_note', rc.customer_note,
		'site_name', s.name, 'visit_id', v.id, 'visit_date', v.scheduled_date, 'report_no', rp.report_no
		) ORDER BY v.scheduled_date DESC), '[]')
		FROM report_recommendations rc JOIN visit_reports rp ON rp.id = rc.report_id
		JOIN visits v ON v.id = rp.visit_id JOIN sites s ON s.id = v.site_id
		WHERE s.customer_id = $1 AND v.status = 'published' AND ($2 = '' OR rc.customer_status = $2)`,
		auth.FromContext(r.Context()).CustomerID, r.URL.Query().Get("status")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) portalUpdateRecommendation(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Status string  `json:"customer_status"`
		Note   *string `json:"customer_note"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if in.Status != "open" && in.Status != "done" {
		return httpx.E(http.StatusBadRequest, "customer_status harus 'open' atau 'done'")
	}
	var out []byte
	err := s.db.QueryRow(r.Context(), `UPDATE report_recommendations rc SET customer_status = $3,
		customer_note = coalesce($4, rc.customer_note)
		FROM visit_reports rp, visits v, sites s
		WHERE rc.id = $1 AND rp.id = rc.report_id AND v.id = rp.visit_id AND s.id = v.site_id
		  AND s.customer_id = $2 AND v.status = 'published'
		RETURNING jsonb_build_object('id', rc.id, 'customer_status', rc.customer_status, 'customer_note', rc.customer_note)`,
		chi.URLParam(r, "id"), auth.FromContext(r.Context()).CustomerID, in.Status, in.Note).Scan(&out)
	if err != nil {
		return err
	}
	s.audit(r, "customer_update", "report_recommendations", chi.URLParam(r, "id"), in)
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}
