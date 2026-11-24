package updater

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// Release adalah rilis GitHub yang relevan untuk update.
type Release struct {
	Tag         string    `json:"tag"`
	Name        string    `json:"name"`
	Notes       string    `json:"notes"`
	URL         string    `json:"url"`
	PublishedAt time.Time `json:"published_at"`
	Assets      []Asset   `json:"assets"`
}

// Asset adalah satu file di rilis GitHub.
type Asset struct {
	Name        string `json:"name"`
	Size        int64  `json:"size"`
	APIURL      string `json:"-"`
	DownloadURL string `json:"download_url"`
}

// Asset mencari file rilis berdasarkan nama.
func (r *Release) Asset(name string) (Asset, bool) {
	for _, a := range r.Assets {
		if a.Name == name {
			return a, true
		}
	}
	return Asset{}, false
}

// GitHub adalah klien kecil untuk API rilis GitHub.
type GitHub struct {
	Repo  string // owner/nama
	Token string // opsional, wajib jika repo private
	HTTP  *http.Client
	API   string // default https://api.github.com, bisa diganti untuk test
}

func (g *GitHub) client() *http.Client {
	if g.HTTP != nil {
		return g.HTTP
	}
	return &http.Client{Timeout: 10 * time.Minute}
}

func (g *GitHub) request(ctx context.Context, url, accept string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", accept)
	req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
	req.Header.Set("User-Agent", "pestcontrol-updater")
	if g.Token != "" {
		// Header Authorization otomatis dibuang Go saat redirect ke domain lain (storage GitHub).
		req.Header.Set("Authorization", "Bearer "+g.Token)
	}
	res, err := g.client().Do(req)
	if err != nil {
		return nil, err
	}
	if res.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(io.LimitReader(res.Body, 512))
		res.Body.Close()
		msg := strings.TrimSpace(string(body))
		if res.StatusCode == http.StatusNotFound {
			msg = "repo atau rilis tidak ditemukan (repo private butuh UPDATE_GITHUB_TOKEN)"
		}
		return nil, fmt.Errorf("github %s: %s", res.Status, msg)
	}
	return res, nil
}

// Latest mengambil rilis terbaru yang bukan draft dan bukan pre-release.
func (g *GitHub) Latest(ctx context.Context) (*Release, error) {
	api := g.API
	if api == "" {
		api = "https://api.github.com"
	}
	res, err := g.request(ctx, fmt.Sprintf("%s/repos/%s/releases/latest", api, g.Repo), "application/vnd.github+json")
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	var raw struct {
		TagName     string    `json:"tag_name"`
		Name        string    `json:"name"`
		Body        string    `json:"body"`
		HTMLURL     string    `json:"html_url"`
		PublishedAt time.Time `json:"published_at"`
		Assets      []struct {
			Name               string `json:"name"`
			Size               int64  `json:"size"`
			URL                string `json:"url"`
			BrowserDownloadURL string `json:"browser_download_url"`
		} `json:"assets"`
	}
	if err := json.NewDecoder(res.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("membaca rilis: %w", err)
	}
	rel := &Release{Tag: raw.TagName, Name: raw.Name, Notes: raw.Body, URL: raw.HTMLURL, PublishedAt: raw.PublishedAt}
	for _, a := range raw.Assets {
		rel.Assets = append(rel.Assets, Asset{Name: a.Name, Size: a.Size, APIURL: a.URL, DownloadURL: a.BrowserDownloadURL})
	}
	return rel, nil
}

// Open membuka stream isi file rilis. Lewat API agar repo private juga bisa.
func (g *GitHub) Open(ctx context.Context, a Asset) (io.ReadCloser, int64, error) {
	res, err := g.request(ctx, a.APIURL, "application/octet-stream")
	if err != nil {
		return nil, 0, err
	}
	return res.Body, res.ContentLength, nil
}

// Checksums membaca SHA256SUMS (format keluaran sha256sum: "hash  nama") dari rilis.
func (g *GitHub) Checksums(ctx context.Context, rel *Release) (map[string]string, error) {
	a, ok := rel.Asset("SHA256SUMS")
	if !ok {
		return nil, fmt.Errorf("rilis %s tidak punya SHA256SUMS", rel.Tag)
	}
	body, _, err := g.Open(ctx, a)
	if err != nil {
		return nil, err
	}
	defer body.Close()
	sums := map[string]string{}
	sc := bufio.NewScanner(io.LimitReader(body, 1<<20))
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) == 2 {
			sums[strings.TrimPrefix(f[1], "*")] = strings.ToLower(f[0])
		}
	}
	return sums, sc.Err()
}
