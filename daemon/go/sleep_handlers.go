package main

import (
	"log/slog"
	"net/http"
	"os/exec"
)

// suspendCmd is the function called to suspend the system.
// It is a variable so tests can replace it with a stub without
// actually putting the machine to sleep.
var suspendCmd = func() error {
	return exec.Command("systemctl", "suspend").Run()
}

func handleSleep(w http.ResponseWriter, r *http.Request) {
	slog.Info("Sleep request received. Putting laptop to sleep...")
	if err := suspendCmd(); err != nil {
		slog.Error("Error putting system to sleep", "err", err)
		errorJSON(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "success",
		"message": "Suspending system",
	})
}
