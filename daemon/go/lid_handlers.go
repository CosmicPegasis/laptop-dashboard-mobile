package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strconv"
)

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
