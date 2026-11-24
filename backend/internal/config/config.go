// Package config membaca konfigurasi dari environment variable.
package config

import (
	"fmt"
	"os"
	"time"

	"github.com/propestindo/pestcontrol/internal/buildinfo"
)

type Config struct {
	Addr        string
	DatabaseURL string
	JWTSecret   string
	JWTTTL      time.Duration
	StorageDir  string
	ChromePath  string
	CORSOrigins string
	CompanyName string

	// Update dari GitHub Releases
	UpdateRepo     string        // owner/nama, default dari buildinfo.Repo
	UpdateToken    string        // token GitHub, wajib untuk repo private
	UpdateAuto     bool          // nilai awal update otomatis; super admin bisa mengubah dari web
	UpdateInterval time.Duration // jeda cek update
	UpdateHours    string        // jam update otomatis boleh dipasang, misalnya "01-05"
	UpdateAPI      string        // alamat API GitHub, kosong = api.github.com (untuk GitHub Enterprise / uji)
}

func Load() Config {
	return Config{
		Addr:        env("APP_ADDR", ":8080"),
		DatabaseURL: env("DATABASE_URL", "postgres://pest:pest@localhost:5432/pestcontrol?sslmode=disable"),
		JWTSecret:   env("JWT_SECRET", "dev-secret-change-me"),
		JWTTTL:      durationEnv("JWT_TTL", 7*24*time.Hour),
		StorageDir:  env("STORAGE_DIR", "./storage"),
		ChromePath:  env("CHROME_PATH", "chromium"),
		CORSOrigins: env("CORS_ORIGINS", "http://localhost:5173"),
		CompanyName: env("COMPANY_NAME", "PT. Profesional Pest Control Indonesia"),

		UpdateRepo:     env("UPDATE_REPO", buildinfo.Repo),
		UpdateToken:    os.Getenv("UPDATE_GITHUB_TOKEN"),
		UpdateAuto:     env("UPDATE_AUTO", "true") == "true",
		UpdateInterval: durationEnv("UPDATE_INTERVAL", time.Hour),
		UpdateHours:    env("UPDATE_HOURS", "01-05"),
		UpdateAPI:      os.Getenv("UPDATE_GITHUB_API"),
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func durationEnv(k string, def time.Duration) time.Duration {
	if v := os.Getenv(k); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return def
}

// UpdateWindow membaca UpdateHours ("01-05") menjadi jam mulai dan selesai.
// Format tidak valid atau kosong berarti kapan saja.
func (c Config) UpdateWindow() (from, to int) {
	var a, b int
	if _, err := fmt.Sscanf(c.UpdateHours, "%d-%d", &a, &b); err != nil || a < 0 || a > 23 || b < 0 || b > 24 {
		return 0, 0
	}
	return a, b % 24
}
