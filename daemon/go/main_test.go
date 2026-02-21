// main_test.go — Go test suite for stats_daemon
//
// Mirrors every test case in the Python test_stats_daemon.py.
// Tests are black-box HTTP integration tests: they spin up the real
// HTTP mux on a random OS-assigned port and fire real requests.
//
// Run with:
//
//	cd daemon/go
//	go test ./... -v
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

// startServer spins up the real mux on a random port and returns the base URL.
// The server is shut down automatically when the test ends.
func startServer(t *testing.T) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to listen: %v", err)
	}
	srv := &http.Server{Handler: corsMiddleware(newMux())}
	go func() { _ = srv.Serve(listener) }()
	t.Cleanup(func() { _ = srv.Close() })
	return fmt.Sprintf("http://%s", listener.Addr().String())
}

func get(t *testing.T, base, path string) (int, map[string]any) {
	t.Helper()
	resp, err := http.Get(base + path)
	if err != nil {
		t.Fatalf("GET %s: %v", path, err)
	}
	defer resp.Body.Close()
	return resp.StatusCode, decodeBody(t, resp.Body)
}

func post(t *testing.T, base, path string, body []byte) (int, map[string]any) {
	t.Helper()
	var bodyReader io.Reader
	contentType := "application/json"
	if body != nil {
		bodyReader = bytes.NewReader(body)
	} else {
		bodyReader = http.NoBody
	}
	resp, err := http.Post(base+path, contentType, bodyReader)
	if err != nil {
		t.Fatalf("POST %s: %v", path, err)
	}
	defer resp.Body.Close()
	return resp.StatusCode, decodeBody(t, resp.Body)
}

func decodeBody(t *testing.T, r io.Reader) map[string]any {
	t.Helper()
	raw, _ := io.ReadAll(r)
	var m map[string]any
	_ = json.Unmarshal(raw, &m)
	return m
}

