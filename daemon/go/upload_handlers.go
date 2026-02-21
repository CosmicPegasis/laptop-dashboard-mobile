package main

import (
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
)

func handleUpload(w http.ResponseWriter, r *http.Request) {
	// 32 MB in-memory threshold; larger files spill to OS temp automatically.
	if err := r.ParseMultipartForm(32 << 20); err != nil {
		errorJSON(w, http.StatusBadRequest, "failed to parse multipart form")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "missing 'file' field")
		return
	}
	defer file.Close()

	dest, err := safePath(uploadDir, header.Filename)
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid filename")
		return
	}

	out, err := os.Create(dest)
	if err != nil {
		slog.Error("Failed to create upload file", "dest", dest, "err", err)
		errorJSON(w, http.StatusInternalServerError, "could not create destination file")
		return
	}
	defer out.Close()

	if _, err = io.Copy(out, file); err != nil {
		slog.Error("Failed to write upload file", "dest", dest, "err", err)
		errorJSON(w, http.StatusInternalServerError, "failed to write file")
		return
	}

	slog.Info("File received from phone", "filename", header.Filename, "dest", dest)

	// Fire a desktop notification (mirrors handlePhoneNotification pattern).
	if notifySend, err := exec.LookPath("notify-send"); err == nil {
		cmd := exec.Command(notifySend, "--app-name=Phone Sync",
			"File received", truncate(header.Filename, 200))
		_ = cmd.Run()
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":   "success",
		"filename": header.Filename,
	})
}
