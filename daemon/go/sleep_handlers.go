package main

import (
	"log/slog"
	"net/http"
	"os/exec"
)

func handleSleep(w http.ResponseWriter, r *http.Request) {
	slog.Info("Sleep request received. Putting laptop to sleep...")
	cmd := exec.Command("systemctl", "suspend")
	if err := cmd.Run(); err != nil {
		slog.Error("Error putting system to sleep", "err", err)
		errorJSON(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "success",
		"message": "Suspending system",
	})
}
