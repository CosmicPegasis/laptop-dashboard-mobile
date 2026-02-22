package main

import (
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"sync"
)

var (
	lidInhibitEnabled bool
	lidMu             sync.RWMutex
)

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

func handleInhibitLidSleep(w http.ResponseWriter, r *http.Request) {
	var payload lidInhibitPayload
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		errorJSON(w, http.StatusBadRequest, "Invalid JSON payload")
		return
	}

	lidMu.Lock()
	lidInhibitEnabled = payload.Enabled
	lidMu.Unlock()

	if err := applyLidInhibit(payload.Enabled); err != nil {
		slog.Error("Failed to apply lid inhibit", "err", err)
		errorJSON(w, http.StatusInternalServerError, err.Error())
		return
	}

	if err := writeLidInhibitState(payload.Enabled); err != nil {
		slog.Error("Failed to persist lid inhibit state", "err", err)
	}

	slog.Info("Lid inhibit set", "enabled", payload.Enabled)
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "success",
		"enabled": strconv.FormatBool(payload.Enabled),
	})
}
