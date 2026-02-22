package main

import (
	"log/slog"
	"net/http"
)

// methodNotAllowed replies with 405 and the correct Allow header.
func methodNotAllowed(allowed string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Allow", allowed)
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
	}
}

// newMux wires all routes using Go 1.22 method+path pattern syntax.
// CORS is applied at the server level via corsMiddleware in main().
func newMux() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /stats", handleStats)
	// Go 1.22 routers return 404 (not 405) when a path is registered for only
	// one method. Register explicit 405 handlers for the wrong-method cases that
	// the test suite asserts on.
	mux.HandleFunc("POST /stats", methodNotAllowed("GET"))

	mux.HandleFunc("POST /sleep", handleSleep)
	mux.HandleFunc("POST /phone-notification", handlePhoneNotification)

	mux.HandleFunc("POST /upload", handleUpload)
	mux.HandleFunc("GET /upload", methodNotAllowed("POST"))

	mux.HandleFunc("POST /inhibit-lid-sleep", handleInhibitLidSleep)
	mux.HandleFunc("GET /list-files", handleListFiles)
	mux.HandleFunc("GET /download/", handleDownload)

	// Catch-all 404
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		slog.Warn("Path not found", "path", r.URL.Path, "method", r.Method)
		http.NotFound(w, r)
	})

	return mux
}
