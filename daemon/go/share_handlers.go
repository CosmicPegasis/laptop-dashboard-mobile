package main

import (
	"log/slog"
	"net/http"
	"os"
	"strings"
)

type fileInfo struct {
	Name    string  `json:"name"`
	Size    int64   `json:"size"`
	ModTime float64 `json:"mod_time"`
}

func handleListFiles(w http.ResponseWriter, r *http.Request) {
	entries, err := os.ReadDir(shareDir)
	if err != nil {
		slog.Error("Failed to read share directory", "dir", shareDir, "err", err)
		errorJSON(w, http.StatusInternalServerError, "could not read share directory")
		return
	}

	files := []fileInfo{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, fileInfo{
			Name:    info.Name(),
			Size:    info.Size(),
			ModTime: float64(info.ModTime().UnixMilli()) / 1000.0,
		})
	}

	writeJSON(w, http.StatusOK, files)
	slog.Info("Listed share files", "count", len(files))
}

func handleDownload(w http.ResponseWriter, r *http.Request) {
	filename := strings.TrimPrefix(r.URL.Path, "/download/")
	if filename == "" {
		errorJSON(w, http.StatusBadRequest, "missing filename")
		return
	}

	dest, err := safePath(shareDir, filename)
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid filename")
		return
	}

	if _, err := os.Stat(dest); os.IsNotExist(err) {
		http.NotFound(w, r)
		return
	}

	slog.Info("Serving file to phone", "filename", filename, "path", dest)
	http.ServeFile(w, r, dest)
}
