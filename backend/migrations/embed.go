// Package migrations menyimpan file SQL migrasi di dalam binary.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
