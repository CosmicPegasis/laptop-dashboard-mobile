package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func errorJSON(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"status": "error", "message": msg})
}

func truncate(s string, max int) string {
	runes := []rune(s)
	if len(runes) > max {
		return string(runes[:max])
	}
	return s
}

func ensureDir(path string) error {
	return os.MkdirAll(path, 0o755)
}

func safePath(dir, filename string) (string, error) {
	base := filepath.Base(filename)
	if base == "." || base == string(filepath.Separator) {
		return "", fmt.Errorf("invalid filename")
	}
	dest := filepath.Clean(filepath.Join(dir, base))
	if !strings.HasPrefix(dest, filepath.Clean(dir)+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes upload directory")
	}
	return dest, nil
}
