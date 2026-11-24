package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/propestindo/pestcontrol/internal/httpx"
)

// resource mendeskripsikan satu tabel data master yang dikelola lewat CRUD generik.
type resource struct {
	table   string
	cols    []string // kolom yang boleh diisi dari API
	filters []string // kolom yang boleh dipakai sebagai filter ?kolom=nilai
	search  string   // kolom untuk pencarian ?q=
	order   string
	// afterCreate dijalankan dalam transaksi yang sama setelah insert.
	afterCreate func(ctx context.Context, tx pgx.Tx, id string) error
}

var masterResources = map[string]resource{
	"customers": {table: "customers", cols: []string{"name", "tax_id", "billing_address", "active"},
		search: "name", order: "name"},
	"sites": {table: "sites", cols: []string{"customer_id", "building_type_id", "name", "address", "latitude", "longitude", "active"},
		filters: []string{"customer_id"}, search: "name", order: "name", afterCreate: createDefaultAreas},
	"site-contacts": {table: "site_contacts", cols: []string{"site_id", "name", "position", "phone", "email", "is_primary"},
		filters: []string{"site_id"}, order: "name"},
	"areas": {table: "areas", cols: []string{"site_id", "name", "zone", "active"},
		filters: []string{"site_id"}, order: "name"},
	"building-types": {table: "building_types", cols: []string{"name", "default_areas"}, order: "name"},
	"pest-types": {table: "pest_types", cols: []string{"name_id", "name_en", "pest_group", "icon", "active"},
		search: "name_id", order: "name_id"},
	"treatment-methods": {table: "treatment_methods", cols: []string{"name_id", "name_en", "active"}, order: "name_id"},
	"chemicals": {table: "chemicals", cols: []string{"trade_name", "active_ingredient", "chemical_class", "registration_no", "unit", "active"},
		search: "trade_name", order: "trade_name"},
	"chemical-doses": {table: "chemical_doses", cols: []string{"chemical_id", "method_id", "dose_text"},
		filters: []string{"chemical_id", "method_id"}, order: "dose_text"},
	"equipment-types": {table: "equipment_types", cols: []string{"name", "code_prefix"}, order: "name"},
	"stations": {table: "stations", cols: []string{"site_id", "area_id", "equipment_type_id", "code", "active"},
		filters: []string{"site_id"}, order: "code"},
}

// createDefaultAreas membuat area bawaan sesuai jenis bangunan lokasi baru.
func createDefaultAreas(ctx context.Context, tx pgx.Tx, siteID string) error {
	_, err := tx.Exec(ctx, `
		INSERT INTO areas (site_id, name)
		SELECT s.id, unnest(b.default_areas) FROM sites s JOIN building_types b ON b.id = s.building_type_id
		WHERE s.id = $1 ON CONFLICT DO NOTHING`, siteID)
	return err
}

func (s *Server) masterRes(r *http.Request) (resource, error) {
	res, ok := masterResources[chi.URLParam(r, "resource")]
	if !ok {
		return res, httpx.ErrNotFound
	}
	return res, nil
}

