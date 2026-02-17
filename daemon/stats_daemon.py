import http.server
import json
import psutil
import time
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("stats-daemon")

class StatsHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/stats':
            # CPU Usage (interval=None is non-blocking)
            cpu_usage = psutil.cpu_percent(interval=None)
            
            # RAM Usage
            ram = psutil.virtual_memory()
            ram_usage = ram.percent
            
            # CPU Temperature
            temp = 0
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
            
            stats = {
                "cpu_usage": cpu_usage,
                "ram_usage": ram_usage,
                "cpu_temp": temp,
                "timestamp": time.time()
            }

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            self.wfile.write(json.dumps(stats).encode('utf-8'))
            logger.debug(f"Served stats: {stats}")
        else:
            self.send_response(404)
            self.end_headers()
            logger.warning(f"Path not found: {self.path}")

    def log_message(self, format, *args):
        # Use standard logging instead of sys.stderr
        logger.info("%s - - %s" % (self.address_string(), format % args))

def run(server_class=http.server.HTTPServer, handler_class=StatsHandler, port=8081):
    server_address = ('', port)
    httpd = server_class(server_address, handler_class)
    logger.info(f"Starting stats daemon on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        logger.info("Stopping stats daemon...")
    httpd.server_close()

if __name__ == '__main__':
    # Initial call to cpu_percent to initialize
    psutil.cpu_percent(interval=None)
    run()
