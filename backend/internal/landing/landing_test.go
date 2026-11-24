package landing

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandler(t *testing.T) {
	h := Handler()
	cases := []struct {
		path, wantType, wantBody, wantLoc string
		code                              int
	}{
		{"/", "text/html", "Propestindo", "", 200},
		{"/site/style.css", "text/css", "--green-900", "", 200},
		{"/site/logo.svg", "image/svg+xml", "<svg", "", 200},
		{"/favicon.svg", "image/svg+xml", "", "", 200},
		{"/sw.js", "application/javascript", "unregister", "", 200},
		{"/login", "", "", "/app/login", 302},
		{"/visits/123?x=1", "", "", "/app/visits/123?x=1", 302},
		{"/portal/recommendations", "", "", "/app/portal/recommendations", 302},
		{"/api/tidak-ada", "application/json", "endpoint", "", 404},
		{"/halaman-acak", "text/html", "404", "", 404},
		{"/site/404.html", "text/html", "404", "", 404},
	}
	for _, c := range cases {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, c.path, nil))
		if rec.Code != c.code {
			t.Errorf("%s: status %d, mau %d", c.path, rec.Code, c.code)
		}
		if c.wantType != "" && !strings.Contains(rec.Header().Get("Content-Type"), c.wantType) {
			t.Errorf("%s: content-type %q", c.path, rec.Header().Get("Content-Type"))
		}
		if c.wantBody != "" && !strings.Contains(rec.Body.String(), c.wantBody) {
			t.Errorf("%s: body tidak memuat %q", c.path, c.wantBody)
		}
		if c.wantLoc != "" && rec.Header().Get("Location") != c.wantLoc {
			t.Errorf("%s: location %q, mau %q", c.path, rec.Header().Get("Location"), c.wantLoc)
		}
	}
}