func (s *Server) masterList(w http.ResponseWriter, r *http.Request) error {
	res, err := s.masterRes(r)
	if err != nil {
		return err
	}
	var where []string
	var args []any
	for _, f := range res.filters {
		if v := r.URL.Query().Get(f); v != "" {
			args = append(args, v)
			where = append(where, fmt.Sprintf("t.%s = $%d", f, len(args)))
		}
	}
	if q := r.URL.Query().Get("q"); q != "" && res.search != "" {
		args = append(args, "%"+q+"%")
		where = append(where, fmt.Sprintf("t.%s ILIKE $%d", res.search, len(args)))
	}
	sql := fmt.Sprintf(`SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.%s), '[]') FROM %s t`, res.order, res.table)
	if len(where) > 0 {
		sql += " WHERE " + strings.Join(where, " AND ")
	}
	var out []byte
	if err := s.db.QueryRow(r.Context(), sql, args...).Scan(&out); err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) masterGet(w http.ResponseWriter, r *http.Request) error {
	res, err := s.masterRes(r)
	if err != nil {
		return err
	}
	var out []byte
	err = s.db.QueryRow(r.Context(), fmt.Sprintf(`SELECT to_jsonb(t) FROM %s t WHERE id = $1`, res.table),
		chi.URLParam(r, "id")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

// pickCols mengembalikan kolom yang ada di body dan termasuk daftar kolom yang diizinkan.
func pickCols(body map[string]any, allowed []string) []string {
	var cols []string
	for _, c := range allowed {
		if _, ok := body[c]; ok {
			cols = append(cols, c)
		}
	}
	return cols
}

func (s *Server) masterCreate(w http.ResponseWriter, r *http.Request) error {
	res, err := s.masterRes(r)
	if err != nil {
		return err
	}
	var body map[string]any
	if err := httpx.Decode(r, &body); err != nil {
		return err
	}
	cols := pickCols(body, res.cols)
	if len(cols) == 0 {
		return httpx.E(http.StatusBadRequest, "tidak ada kolom yang diisi")
	}
	list := strings.Join(cols, ", ")
	// jsonb_populate_record mengubah JSON ke tipe kolom yang benar (uuid, numeric, array, dst).
	sql := fmt.Sprintf(`INSERT INTO %[1]s (%[2]s) SELECT %[2]s FROM jsonb_populate_record(NULL::%[1]s, $1::jsonb)
		RETURNING id`, res.table, list)

	tx, err := s.db.Begin(r.Context())
	if err != nil {
		return err
	}
	defer tx.Rollback(r.Context())
	var id string
	if err := tx.QueryRow(r.Context(), sql, body).Scan(&id); err != nil {
		return err
	}
	if res.afterCreate != nil {
		if err := res.afterCreate(r.Context(), tx, id); err != nil {
			return err
		}
	}
	var out []byte
	if err := tx.QueryRow(r.Context(), fmt.Sprintf(`SELECT to_jsonb(t) FROM %s t WHERE id=$1`, res.table), id).Scan(&out); err != nil {
		return err
	}
	if err := tx.Commit(r.Context()); err != nil {
		return err
	}
	s.audit(r, "create", res.table, id, body)
	httpx.RawJSON(w, http.StatusCreated, out)
	return nil
}

func (s *Server) masterUpdate(w http.ResponseWriter, r *http.Request) error {
	res, err := s.masterRes(r)
	if err != nil {
		return err
	}
	var body map[string]any
	if err := httpx.Decode(r, &body); err != nil {
		return err
	}
	cols := pickCols(body, res.cols)
	if len(cols) == 0 {
		return httpx.E(http.StatusBadRequest, "tidak ada kolom yang diubah")
	}
	list := strings.Join(cols, ", ")
	sql := fmt.Sprintf(`UPDATE %[1]s t SET (%[2]s) = (SELECT %[2]s FROM jsonb_populate_record(NULL::%[1]s, $1::jsonb))
		WHERE t.id = $2 RETURNING to_jsonb(t)`, res.table, list)
	if len(cols) == 1 {
		// Postgres tidak menerima SET (a) = (subquery) untuk satu kolom.
		sql = fmt.Sprintf(`UPDATE %[1]s t SET %[2]s = (SELECT %[2]s FROM jsonb_populate_record(NULL::%[1]s, $1::jsonb))
			WHERE t.id = $2 RETURNING to_jsonb(t)`, res.table, list)
	}
	var out []byte
	id := chi.URLParam(r, "id")
	if err := s.db.QueryRow(r.Context(), sql, body, id).Scan(&out); err != nil {
		return err
	}
	s.audit(r, "update", res.table, id, body)
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) masterDelete(w http.ResponseWriter, r *http.Request) error {
	res, err := s.masterRes(r)
	if err != nil {
		return err
	}
	id := chi.URLParam(r, "id")
	tag, err := s.db.Exec(r.Context(), fmt.Sprintf(`DELETE FROM %s WHERE id = $1`, res.table), id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return httpx.ErrNotFound
	}
	s.audit(r, "delete", res.table, id, nil)
	w.WriteHeader(http.StatusNoContent)
	return nil
}

// catalog mengirim semua data master umum sekaligus untuk di-cache aplikasi HP.
func (s *Server) catalog(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT jsonb_build_object(
		'pest_types',        (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY name_id), '[]') FROM pest_types t WHERE active),
		'treatment_methods', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY name_id), '[]') FROM treatment_methods t WHERE active),
		'chemicals',         (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY trade_name), '[]') FROM chemicals t WHERE active),
		'chemical_doses',    (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]') FROM chemical_doses t),
		'equipment_types',   (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY name), '[]') FROM equipment_types t),
		'building_types',    (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY name), '[]') FROM building_types t)
	)`).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}