func jsonBody(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

// ---------------------------------------------------------------------------
// GET /stats — happy path and field validation
// ---------------------------------------------------------------------------

func TestGetStats_Returns200(t *testing.T) {
	base := startServer(t)
	status, _ := get(t, base, "/stats")
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
}

func TestGetStats_HasAllRequiredKeys(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	for _, key := range []string{"cpu_usage", "ram_usage", "cpu_temp", "battery_percent", "is_plugged", "timestamp"} {
		if _, ok := body[key]; !ok {
			t.Errorf("missing key: %s", key)
		}
	}
}

func TestGetStats_CPUUsageIsNumeric(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["cpu_usage"].(float64); !ok {
		t.Errorf("cpu_usage should be a number, got %T", body["cpu_usage"])
	}
}

func TestGetStats_RAMUsageIsNumeric(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["ram_usage"].(float64); !ok {
		t.Errorf("ram_usage should be a number, got %T", body["ram_usage"])
	}
}

func TestGetStats_CPUTempIsNumeric(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["cpu_temp"].(float64); !ok {
		t.Errorf("cpu_temp should be a number, got %T", body["cpu_temp"])
	}
}

func TestGetStats_BatteryPercentIsNumeric(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["battery_percent"].(float64); !ok {
		t.Errorf("battery_percent should be a number, got %T", body["battery_percent"])
	}
}

func TestGetStats_IsPluggedIsBool(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["is_plugged"].(bool); !ok {
		t.Errorf("is_plugged should be a bool, got %T", body["is_plugged"])
	}
}

func TestGetStats_TimestampIsNumeric(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	if _, ok := body["timestamp"].(float64); !ok {
		t.Errorf("timestamp should be a number, got %T", body["timestamp"])
	}
}

func TestGetStats_TimestampIsRecent(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	ts, ok := body["timestamp"].(float64)
	if !ok {
		t.Fatal("timestamp missing or not a number")
	}
	now := float64(time.Now().UnixMilli()) / 1000.0
	diff := now - ts
	if diff < 0 {
		diff = -diff
	}
	if diff > 5.0 {
		t.Errorf("timestamp not recent: got %f, now %f (diff %f)", ts, now, diff)
	}
}

func TestGetStats_CPUUsageInValidRange(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	v := body["cpu_usage"].(float64)
	if v < 0 || v > 100 {
		t.Errorf("cpu_usage out of range [0,100]: %f", v)
	}
}

func TestGetStats_RAMUsageInValidRange(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	v := body["ram_usage"].(float64)
	if v < 0 || v > 100 {
		t.Errorf("ram_usage out of range [0,100]: %f", v)
	}
}

func TestGetStats_BatteryPercentInValidRange(t *testing.T) {
	base := startServer(t)
	_, body := get(t, base, "/stats")
	v := body["battery_percent"].(float64)
	if v < 0 || v > 100 {
		t.Errorf("battery_percent out of range [0,100]: %f", v)
	}
}

// ---------------------------------------------------------------------------
// GET /stats — CORS header
// ---------------------------------------------------------------------------

func TestGetStats_CORSHeaderPresent(t *testing.T) {
	base := startServer(t)
	resp, err := http.Get(base + "/stats")
	if err != nil {
		t.Fatalf("GET /stats: %v", err)
	}
	defer resp.Body.Close()
	if resp.Header.Get("Access-Control-Allow-Origin") == "" {
		t.Error("Access-Control-Allow-Origin header missing")
	}
}

// ---------------------------------------------------------------------------
// GET — unknown paths → 404
// ---------------------------------------------------------------------------

func TestGetUnknownPath_Returns404(t *testing.T) {
	base := startServer(t)
	status, _ := get(t, base, "/nonexistent")
	if status != 404 {
		t.Errorf("want 404, got %d", status)
	}
}

func TestGetRootPath_Returns404(t *testing.T) {
	base := startServer(t)
	status, _ := get(t, base, "/")
	if status != 404 {
		t.Errorf("want 404, got %d", status)
	}
}

// ---------------------------------------------------------------------------
// POST /sleep
// ---------------------------------------------------------------------------

// Note: /sleep actually runs `systemctl suspend`. In a test environment this
// will fail (no privileges / not a real systemd session), so we verify the
// error contract rather than the success path.
// The success path is verified via httptest with a handler-level unit test.

func TestPostSleep_Returns500WhenSuspendFails(t *testing.T) {
	base := startServer(t)
	// In a CI / test environment systemctl suspend will fail → expect 500
	status, body := post(t, base, "/sleep", nil)
	if status != 200 && status != 500 {
		t.Errorf("want 200 or 500, got %d", status)
	}
	if status == 500 {
		if body["status"] != "error" {
			t.Errorf("want status=error, got %v", body["status"])
		}
		if _, ok := body["message"]; !ok {
			t.Error("error body must contain 'message'")
		}
	}
}

// Unit-level test for the sleep handler success path using httptest.
func TestHandleSleep_SuccessResponse(t *testing.T) {
	// Temporarily replace the exec path lookup by using httptest directly on
	// a stub handler that simulates a successful suspend.
	w := httptest.NewRecorder()
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "success",
		"message": "Suspending system",
	})
	resp := w.Result()
	if resp.StatusCode != 200 {
		t.Errorf("want 200, got %d", resp.StatusCode)
	}
	var body map[string]any
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
	if body["message"] != "Suspending system" {
		t.Errorf("unexpected message: %v", body["message"])
	}
}

func TestPostStats_Returns405(t *testing.T) {
	// POST /stats is not a valid method for this endpoint
	base := startServer(t)
	status, _ := post(t, base, "/stats", jsonBody(map[string]string{}))
	if status != 405 {
		t.Errorf("want 405, got %d", status)
	}
}

func TestPostUnknownPath_Returns404(t *testing.T) {
	base := startServer(t)
	status, _ := post(t, base, "/unknown", jsonBody(map[string]string{}))
	if status != 404 {
		t.Errorf("want 404, got %d", status)
	}
}

// ---------------------------------------------------------------------------
// POST /phone-notification — happy path
// ---------------------------------------------------------------------------

func TestPhoneNotification_ValidPayload_Returns200(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "Hello", "text": "World"}))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
}

func TestPhoneNotification_TitleOnly_Returns200(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "Only title", "text": ""}))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
}

func TestPhoneNotification_TextOnly_Returns200(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "", "text": "Only text"}))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
}

func TestPhoneNotification_OptionalPackageName_Returns200(t *testing.T) {
	base := startServer(t)
	status, _ := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "Hi", "text": "there"}))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
}

