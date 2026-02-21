package main

import (
	"log/slog"
	"net/http"
)

func newMux() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/stats", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			w.Header().Set("Allow", "GET")
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}
		handleStats(w, r)
	})

	mux.HandleFunc("/sleep", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}
		handleSleep(w, r)
	})

	mux.HandleFunc("/phone-notification", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}
		handlePhoneNotification(w, r)
	})

	mux.HandleFunc("/upload", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}
		handleUpload(w, r)
	})

	mux.HandleFunc("/inhibit-lid-sleep", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.Header().Set("Allow", "POST")
			http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
			return
		}
		handleInhibitLidSleep(w, r)
	})

	// Catch-all 404
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		slog.Warn("Path not found", "path", r.URL.Path, "method", r.Method)
		http.NotFound(w, r)
	})

	return mux
}
