package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

var (
	uploadDir = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_transfers")
	shareDir  = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_share")
)

var lidInhibitFile = "lid_inhibit.state"

var (
	lidInhibitEnabled bool
	lidMu             sync.RWMutex
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

func readLidInhibitState() error {
	data, err := os.ReadFile(lidInhibitFile)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	enabled := string(data) == "enabled"

	lidMu.Lock()
	lidInhibitEnabled = enabled
	lidMu.Unlock()

	return applyLidInhibit(enabled)
}

func writeLidInhibitState(enabled bool) error {
	content := "disabled"
	if enabled {
		content = "enabled"
	}
	return os.WriteFile(lidInhibitFile, []byte(content), 0o644)
}

func applyLidInhibit(enabled bool) error {
	mode := "suspend"
	if enabled {
		mode = "external"
	}
	cmd := exec.Command("loginctl", "set-handle-lid-switch", mode)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to set lid switch handling: %w", err)
	}
	slog.Info("Lid switch handling set", "mode", mode)
	return nil
}
