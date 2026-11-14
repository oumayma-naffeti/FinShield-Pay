import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        elif self.path.startswith("/api/"):
            self._send(200, {"service": "finshield-pay", "path": self.path})
        else:
            self._send(404, {"error": "not found"})

    def log_message(self, fmt, *args):
        print(fmt % args, flush=True)


HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()