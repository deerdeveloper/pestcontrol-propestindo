// Package httpx berisi helper JSON dan error untuk handler HTTP.
package httpx

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type Error struct {
	Status  int    `json:"-"`
	Message string `json:"error"`
	// Code adalah kode error tetap yang bisa dibaca aplikasi (pesan bisa berubah).
	Code string `json:"code,omitempty"`
}

func (e *Error) Error() string { return e.Message }

func E(status int, msg string) *Error { return &Error{Status: status, Message: msg} }

// EC sama seperti E, ditambah kode error tetap untuk aplikasi.
func EC(status int, code, msg string) *Error { return &Error{Status: status, Message: msg, Code: code} }

var (
	ErrNotFound     = E(http.StatusNotFound, "data tidak ditemukan")
	ErrForbidden    = E(http.StatusForbidden, "tidak punya akses")
	ErrUnauthorized = E(http.StatusUnauthorized, "silakan login")
)

func JSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

// RawJSON menulis JSON yang sudah dibentuk oleh PostgreSQL.
func RawJSON(w http.ResponseWriter, status int, b []byte) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(b)
}

func Decode(r *http.Request, v any) error {
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 10<<20))
	if err := dec.Decode(v); err != nil {
		return E(http.StatusBadRequest, "format JSON tidak valid: "+err.Error())
	}
	return nil
}

// Fail mengubah error menjadi respons HTTP yang sesuai.
func Fail(w http.ResponseWriter, err error) {
	var he *Error
	if errors.As(err, &he) {
		JSON(w, he.Status, he)
		return
	}
	if errors.Is(err, pgx.ErrNoRows) {
		JSON(w, http.StatusNotFound, ErrNotFound)
		return
	}
	var pe *pgconn.PgError
	if errors.As(err, &pe) {
		switch pe.Code {
		case "23505":
			JSON(w, http.StatusConflict, E(0, "data sudah ada: "+pe.Detail))
			return
		case "23503":
			JSON(w, http.StatusConflict, E(0, "data masih dipakai atau referensi tidak valid: "+pe.Detail))
			return
		case "23514", "23502", "22P02", "22007", "22008":
			JSON(w, http.StatusBadRequest, E(0, "data tidak valid: "+pe.Message))
			return
		}
	}
	log.Printf("internal error: %v", err)
	JSON(w, http.StatusInternalServerError, E(0, "terjadi kesalahan di server"))
}

// Handler membungkus handler yang mengembalikan error.
type Handler func(w http.ResponseWriter, r *http.Request) error

func (h Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if err := h(w, r); err != nil {
		Fail(w, err)
	}
}