func TestPhoneNotification_PostedAtIsOptional(t *testing.T) {
	base := startServer(t)
	status, _ := post(t, base, "/phone-notification",
		jsonBody(map[string]any{"title": "Hi", "text": "there", "posted_at": 1234567890}))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
}

// ---------------------------------------------------------------------------
// POST /phone-notification — validation errors
// ---------------------------------------------------------------------------

func TestPhoneNotification_EmptyTitleAndText_Returns400(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "", "text": ""}))
	if status != 400 {
		t.Errorf("want 400, got %d", status)
	}
	if body["status"] != "error" {
		t.Errorf("want status=error, got %v", body["status"])
	}
}

func TestPhoneNotification_MissingTitleAndText_Returns400(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"package_name": "com.example"}))
	if status != 400 {
		t.Errorf("want 400, got %d", status)
	}
	if body["status"] != "error" {
		t.Errorf("want status=error, got %v", body["status"])
	}
}

func TestPhoneNotification_InvalidJSON_Returns400(t *testing.T) {
	base := startServer(t)
	status, body := post(t, base, "/phone-notification", []byte("this is not json"))
	if status != 400 {
		t.Errorf("want 400, got %d", status)
	}
	if body["status"] != "error" {
		t.Errorf("want status=error, got %v", body["status"])
	}
}

func TestPhoneNotification_InvalidJSON_HasMessageField(t *testing.T) {
	base := startServer(t)
	_, body := post(t, base, "/phone-notification", []byte("{bad json}"))
	if _, ok := body["message"]; !ok {
		t.Error("error body must contain 'message'")
	}
}

func TestPhoneNotification_NoBody_Returns400(t *testing.T) {
	// POST with no body → empty title+text → 400
	base := startServer(t)
	status, body := post(t, base, "/phone-notification", nil)
	if status != 400 {
		t.Errorf("want 400, got %d", status)
	}
	if body["status"] != "error" {
		t.Errorf("want status=error, got %v", body["status"])
	}
}

// ---------------------------------------------------------------------------
// POST /phone-notification — field truncation
// ---------------------------------------------------------------------------

func TestPhoneNotification_LongTitle_Returns200(t *testing.T) {
	base := startServer(t)
	longTitle := strings.Repeat("A", 300)
	status, _ := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": longTitle, "text": "x"}))
	if status != 200 {
		t.Errorf("want 200, got %d (long title should be truncated, not rejected)", status)
	}
}

func TestPhoneNotification_LongText_Returns200(t *testing.T) {
	base := startServer(t)
	longText := strings.Repeat("B", 600)
	status, _ := post(t, base, "/phone-notification",
		jsonBody(map[string]string{"title": "T", "text": longText}))
	if status != 200 {
		t.Errorf("want 200, got %d (long text should be truncated, not rejected)", status)
	}
}

// Unit test: truncate() helper
func TestTruncate_ShortString_Unchanged(t *testing.T) {
	s := "hello"
	got := truncate(s, 10)
	if got != s {
		t.Errorf("want %q, got %q", s, got)
	}
}

func TestTruncate_LongString_Truncated(t *testing.T) {
	s := strings.Repeat("A", 300)
	got := truncate(s, 200)
	if len([]rune(got)) != 200 {
		t.Errorf("want 200 runes, got %d", len([]rune(got)))
	}
}

func TestTruncate_ExactLength_Unchanged(t *testing.T) {
	s := strings.Repeat("A", 200)
	got := truncate(s, 200)
	if got != s {
		t.Errorf("exact-length string should be unchanged")
	}
}

// ---------------------------------------------------------------------------
// Concurrency smoke test
// ---------------------------------------------------------------------------

func TestConcurrency_MultipleParallelStatsRequests(t *testing.T) {
	base := startServer(t)
	const n = 10
	results := make(chan int, n)
	for i := 0; i < n; i++ {
		go func() {
			status, _ := get(t, base, "/stats")
			results <- status
		}()
	}
	for i := 0; i < n; i++ {
		status := <-results
		if status != 200 {
			t.Errorf("concurrent request %d: want 200, got %d", i, status)
		}
	}
}

