package api

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/propestindo/pestcontrol/internal/auth"
	"github.com/propestindo/pestcontrol/internal/httpx"
)

const userCols = `id, email, name, phone, role, technician_code, customer_id, active, created_at`

func (s *Server) login(w http.ResponseWriter, r *http.Request) error {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	var u auth.User
	var hash string
	var cid *string
	var active bool
	err := s.db.QueryRow(r.Context(), `SELECT id, role, customer_id, password_hash, active FROM users WHERE lower(email) = lower($1)`,
		strings.TrimSpace(in.Email)).Scan(&u.ID, &u.Role, &cid, &hash, &active)
	if err != nil || !active || !auth.CheckPassword(hash, in.Password) {
		return httpx.E(http.StatusUnauthorized, "email atau password salah")
	}
	if cid != nil {
		u.CustomerID = *cid
	}
	token, exp, err := s.auth.Issue(u)
	if err != nil {
		return err
	}
	var profile []byte
	if err := s.db.QueryRow(r.Context(), `SELECT to_jsonb(t) FROM (SELECT `+userCols+` FROM users WHERE id=$1) t`, u.ID).Scan(&profile); err != nil {
		return err
	}
	httpx.JSON(w, http.StatusOK, map[string]any{"token": token, "expires_at": exp, "user": rawJSON(profile)})
	return nil
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) error {
	u := auth.FromContext(r.Context())
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT to_jsonb(t) || jsonb_build_object('customer_name', c.name)
		FROM (SELECT `+userCols+` FROM users WHERE id=$1) t LEFT JOIN customers c ON c.id = t.customer_id`, u.ID).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) listUsers(w http.ResponseWriter, r *http.Request) error {
	var out []byte
	err := s.db.QueryRow(r.Context(), `SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.name), '[]') FROM (
		SELECT `+userCols+` FROM users WHERE ($1 = '' OR role = $1) AND ($2 = '' OR customer_id::text = $2)) t`,
		r.URL.Query().Get("role"), r.URL.Query().Get("customer_id")).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}

type userInput struct {
	Email          *string `json:"email"`
	Password       *string `json:"password"`
	Name           *string `json:"name"`
	Phone          *string `json:"phone"`
	Role           *string `json:"role"`
	TechnicianCode *string `json:"technician_code"`
	CustomerID     *string `json:"customer_id"`
	Active         *bool   `json:"active"`
}

func (s *Server) createUser(w http.ResponseWriter, r *http.Request) error {
	var in userInput
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if in.Email == nil || in.Name == nil || in.Role == nil || in.Password == nil || len(*in.Password) < 8 {
		return httpx.E(http.StatusBadRequest, "email, nama, peran, dan password (minimal 8 karakter) wajib diisi")
	}
	if *in.Role == auth.RoleSuperAdmin && !auth.FromContext(r.Context()).Is(auth.RoleSuperAdmin) {
		return httpx.ErrForbidden
	}
	hash, err := auth.HashPassword(*in.Password)
	if err != nil {
		return err
	}
	var out []byte
	err = s.db.QueryRow(r.Context(), `INSERT INTO users (email, password_hash, name, phone, role, technician_code, customer_id)
		VALUES (lower($1), $2, $3, $4, $5, $6, $7) RETURNING to_jsonb((SELECT t FROM (SELECT `+userCols+`) t))`,
		*in.Email, hash, *in.Name, in.Phone, *in.Role, in.TechnicianCode, in.CustomerID).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusCreated, out)
	return nil
}

func (s *Server) updateUser(w http.ResponseWriter, r *http.Request) error {
	var in userInput
	if err := httpx.Decode(r, &in); err != nil {
		return err
	}
	if in.Role != nil && *in.Role == auth.RoleSuperAdmin && !auth.FromContext(r.Context()).Is(auth.RoleSuperAdmin) {
		return httpx.ErrForbidden
	}
	var hash *string
	if in.Password != nil {
		if len(*in.Password) < 8 {
			return httpx.E(http.StatusBadRequest, "password minimal 8 karakter")
		}
		h, err := auth.HashPassword(*in.Password)
		if err != nil {
			return err
		}
		hash = &h
	}
	var out []byte
	err := s.db.QueryRow(r.Context(), `UPDATE users SET
		email = coalesce(lower($2), email), password_hash = coalesce($3, password_hash), name = coalesce($4, name),
		phone = coalesce($5, phone), role = coalesce($6, role), technician_code = coalesce($7, technician_code),
		customer_id = coalesce($8, customer_id), active = coalesce($9, active), updated_at = now()
		WHERE id = $1 RETURNING to_jsonb((SELECT t FROM (SELECT `+userCols+`) t))`,
		chi.URLParam(r, "id"), in.Email, hash, in.Name, in.Phone, in.Role, in.TechnicianCode, in.CustomerID, in.Active).Scan(&out)
	if err != nil {
		return err
	}
	httpx.RawJSON(w, http.StatusOK, out)
	return nil
}
