// Package buildinfo menyimpan versi binary. Nilainya diisi saat build lewat -ldflags,
// lihat target build-server di Makefile.
package buildinfo

var (
	// Version adalah tag rilis, misalnya v0.2.0. Build lokal tanpa tag bernilai "dev".
	Version = "dev"
	// Commit adalah hash git singkat.
	Commit = "unknown"
	// Date adalah waktu build (UTC, RFC 3339).
	Date = ""
	// Repo adalah repo GitHub sumber update, format owner/nama. Bisa ditimpa env UPDATE_REPO.
	Repo = ""
)
