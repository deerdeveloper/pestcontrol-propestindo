// Package pdf membuat PDF laporan kunjungan dua bahasa dari template HTML,
// lalu mencetaknya ke PDF dengan Chromium headless.
package pdf

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/base64"
	"fmt"
	"html/template"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

//go:embed assets/logo.png
var logoPNG []byte

//go:embed report.html
var reportHTML string

type Document struct {
	Visit struct {
		ID            string `json:"id"`
		VisitType     string `json:"visit_type"`
		ScheduledDate string `json:"scheduled_date"`
		Status        string `json:"status"`
	} `json:"visit"`
	Customer struct {
		Name string `json:"name"`
	} `json:"customer"`
	Site struct {
		Name    string `json:"name"`
		Address string `json:"address"`
	} `json:"site"`
	Technician *struct {
		Name string  `json:"name"`
		Code *string `json:"code"`
	} `json:"technician"`
	PIC *struct {
		Name string `json:"name"`
	} `json:"pic"`
	Report *Report `json:"report"`
}

type Ref struct {
	ID      string  `json:"id"`
	Caption *string `json:"caption"`
}

type Report struct {
	ID         string     `json:"id"`
	ReportNo   *string    `json:"report_no"`
	StartedAt  *time.Time `json:"started_at"`
	FinishedAt *time.Time `json:"finished_at"`
	PICName    *string    `json:"pic_name"`
	Notes      *string    `json:"general_notes"`
	Findings   []struct {
		PestNameID  string  `json:"pest_name_id"`
		PestNameEN  string  `json:"pest_name_en"`
		AreaName    *string `json:"area_name"`
		Level       string  `json:"level"`
		IsActive    bool    `json:"is_active"`
		Remarks     *string `json:"remarks"`
		Attachments []Ref   `json:"attachments"`
	} `json:"findings"`
	Treatments []struct {
		MethodNameID     string  `json:"method_name_id"`
		MethodNameEN     string  `json:"method_name_en"`
		AreaName         *string `json:"area_name"`
		ChemicalName     *string `json:"chemical_name"`
		ActiveIngredient *string `json:"active_ingredient"`
		DoseText         *string `json:"dose_text"`
		QuantityUsed     *string `json:"quantity_used"`
		Equipment        *string `json:"equipment"`
	} `json:"treatments"`
	Recommendations []struct {
		Category       string `json:"category"`
		RiskFinding    string `json:"risk_finding"`
		Recommendation string `json:"recommendation"`
	} `json:"recommendations"`
	StationChecks []struct {
		StationCode     string  `json:"station_code"`
		EquipmentType   string  `json:"equipment_type"`
		AreaName        *string `json:"area_name"`
		Status          string  `json:"status"`
		BaitConsumption string  `json:"bait_consumption"`
		Finding         *string `json:"finding"`
	} `json:"station_checks"`
	Attachments []Ref `json:"attachments"`
	Signatures  []struct {
		ID         string    `json:"id"`
		SignerRole string    `json:"signer_role"`
		SignerName string    `json:"signer_name"`
		SignedAt   time.Time `json:"signed_at"`
	} `json:"signatures"`
}

type Renderer struct {
	ChromePath  string
	CompanyName string
	tmpl        *template.Template
}

var jakarta = func() *time.Location {
	if l, err := time.LoadLocation("Asia/Jakarta"); err == nil {
		return l
	}
	return time.FixedZone("WIB", 7*3600)
}()

var bilingual = map[string][2]string{
	"routine_monthly": {"Rutin Bulanan", "Monthly Routine"}, "routine_biweekly": {"Rutin Dua Mingguan", "Bi-weekly Routine"},
	"emergency": {"Kunjungan Darurat", "Emergency Visit"}, "initial_inspection": {"Inspeksi Awal", "Initial Inspection"},
	"none": {"Nihil", "None"}, "low": {"Rendah", "Low"}, "medium": {"Sedang", "Medium"}, "high": {"Tinggi", "High"},
	"exclusion": {"Penutupan Akses", "Exclusion"}, "sanitation": {"Sanitasi", "Sanitation"},
	"storage": {"Penyimpanan", "Storage"}, "habitual": {"Kebiasaan", "Habitual"},
	"ok": {"OK", "OK"}, "check": {"Periksa", "Check"}, "replace": {"Ganti", "Replace"},
	"partial": {"Dimakan sebagian", "Partially eaten"}, "total": {"Habis total", "Fully consumed"},
}

func New(chromePath, company string) *Renderer {
	months := []string{"", "Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"}
	funcs := template.FuncMap{
		"id": func(k string) string { return bilingual[k][0] },
		"en": func(k string) string {
			if v, ok := bilingual[k]; ok {
				return v[1]
			}
			return k
		},
		"str": func(p *string) string {
			if p == nil {
				return "-"
			}
			return *p
		},
		"dateID": func(s string) string {
			t, err := time.Parse("2006-01-02", s)
			if err != nil {
				return s
			}
			return fmt.Sprintf("%d %s %d", t.Day(), months[t.Month()], t.Year())
		},
		"dateEN": func(s string) string {
			t, err := time.Parse("2006-01-02", s)
			if err != nil {
				return s
			}
			return t.Format("2 January 2006")
		},
		"clock": func(t *time.Time) string {
			if t == nil {
				return "--:--"
			}
			return t.In(jakarta).Format("15:04")
		},
		"stamp": func(t time.Time) string { return t.In(jakarta).Format("02/01/2006 15:04") + " WIB" },
		"inc":   func(i int) int { return i + 1 },
	}
	return &Renderer{ChromePath: chromePath, CompanyName: company,
		tmpl: template.Must(template.New("report").Funcs(funcs).Parse(reportHTML))}
}

// HTML menghasilkan HTML laporan. files memetakan id foto/tanda tangan ke path file di disk.
func (r *Renderer) HTML(doc Document, files map[string]string) ([]byte, error) {
	img := func(id string) template.URL {
		p, ok := files[id]
		if !ok {
			return ""
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return ""
		}
		return template.URL("data:" + http.DetectContentType(b) + ";base64," + base64.StdEncoding.EncodeToString(b))
	}
	var buf bytes.Buffer
	err := r.tmpl.Execute(&buf, map[string]any{
		"D":       doc,
		"R":       doc.Report,
		"Logo":    template.URL("data:image/png;base64," + base64.StdEncoding.EncodeToString(logoPNG)),
		"Img":     img,
		"Company": r.CompanyName,
		"Now":     time.Now(),
	})
	return buf.Bytes(), err
}

// Render membuat PDF dengan menjalankan Chromium headless.
func (r *Renderer) Render(ctx context.Context, doc Document, files map[string]string) ([]byte, error) {
	html, err := r.HTML(doc, files)
	if err != nil {
		return nil, err
	}
	dir, err := os.MkdirTemp("", "report-*")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)
	in, out := filepath.Join(dir, "report.html"), filepath.Join(dir, "report.pdf")
	if err := os.WriteFile(in, html, 0o600); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, r.ChromePath, "--headless", "--no-sandbox", "--disable-gpu",
		"--no-pdf-header-footer", "--user-data-dir="+filepath.Join(dir, "profile"),
		"--print-to-pdf="+out, "file://"+in)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("chromium gagal: %v: %s", err, strings.TrimSpace(stderr.String()))
	}
	return os.ReadFile(out)
}
