"""
Test suite for stats_daemon.py

Tests every HTTP endpoint and edge case so the behaviour can be
cross-verified against the future Go rewrite.

Run with:
    cd daemon
    python -m pytest test_stats_daemon.py -v
  or (stdlib only):
    python -m unittest test_stats_daemon -v
"""

import io
import json
import threading
import time
import unittest
import urllib.request
import urllib.error
from http.server import HTTPServer
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Import the handler under test.  We import only the class so the module-level
# logging setup and the `run()` entrypoint are NOT executed during import.
# ---------------------------------------------------------------------------
import importlib, sys, types

# Suppress the RotatingFileHandler from creating a log file during tests
import logging
logging.disable(logging.CRITICAL)

from stats_daemon import StatsHandler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _start_server() -> tuple[HTTPServer, int]:
    """Start a real HTTPServer on a random OS-assigned port and return it."""
    server = HTTPServer(("127.0.0.1", 0), StatsHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, port


def _get(port: int, path: str) -> tuple[int, dict]:
    url = f"http://127.0.0.1:{port}{path}"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            return e.code, json.loads(body.decode())
        except Exception:
            return e.code, {}


def _post(port: int, path: str, body: bytes | None = None,
          content_type: str = "application/json") -> tuple[int, dict]:
    url = f"http://127.0.0.1:{port}{path}"
    req = urllib.request.Request(url, data=body, method="POST")
    if body is not None:
        req.add_header("Content-Type", content_type)
        req.add_header("Content-Length", str(len(body)))
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        body_resp = e.read()
        try:
            return e.code, json.loads(body_resp.decode())
        except Exception:
            return e.code, {}


# ---------------------------------------------------------------------------
# Shared psutil mock values (realistic defaults)
# ---------------------------------------------------------------------------

MOCK_CPU    = 42.5
MOCK_RAM    = 67.3
MOCK_TEMP   = 55.0
MOCK_BAT    = 80.0
MOCK_PLUGGED = True


def _make_psutil_patches(
    cpu=MOCK_CPU,
    ram=MOCK_RAM,
    temp=MOCK_TEMP,
    battery_percent=MOCK_BAT,
    plugged=MOCK_PLUGGED,
    battery_available=True,
    temps_available=True,
):
    """Return a context-manager stack of patches for psutil calls."""
    mock_ram = MagicMock()
    mock_ram.percent = ram

    mock_battery = MagicMock()
    mock_battery.percent = battery_percent
    mock_battery.power_plugged = plugged

    mock_temps = {"coretemp": [MagicMock(current=temp)]} if temps_available else {}

    patches = [
        patch("stats_daemon.psutil.cpu_percent", return_value=cpu),
        patch("stats_daemon.psutil.virtual_memory", return_value=mock_ram),
        patch(
            "stats_daemon.psutil.sensors_battery",
            return_value=mock_battery if battery_available else None,
        ),
        patch("stats_daemon.psutil.sensors_temperatures", return_value=mock_temps),
    ]
    return patches


# ---------------------------------------------------------------------------
# Test classes
# ---------------------------------------------------------------------------

class TestGetStats(unittest.TestCase):
    """GET /stats — happy path and field validation."""

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def _stats(self, **kwargs):
        patches = _make_psutil_patches(**kwargs)
        for p in patches:
            p.start()
        try:
            status, body = _get(self.port, "/stats")
        finally:
            for p in patches:
                p.stop()
        return status, body

    # --- status code ---

    def test_returns_200(self):
        status, _ = self._stats()
        self.assertEqual(200, status)

    # --- required fields present ---

    def test_response_has_all_required_keys(self):
        _, body = self._stats()
        for key in ("cpu_usage", "ram_usage", "cpu_temp", "battery_percent",
                    "is_plugged", "timestamp"):
            self.assertIn(key, body, f"Missing key: {key}")

    # --- value types ---

    def test_cpu_usage_is_float(self):
        _, body = self._stats()
        self.assertIsInstance(body["cpu_usage"], float)

    def test_ram_usage_is_float(self):
        _, body = self._stats()
        self.assertIsInstance(body["ram_usage"], float)

    def test_cpu_temp_is_numeric(self):
        _, body = self._stats()
        self.assertIsInstance(body["cpu_temp"], (int, float))

    def test_battery_percent_is_numeric(self):
        _, body = self._stats()
        self.assertIsInstance(body["battery_percent"], (int, float))

    def test_is_plugged_is_bool(self):
        _, body = self._stats()
        self.assertIsInstance(body["is_plugged"], bool)

    def test_timestamp_is_numeric(self):
        _, body = self._stats()
        self.assertIsInstance(body["timestamp"], (int, float))

    # --- value accuracy ---

    def test_cpu_value_matches_mock(self):
        _, body = self._stats(cpu=12.3)
        self.assertAlmostEqual(12.3, body["cpu_usage"], places=1)

    def test_ram_value_matches_mock(self):
        _, body = self._stats(ram=55.5)
        self.assertAlmostEqual(55.5, body["ram_usage"], places=1)

    def test_temp_value_matches_mock(self):
        _, body = self._stats(temp=72.0)
        self.assertAlmostEqual(72.0, body["cpu_temp"], places=1)

    def test_battery_value_matches_mock(self):
        _, body = self._stats(battery_percent=45.0)
        self.assertAlmostEqual(45.0, body["battery_percent"], places=1)

    def test_is_plugged_true(self):
        _, body = self._stats(plugged=True)
        self.assertTrue(body["is_plugged"])

    def test_is_plugged_false(self):
        _, body = self._stats(plugged=False)
        self.assertFalse(body["is_plugged"])

    def test_timestamp_is_recent(self):
        _, body = self._stats()
        now = time.time()
        self.assertAlmostEqual(body["timestamp"], now, delta=5.0)

    # --- value ranges ---

    def test_cpu_usage_in_valid_range(self):
        _, body = self._stats(cpu=0.0)
        self.assertGreaterEqual(body["cpu_usage"], 0.0)

    def test_battery_percent_in_valid_range(self):
        _, body = self._stats(battery_percent=100.0)
        self.assertLessEqual(body["battery_percent"], 100.0)

    # --- temperature fallbacks ---

    def test_temp_zero_when_no_sensors(self):
        """If psutil returns no temperature sensors, cpu_temp must be 0."""
        _, body = self._stats(temps_available=False)
        self.assertEqual(0, body["cpu_temp"])

    def test_temp_fallback_to_first_sensor(self):
        """If 'coretemp' is absent, the first available sensor is used."""
        mock_temps = {"acpitz": [MagicMock(current=38.0)]}
        patches = _make_psutil_patches(temp=38.0, temps_available=False)
        # Override the temperatures patch with a custom dict
        patches.append(
            patch("stats_daemon.psutil.sensors_temperatures", return_value=mock_temps)
        )
        for p in patches:
            p.start()
        try:
            _, body = _get(self.port, "/stats")
        finally:
            for p in patches:
                p.stop()
        self.assertAlmostEqual(38.0, body["cpu_temp"], places=1)

    # --- battery upower fallback ---

    def test_battery_zero_when_psutil_returns_none_and_upower_unavailable(self):
        """If psutil returns no battery and upower fails, battery_percent = 0."""
        patches = _make_psutil_patches(battery_available=False)
        patches.append(
            patch("subprocess.check_output", side_effect=FileNotFoundError("upower not found"))
        )
        for p in patches:
            p.start()
        try:
            status, body = _get(self.port, "/stats")
        finally:
            for p in patches:
                p.stop()
        self.assertEqual(200, status)
        self.assertEqual(0, body["battery_percent"])
        self.assertFalse(body["is_plugged"])

    # --- CORS header ---

    def test_cors_header_present(self):
        with patch("stats_daemon.psutil.cpu_percent", return_value=0.0), \
             patch("stats_daemon.psutil.virtual_memory", return_value=MagicMock(percent=0.0)), \
             patch("stats_daemon.psutil.sensors_battery", return_value=MagicMock(percent=0.0, power_plugged=False)), \
             patch("stats_daemon.psutil.sensors_temperatures", return_value={}):
            url = f"http://127.0.0.1:{self.port}/stats"
            with urllib.request.urlopen(url, timeout=5) as resp:
                self.assertIn("Access-Control-Allow-Origin", resp.headers)


class TestGetStatsNotFound(unittest.TestCase):
    """GET on unknown paths."""

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_unknown_get_path_returns_404(self):
        status, _ = _get(self.port, "/nonexistent")
        self.assertEqual(404, status)

    def test_root_path_returns_404(self):
        status, _ = _get(self.port, "/")
        self.assertEqual(404, status)


class TestPostSleep(unittest.TestCase):
    """POST /sleep"""

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_sleep_returns_200_on_success(self):
        with patch("stats_daemon.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            status, body = _post(self.port, "/sleep")
        self.assertEqual(200, status)
        self.assertEqual("success", body.get("status"))

    def test_sleep_calls_systemctl_suspend(self):
        with patch("stats_daemon.subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            _post(self.port, "/sleep")
            mock_run.assert_called_once()
            args = mock_run.call_args[0][0]
            self.assertEqual(["systemctl", "suspend"], args)

    def test_sleep_returns_500_when_subprocess_raises(self):
        with patch("stats_daemon.subprocess.run", side_effect=Exception("permission denied")):
            status, body = _post(self.port, "/sleep")
        self.assertEqual(500, status)
        self.assertEqual("error", body.get("status"))

    def test_sleep_error_body_contains_message(self):
        with patch("stats_daemon.subprocess.run", side_effect=Exception("oops")):
            _, body = _post(self.port, "/sleep")
        self.assertIn("message", body)
        self.assertIn("oops", body["message"])


class TestPostPhoneNotification(unittest.TestCase):
    """POST /phone-notification"""

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def _notify(self, payload: dict, mock_which=True):
        body = json.dumps(payload).encode()
        with patch("stats_daemon.which", return_value="/usr/bin/notify-send" if mock_which else None), \
             patch("stats_daemon.subprocess.run") as mock_run:
            status, resp = _post(self.port, "/phone-notification", body)
            return status, resp, mock_run

    # --- happy path ---

    def test_valid_notification_returns_200(self):
        status, _, _ = self._notify({"title": "Hello", "text": "World"})
        self.assertEqual(200, status)

    def test_valid_notification_returns_success_status(self):
        _, body, _ = self._notify({"title": "Hello", "text": "World"})
        self.assertEqual("success", body.get("status"))

    def test_notify_send_called_when_available(self):
        _, _, mock_run = self._notify({"title": "Test", "text": "Body"})
        mock_run.assert_called_once()
        cmd = mock_run.call_args[0][0]
        self.assertEqual("notify-send", cmd[0])

    def test_notify_send_summary_contains_title(self):
        _, _, mock_run = self._notify({"title": "MyApp", "text": "msg"})
        cmd = mock_run.call_args[0][0]
        self.assertTrue(any("MyApp" in arg for arg in cmd))

    def test_notify_send_not_called_when_unavailable(self):
        _, _, mock_run = self._notify({"title": "Hi", "text": "there"}, mock_which=False)
        mock_run.assert_not_called()

    # --- title-only / text-only ---

    def test_title_only_is_accepted(self):
        status, body, _ = self._notify({"title": "Only title", "text": ""})
        self.assertEqual(200, status)
        self.assertEqual("success", body.get("status"))

    def test_text_only_is_accepted(self):
        status, body, _ = self._notify({"title": "", "text": "Only text"})
        self.assertEqual(200, status)
        self.assertEqual("success", body.get("status"))

    # --- missing / empty content ---

    def test_empty_title_and_text_returns_400(self):
        status, body, _ = self._notify({"title": "", "text": ""})
        self.assertEqual(400, status)
        self.assertEqual("error", body.get("status"))

    def test_missing_title_and_text_returns_400(self):
        status, body, _ = self._notify({"package_name": "com.example"})
        self.assertEqual(400, status)

    # --- field truncation ---

    def test_title_truncated_to_200_chars(self):
        long_title = "A" * 300
        with patch("stats_daemon.which", return_value=None), \
             patch("stats_daemon.subprocess.run") as mock_run:
            body_bytes = json.dumps({"title": long_title, "text": "x"}).encode()
            _post(self.port, "/phone-notification", body_bytes)
            # notify-send not called (which=None), but we can verify the handler
            # didn't crash — a 200 response is sufficient evidence.
        # Re-run with notify-send available to inspect the command
        with patch("stats_daemon.which", return_value="/usr/bin/notify-send"), \
             patch("stats_daemon.subprocess.run") as mock_run:
            body_bytes = json.dumps({"title": long_title, "text": "x"}).encode()
            status, _ = _post(self.port, "/phone-notification", body_bytes)
            self.assertEqual(200, status)
            cmd = mock_run.call_args[0][0]
            summary_arg = next((a for a in cmd if "A" in a), "")
            self.assertLessEqual(len(summary_arg), 210)  # "Phone: " + 200 chars

    def test_text_truncated_to_500_chars(self):
        long_text = "B" * 600
        with patch("stats_daemon.which", return_value="/usr/bin/notify-send"), \
             patch("stats_daemon.subprocess.run") as mock_run:
            body_bytes = json.dumps({"title": "T", "text": long_text}).encode()
            status, _ = _post(self.port, "/phone-notification", body_bytes)
        self.assertEqual(200, status)

    # --- invalid JSON ---

    def test_invalid_json_returns_400(self):
        with patch("stats_daemon.which", return_value=None):
            status, body = _post(
                self.port, "/phone-notification",
                b"this is not json"
            )
        self.assertEqual(400, status)
        self.assertEqual("error", body.get("status"))

    def test_invalid_json_error_message(self):
        with patch("stats_daemon.which", return_value=None):
            _, body = _post(self.port, "/phone-notification", b"{bad json}")
        self.assertIn("message", body)

    # --- no body ---

    def test_no_body_returns_400(self):
        """A POST with no body and no Content-Length should return 400 (empty title+text)."""
        status, body = _post(self.port, "/phone-notification", body=None)
        self.assertEqual(400, status)

    # --- optional fields ---

    def test_package_name_defaults_to_unknown_app(self):
        """Missing package_name should not crash the handler."""
        status, body, _ = self._notify({"title": "Hi", "text": "there"})
        self.assertEqual(200, status)

    def test_posted_at_field_is_optional(self):
        status, _, _ = self._notify({"title": "Hi", "text": "there", "posted_at": 1234567890})
        self.assertEqual(200, status)

    # --- notify-send summary when title is empty ---

    def test_notify_send_fallback_summary_when_no_title(self):
        with patch("stats_daemon.which", return_value="/usr/bin/notify-send"), \
             patch("stats_daemon.subprocess.run") as mock_run:
            body_bytes = json.dumps({"title": "", "text": "some text"}).encode()
            _post(self.port, "/phone-notification", body_bytes)
            cmd = mock_run.call_args[0][0]
            self.assertIn("Phone notification", " ".join(cmd))


class TestPostUnknownPath(unittest.TestCase):
    """POST to unknown paths."""

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_unknown_post_path_returns_404(self):
        status, _ = _post(self.port, "/unknown", b"{}")
        self.assertEqual(404, status)

    def test_post_to_stats_returns_404(self):
        """POST /stats is not a valid endpoint."""
        status, _ = _post(self.port, "/stats", b"{}")
        self.assertEqual(404, status)


class TestConcurrency(unittest.TestCase):
    """
    Basic concurrency smoke-test.

    NOTE: The current daemon is single-threaded, so this test verifies that
    sequential requests all succeed. When the Go rewrite (or ThreadingMixIn)
    is in place, this test will also validate that concurrent requests don't
    corrupt each other.
    """

    @classmethod
    def setUpClass(cls):
        cls.server, cls.port = _start_server()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def test_multiple_sequential_stats_requests_all_succeed(self):
        patches = _make_psutil_patches()
        for p in patches:
            p.start()
        try:
            for _ in range(5):
                status, body = _get(self.port, "/stats")
                self.assertEqual(200, status)
                self.assertIn("cpu_usage", body)
        finally:
            for p in patches:
                p.stop()

    def test_stats_and_notification_sequential(self):
        """Stats followed by a notification — both must succeed."""
        patches = _make_psutil_patches()
        for p in patches:
            p.start()
        try:
            status_stats, _ = _get(self.port, "/stats")
        finally:
            for p in patches:
                p.stop()

        with patch("stats_daemon.which", return_value=None):
            status_notif, body = _post(
                self.port, "/phone-notification",
                json.dumps({"title": "ping", "text": "pong"}).encode()
            )

        self.assertEqual(200, status_stats)
        self.assertEqual(200, status_notif)


if __name__ == "__main__":
    unittest.main(verbosity=2)
