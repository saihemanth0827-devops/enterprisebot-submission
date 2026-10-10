"""Small dependency-free HTTP service for the DevOps take-home."""
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import socket

CONFIG_DIR = Path(os.environ.get("CONFIG_DIR", "/etc/demo-config"))


def config_value(key: str, default: str) -> str:
    """Read projected ConfigMap files dynamically, falling back to env vars.

    Kubernetes does not refresh process environment variables after a ConfigMap
    changes. Reading projected files per request lets the service reflect a
    ConfigMap update without requiring a pod restart; env vars remain the local
    development/default source as requested by the assignment.
    """
    try:
        value = (CONFIG_DIR / key).read_text(encoding="utf-8").strip()
        if value:
            return value
    except (OSError, UnicodeError):
        pass
    return os.environ.get(key, default)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok\n")
            return
        if self.path == "/":
            payload = {
                "app": config_value("APP_NAME", "demo"),
                "version": config_value("VERSION", "1.0.0"),
                "pod": socket.gethostname(),
            }
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404, "not found")

    def log_message(self, fmt, *args):
        # Keep the container logs useful without exposing request bodies.
        print("%s - %s" % (self.client_address[0], fmt % args), flush=True)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler)
    print("listening on 0.0.0.0:%s" % server.server_port, flush=True)
    server.serve_forever()
