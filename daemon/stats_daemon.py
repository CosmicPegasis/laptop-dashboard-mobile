import http.server
import json
import psutil
import time
import logging
import sys
from logging.handlers import RotatingFileHandler

# Configure logging
LOG_FILE = "stats_daemon.log"
logger = logging.getLogger("stats-daemon")
logger.setLevel(logging.INFO)

# Create formatters
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')

# Console Handler
console_handler = logging.StreamHandler(sys.stdout)
console_handler.setFormatter(formatter)
logger.addHandler(console_handler)

# File Handler (with rotation for production readiness)
file_handler = RotatingFileHandler(LOG_FILE, maxBytes=10*1024*1024, backupCount=5)
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

class StatsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        client_ip = self.client_address[0]
        if self.path == '/stats':
            try:
                # CPU Usage (interval=None is non-blocking)
                cpu_usage = psutil.cpu_percent(interval=None)
                
                # RAM Usage
                ram = psutil.virtual_memory()
                ram_usage = ram.percent
                
                # CPU Temperature
                temp = 0
                try:
                    temps = psutil.sensors_temperatures()
                    if 'coretemp' in temps:
                        temp = temps['coretemp'][0].current
                    elif 'cpu_thermal' in temps:
                        temp = temps['cpu_thermal'][0].current
                    elif temps:
                        # Fallback to the first available sensor
                        for name, entries in temps.items():
                            if entries:
                                temp = entries[0].current
                                break
                except Exception as e:
                    logger.error(f"Error collecting temperature stats: {e}")
                
                # Battery Info
                battery_percent = 0
                is_plugged = False
                try:
                    # Try psutil first
                    battery = psutil.sensors_battery()
                    if battery:
                        battery_percent = battery.percent
                        is_plugged = battery.power_plugged
                    else:
                        # Fallback to upower for systems where psutil fails (e.g. certain kernels/setups)
                        import subprocess
                        # List devices to find the battery (usually BAT0 or CMB0)
                        devices = subprocess.check_output(["upower", "-e"], text=True).splitlines()
                        battery_path = next((d for d in devices if "battery" in d), None)
                        if battery_path:
                            info = subprocess.check_output(["upower", "-i", battery_path], text=True)
                            for line in info.splitlines():
                                if "percentage:" in line:
                                    battery_percent = float(line.split(":")[1].replace("%", "").strip())
                                if "state:" in line:
                                    is_plugged = "charging" in line.lower() or "fully-charged" in line.lower()
                except Exception as e:
                    logger.error(f"Error collecting battery stats: {e}")

                stats = {
                    "cpu_usage": cpu_usage,
                    "ram_usage": ram_usage,
                    "cpu_temp": temp,
                    "battery_percent": battery_percent,
                    "is_plugged": is_plugged,
                    "timestamp": time.time()
                }

                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()
                
                self.wfile.write(json.dumps(stats).encode('utf-8'))
                logger.info(f"Served stats to {client_ip}")
                logger.debug(f"Stats data: {stats}")
            except Exception as e:
                logger.error(f"Error serving stats to {client_ip}: {e}")
                self.send_response(500)
                self.end_headers()
        else:
            self.send_response(404)
            self.end_headers()
            logger.warning(f"Path not found: {self.path} (Request from {client_ip})")

    def log_message(self, format, *args):
        # Silence default HTTP server logging to avoid double logs since we manually log requests
        pass

def run(server_class=http.server.HTTPServer, handler_class=StatsHandler, port=8081):
    server_address = ('', port)
    try:
        httpd = server_class(server_address, handler_class)
        logger.info(f"Starting stats daemon on port {port}...")
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Stopping stats daemon (KeyboardInterrupt)...")
    except Exception as e:
        logger.error(f"Server error: {e}")
    finally:
        if 'httpd' in locals():
            httpd.server_close()
            logger.info("Server closed.")

if __name__ == '__main__':
    # Initial call to cpu_percent to initialize
    psutil.cpu_percent(interval=None)
    run()
