package main

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
)

func handlePhoneNotification(w http.ResponseWriter, r *http.Request) {
	var raw []byte
	if cl := r.Header.Get("Content-Length"); cl != "" {
		length, err := strconv.Atoi(cl)
		if err == nil && length > 0 {
			raw = make([]byte, length)
			if _, err = io.ReadFull(r.Body, raw); err != nil {
				errorJSON(w, http.StatusBadRequest, "Failed to read body")
				return
			}
		}
	}
	if len(raw) == 0 {
		raw = []byte("{}")
	}

	var payload notificationPayload
	if err := json.Unmarshal(raw, &payload); err != nil {
		errorJSON(w, http.StatusBadRequest, "Invalid JSON payload")
		return
	}

	appName := truncate(strings.TrimSpace(payload.PackageName), 200)
	if appName == "" {
		appName = "unknown_app"
	}
	title := truncate(strings.TrimSpace(payload.Title), 200)
	text := truncate(strings.TrimSpace(payload.Text), 500)

	if title == "" && text == "" {
		errorJSON(w, http.StatusBadRequest, "Missing title/text")
		return
	}

	slog.Info("Phone notification",
		"app", appName,
		"title", title,
		"text", text,
		"posted_at", payload.PostedAt,
	)

	// Call notify-send if available (mirrors Python's `which("notify-send")`)
	notifySend, err := exec.LookPath("notify-send")
	if err == nil {
		summary := "Phone notification"
		if title != "" {
			summary = "Phone: " + title
		}
		body := text
		if body == "" {
			body = appName
		}
		cmd := exec.Command(notifySend, "--app-name=Phone Sync",
			truncate(summary, 200), truncate(body, 500))
		_ = cmd.Run()
	} else {
		slog.Warn("notify-send not found; skipping desktop popup")
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "success"})
}
