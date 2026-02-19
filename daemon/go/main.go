// stats_daemon — Go rewrite of the Python stats_daemon.py
// Serves on port 8081 with four endpoints:
//
//	GET  /stats               — system statistics JSON
//	POST /sleep               — suspend the laptop
//	POST /phone-notification  — forward a phone notification via notify-send
//	POST /upload              — receive a file from the phone
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
	"github.com/shirou/gopsutil/v3/mem"
	"gopkg.in/natefinch/lumberjack.v2"
)

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

const (
	logFile    = "stats_daemon.log"
	maxLogMB   = 10
	maxBackups = 5
	port       = "8081"
)

// uploadDir is the directory (relative to $HOME) where uploaded files are saved.
// shareDir is the directory (relative to $HOME) where files waiting for the phone are stored.
// Declared as vars so tests can override them with t.TempDir().
var (
	uploadDir = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_transfers")
	shareDir  = filepath.Join(os.Getenv("HOME"), "Downloads", "phone_share")
)

func setupLogging() {
	rotatingFile := &lumberjack.Logger{
		Filename:   logFile,
		MaxSize:    maxLogMB,
		MaxBackups: maxBackups,
	}
	// Write to both stdout and the rotating file via a multi-writer handler
	fileHandler := slog.NewTextHandler(rotatingFile, nil)
	stdoutHandler := slog.NewTextHandler(os.Stdout, nil)
	slog.SetDefault(slog.New(&multiHandler{handlers: []slog.Handler{fileHandler, stdoutHandler}}))
}

// multiHandler fans out log records to multiple slog.Handler instances.
type multiHandler struct {
	handlers []slog.Handler
}

func (m *multiHandler) Enabled(ctx context.Context, level slog.Level) bool {
	for _, h := range m.handlers {
		if h.Enabled(ctx, level) {
			return true
		}
	}
	return false
}

func (m *multiHandler) Handle(ctx context.Context, r slog.Record) error {
	for _, h := range m.handlers {
		_ = h.Handle(ctx, r.Clone())
	}
	return nil
}

func (m *multiHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	handlers := make([]slog.Handler, len(m.handlers))
	for i, h := range m.handlers {
		handlers[i] = h.WithAttrs(attrs)
	}
	return &multiHandler{handlers: handlers}
}

func (m *multiHandler) WithGroup(name string) slog.Handler {
	handlers := make([]slog.Handler, len(m.handlers))
	for i, h := range m.handlers {
		handlers[i] = h.WithGroup(name)
	}
	return &multiHandler{handlers: handlers}
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func errorJSON(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"status": "error", "message": msg})
}

// ---------------------------------------------------------------------------
// GET /stats
// ---------------------------------------------------------------------------

type statsResponse struct {
	CPUUsage       float64 `json:"cpu_usage"`
	RAMUsage       float64 `json:"ram_usage"`
	CPUTemp        float64 `json:"cpu_temp"`
	BatteryPercent float64 `json:"battery_percent"`
	IsPlugged      bool    `json:"is_plugged"`
	Timestamp      float64 `json:"timestamp"`
}

// getCPUTemp mirrors the Python fallback chain:
// coretemp → cpu_thermal → first available sensor → 0
func getCPUTemp() float64 {
	temps, err := host.SensorsTemperatures()
	if err != nil || len(temps) == 0 {
		return 0
	}

	byKey := make(map[string][]host.TemperatureStat)
	for _, t := range temps {
		byKey[t.SensorKey] = append(byKey[t.SensorKey], t)
	}

	for _, key := range []string{"coretemp", "cpu_thermal"} {
		if entries, ok := byKey[key]; ok && len(entries) > 0 {
			return entries[0].Temperature
		}
	}
	return temps[0].Temperature
}

// getBattery reads battery info via upower CLI (mirrors Python's psutil fallback).
// gopsutil v3 does not expose a cross-platform battery API on Linux, so we use
// the same upower approach as the Python daemon.
func getBattery() (percent float64, plugged bool) {
	devicesOut, err := exec.Command("upower", "-e").Output()
	if err != nil {
		return 0, false
	}
	for _, dev := range strings.Split(strings.TrimSpace(string(devicesOut)), "\n") {
		if !strings.Contains(dev, "battery") {
			continue
		}
		infoOut, err := exec.Command("upower", "-i", dev).Output()
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(infoOut), "\n") {
			if strings.Contains(line, "percentage:") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					val := strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(parts[1]), "%"))
					if f, err := strconv.ParseFloat(val, 64); err == nil {
						percent = f
					}
				}
			}
			if strings.Contains(line, "state:") {
				parts := strings.SplitN(line, ":", 2)
				if len(parts) == 2 {
					state := strings.ToLower(strings.TrimSpace(parts[1]))
					plugged = state == "charging" || state == "fully-charged"
				}
			}
		}
		return percent, plugged
	}
	return 0, false
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	clientIP := r.RemoteAddr

	cpuPercents, err := cpu.Percent(0, false)
	cpuUsage := 0.0
	if err == nil && len(cpuPercents) > 0 {
		cpuUsage = cpuPercents[0]
	}

	vmStat, err := mem.VirtualMemory()
	ramUsage := 0.0
	if err == nil {
		ramUsage = vmStat.UsedPercent
	}

	cpuTemp := getCPUTemp()
	batteryPercent, isPlugged := getBattery()

	resp := statsResponse{
		CPUUsage:       cpuUsage,
		RAMUsage:       ramUsage,
		CPUTemp:        cpuTemp,
		BatteryPercent: batteryPercent,
		IsPlugged:      isPlugged,
		Timestamp:      float64(time.Now().UnixMilli()) / 1000.0,
	}

	w.Header().Set("Access-Control-Allow-Origin", "*")
	writeJSON(w, http.StatusOK, resp)
	slog.Info("Served stats", "client", clientIP)
}

