// stats_daemon — Go rewrite of the Python stats_daemon.py
// Serves on port 8081. See router.go for the full endpoint list.
package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
)

func main() {
	setupLogging()

	// Ensure upload/share directories exist before accepting requests.
	if err := ensureDir(uploadDir); err != nil {
		slog.Error("Failed to create upload directory", "dir", uploadDir, "err", err)
		os.Exit(1)
	}
	if err := ensureDir(shareDir); err != nil {
		slog.Error("Failed to create share directory", "dir", shareDir, "err", err)
		os.Exit(1)
	}

	// Restore lid-inhibit state persisted from the previous run.
	if err := readLidInhibitState(); err != nil {
		slog.Warn("Failed to restore lid inhibit state", "err", err)
	}

	// Warm up the CPU counter so the first /stats response is meaningful.
	_, _ = cpu.Percent(0, false)

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: corsMiddleware(newMux()),
	}

	// Graceful shutdown on SIGINT / SIGTERM.
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		slog.Info("Starting stats daemon", "port", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Server error", "err", err)
			os.Exit(1)
		}
	}()

	<-quit
	slog.Info("Stopping stats daemon...")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("Shutdown error", "err", err)
	}
	slog.Info("Server closed.")
}
