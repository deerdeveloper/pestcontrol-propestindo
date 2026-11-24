// Package storage menyimpan file (foto, tanda tangan, PDF) di disk lokal.
// Untuk produksi, ganti dengan implementasi S3-compatible dengan interface yang sama.
package storage

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
)

type Store interface {
	Save(dir, ext string, r io.Reader) (string, error)
	Open(path string) (io.ReadCloser, error)
	AbsPath(path string) string
}

type Local struct{ Root string }

func (l Local) Save(dir, ext string, r io.Reader) (string, error) {
	rel := filepath.Join(dir, uuid.NewString()+ext)
	abs := filepath.Join(l.Root, rel)
	if err := os.MkdirAll(filepath.Dir(abs), 0o755); err != nil {
		return "", err
	}
	f, err := os.Create(abs)
	if err != nil {
		return "", err
	}
	defer f.Close()
	if _, err := io.Copy(f, r); err != nil {
		return "", err
	}
	return filepath.ToSlash(rel), nil
}

func (l Local) Open(path string) (io.ReadCloser, error) {
	return os.Open(l.AbsPath(path))
}

func (l Local) AbsPath(path string) string {
	clean := filepath.Clean("/" + path)
	if strings.Contains(clean, "..") {
		panic(fmt.Sprintf("path tidak valid: %s", path))
	}
	return filepath.Join(l.Root, clean)
}