// ---------------------------------------------------------------------------
// POST /sleep
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// POST /phone-notification
// ---------------------------------------------------------------------------

type notificationPayload struct {
	PackageName string `json:"package_name"`
	Title       string `json:"title"`
	Text        string `json:"text"`
	PostedAt    any    `json:"posted_at"`
}

func truncate(s string, max int) string {
	runes := []rune(s)
	if len(runes) > max {
		return string(runes[:max])
	}
	return s
}

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

// ---------------------------------------------------------------------------
// POST /upload
// ---------------------------------------------------------------------------

// ensureUploadDir creates the upload directory if it does not already exist.
func ensureUploadDir() error {
	return os.MkdirAll(uploadDir, 0o755)
}

// safePath joins dir and filename, cleans the result, and verifies it is still
// inside dir. Returns an error if the path would escape the directory.
func safePath(dir, filename string) (string, error) {
	// filepath.Base strips any directory components from the client-supplied name.
	base := filepath.Base(filename)
	if base == "." || base == string(filepath.Separator) {
		return "", fmt.Errorf("invalid filename")
	}
	dest := filepath.Clean(filepath.Join(dir, base))
	// Ensure the resolved path is still inside dir.
	if !strings.HasPrefix(dest, filepath.Clean(dir)+string(filepath.Separator)) {
		return "", fmt.Errorf("path escapes upload directory")
	}
	return dest, nil
}

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

// ---------------------------------------------------------------------------
// GET /list-files and GET /download/
// ---------------------------------------------------------------------------

type fileInfo struct {
	Name    string  `json:"name"`
	Size    int64   `json:"size"`
	ModTime float64 `json:"mod_time"`
}

// ensureShareDir creates the share directory if it does not already exist.
func ensureShareDir() error {
	return os.MkdirAll(shareDir, 0o755)
}

func handleListFiles(w http.ResponseWriter, r *http.Request) {
	entries, err := os.ReadDir(shareDir)
	if err != nil {
		slog.Error("Failed to read share directory", "dir", shareDir, "err", err)
		errorJSON(w, http.StatusInternalServerError, "could not read share directory")
		return
	}

	files := []fileInfo{}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, fileInfo{
			Name:    info.Name(),
			Size:    info.Size(),
			ModTime: float64(info.ModTime().UnixMilli()) / 1000.0,
		})
	}

	writeJSON(w, http.StatusOK, files)
	slog.Info("Listed share files", "count", len(files))
}

func handleDownload(w http.ResponseWriter, r *http.Request) {
	// r.URL.Path is "/download/filename"
	filename := strings.TrimPrefix(r.URL.Path, "/download/")
	if filename == "" {
		errorJSON(w, http.StatusBadRequest, "missing filename")
		return
	}

	dest, err := safePath(shareDir, filename)
	if err != nil {
		errorJSON(w, http.StatusBadRequest, "invalid filename")
		return
	}

	if _, err := os.Stat(dest); os.IsNotExist(err) {
		http.NotFound(w, r)
		return
	}

	slog.Info("Serving file to phone", "filename", filename, "path", dest)
	http.ServeFile(w, r, dest)
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

func newMux() *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /stats", handleStats)
	mux.HandleFunc("POST /sleep", handleSleep)
	mux.HandleFunc("POST /sleep/", handleSleep)
	mux.HandleFunc("POST /phone-notification", handlePhoneNotification)
	mux.HandleFunc("POST /upload", handleUpload)
	mux.HandleFunc("GET /list-files", handleListFiles)
	mux.HandleFunc("GET /download/", handleDownload)

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		slog.Warn("Path not found", "path", r.URL.Path, "method", r.Method)
		http.NotFound(w, r)
	})

	return mux
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

func main() {
	setupLogging()

	// Ensure the directories exist before accepting requests.
	if err := ensureUploadDir(); err != nil {
		slog.Error("Failed to create upload directory", "dir", uploadDir, "err", err)
		os.Exit(1)
	}
	if err := ensureShareDir(); err != nil {
		slog.Error("Failed to create share directory", "dir", shareDir, "err", err)
		os.Exit(1)
	}

	// Warm up CPU counter (mirrors psutil.cpu_percent(interval=None) at startup)
	_, _ = cpu.Percent(0, false)

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: newMux(),
	}

	// Graceful shutdown on SIGINT / SIGTERM
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