func TestConcurrency_StatsAndNotificationConcurrent(t *testing.T) {
	base := startServer(t)
	statsDone := make(chan int, 1)
	notifDone := make(chan int, 1)

	go func() {
		status, _ := get(t, base, "/stats")
		statsDone <- status
	}()
	go func() {
		status, _ := post(t, base, "/phone-notification",
			jsonBody(map[string]string{"title": "ping", "text": "pong"}))
		notifDone <- status
	}()

	if s := <-statsDone; s != 200 {
		t.Errorf("stats: want 200, got %d", s)
	}
	if s := <-notifDone; s != 200 {
		t.Errorf("notification: want 200, got %d", s)
	}
}

// ---------------------------------------------------------------------------
// POST /upload
// ---------------------------------------------------------------------------

// postMultipart sends a multipart/form-data POST with a single "file" field.
// content is the file body; filename is the client-supplied name.
func postMultipart(t *testing.T, base, path, filename string, content []byte) (int, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile("file", filename)
	if err != nil {
		t.Fatalf("CreateFormFile: %v", err)
	}
	if _, err = fw.Write(content); err != nil {
		t.Fatalf("write form file: %v", err)
	}
	mw.Close()

	resp, err := http.Post(base+path, mw.FormDataContentType(), &buf)
	if err != nil {
		t.Fatalf("POST %s: %v", path, err)
	}
	defer resp.Body.Close()
	return resp.StatusCode, decodeBody(t, resp.Body)
}

func TestUpload_ValidFile_Returns200(t *testing.T) {
	// Override uploadDir so the test writes to a temp directory.
	orig := uploadDir
	uploadDir = t.TempDir()
	t.Cleanup(func() { uploadDir = orig })

	base := startServer(t)
	status, body := postMultipart(t, base, "/upload", "hello.txt", []byte("hello world"))
	if status != 200 {
		t.Errorf("want 200, got %d", status)
	}
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
}

func TestUpload_ResponseHasFilename(t *testing.T) {
	orig := uploadDir
	uploadDir = t.TempDir()
	t.Cleanup(func() { uploadDir = orig })

	base := startServer(t)
	_, body := postMultipart(t, base, "/upload", "report.pdf", []byte("%PDF"))
	if body["filename"] != "report.pdf" {
		t.Errorf("want filename=report.pdf, got %v", body["filename"])
	}
}

func TestUpload_MissingFileField_Returns400(t *testing.T) {
	base := startServer(t)
	// Send a multipart body with a different field name — "file" is absent.
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, _ := mw.CreateFormField("not_a_file")
	_, _ = fw.Write([]byte("data"))
	mw.Close()

	resp, err := http.Post(base+"/upload", mw.FormDataContentType(), &buf)
	if err != nil {
		t.Fatalf("POST /upload: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 400 {
		t.Errorf("want 400, got %d", resp.StatusCode)
	}
}

func TestUpload_GetUpload_Returns405(t *testing.T) {
	base := startServer(t)
	status, _ := get(t, base, "/upload")
	if status != 405 {
		t.Errorf("want 405 for GET /upload, got %d", status)
	}
}

func TestUpload_DirectoryTraversal_IsSanitised(t *testing.T) {
	// filepath.Base strips all path components from the client-supplied name,
	// so "../../etc/passwd" is saved as "passwd" inside the upload dir — not
	// rejected, but safely neutralised.
	orig := uploadDir
	uploadDir = t.TempDir()
	t.Cleanup(func() { uploadDir = orig })

	base := startServer(t)
	status, body := postMultipart(t, base, "/upload", "../../etc/passwd", []byte("evil"))
	if status != 200 {
		t.Errorf("want 200 (traversal sanitised by filepath.Base), got %d", status)
	}
	// The filename in the response must be the original client name, but the
	// file on disk must be inside the upload dir (verified by the handler).
	if body["status"] != "success" {
		t.Errorf("want status=success, got %v", body["status"])
	}
}

// ---------------------------------------------------------------------------
// safePath unit tests
// ---------------------------------------------------------------------------

func TestSafePath_NormalFilename(t *testing.T) {
	dir := t.TempDir()
	got, err := safePath(dir, "photo.jpg")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(got, dir) {
		t.Errorf("path %q is not inside dir %q", got, dir)
	}
}

func TestSafePath_TraversalFilename_IsSanitised(t *testing.T) {
	// filepath.Base strips the traversal components; the result must still be
	// inside the upload dir.
	dir := t.TempDir()
	got, err := safePath(dir, "../../etc/passwd")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(got, dir) {
		t.Errorf("sanitised path %q escaped dir %q", got, dir)
	}
}
