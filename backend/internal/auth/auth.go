// Package auth menangani password, token JWT, dan pengecekan peran.
package auth

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"

	"github.com/propestindo/pestcontrol/internal/httpx"
)

const (
	RoleSuperAdmin = "super_admin"
	RoleAdmin      = "admin"
	RoleSupervisor = "supervisor"
	RoleTechnician = "technician"
	RoleCustomer   = "customer"
)

// Staff adalah peran internal Propestindo yang boleh mengelola data.
var Staff = []string{RoleSuperAdmin, RoleAdmin, RoleSupervisor}

type User struct {
	ID         string `json:"id"`
	Role       string `json:"role"`
	CustomerID string `json:"customer_id,omitempty"`
}

func (u User) Is(roles ...string) bool {
	for _, r := range roles {
		if u.Role == r {
			return true
		}
	}
	return false
}

type claims struct {
	Role       string `json:"role"`
	CustomerID string `json:"cid,omitempty"`
	jwt.RegisteredClaims
}

type Manager struct {
	secret []byte
	ttl    time.Duration
}

func NewManager(secret string, ttl time.Duration) *Manager {
	return &Manager{secret: []byte(secret), ttl: ttl}
}

func (m *Manager) Issue(u User) (string, time.Time, error) {
	exp := time.Now().Add(m.ttl)
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims{
		Role:       u.Role,
		CustomerID: u.CustomerID,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   u.ID,
			ExpiresAt: jwt.NewNumericDate(exp),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	})
	s, err := t.SignedString(m.secret)
	return s, exp, err
}

func (m *Manager) Parse(token string) (User, error) {
	var c claims
	_, err := jwt.ParseWithClaims(token, &c, func(t *jwt.Token) (any, error) { return m.secret, nil },
		jwt.WithValidMethods([]string{"HS256"}))
	if err != nil {
		return User{}, err
	}
	return User{ID: c.Subject, Role: c.Role, CustomerID: c.CustomerID}, nil
}

func HashPassword(p string) (string, error) {
	b, err := bcrypt.GenerateFromPassword([]byte(p), bcrypt.DefaultCost)
	return string(b), err
}

func CheckPassword(hash, p string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(p)) == nil
}

type ctxKey struct{}

func FromContext(ctx context.Context) User {
	u, _ := ctx.Value(ctxKey{}).(User)
	return u
}

// Middleware membaca token dari header Authorization (atau ?token= untuk unduhan file).
func (m *Manager) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if tok == "" {
			tok = r.URL.Query().Get("token")
		}
		u, err := m.Parse(tok)
		if tok == "" || err != nil {
			httpx.JSON(w, http.StatusUnauthorized, httpx.ErrUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, u)))
	})
}

// Require hanya meloloskan pengguna dengan salah satu peran yang disebut.
func Require(roles ...string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !FromContext(r.Context()).Is(roles...) {
				httpx.JSON(w, http.StatusForbidden, httpx.ErrForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
