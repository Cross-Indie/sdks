"""Tiny stand-in for the CrossIndie API used by tests/smoke_test.tscn.

GET  /api/v1/ad/fetch -> one ad with a tracking_token and a PNG banner URL
GET  /img.png         -> 16x9 PNG
POST /api/v1/ad/track -> logged to stdout as TRACK {...}
Run: python3 -I tests/mock_server.py 8765
"""
import json
import struct
import sys
import zlib
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765


def png(w, h, rgb=(40, 120, 220)):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


IMG = png(160, 90)
fetches = 0


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        global fetches
        if self.path.startswith("/api/v1/ad/fetch"):
            fetches += 1
            print("FETCH", self.path, flush=True)
            if "app_id=nofill" in self.path:
                return self._send(204)
            ad = {
                "name": "Mock Game %d" % fetches,
                "description": "mock",
                "tracking_token": "tok-%d" % fetches,
                "target_url": "https://example.com",
                "min_display_ms": 1500,
                "banner_image_url": "http://127.0.0.1:%d/img.png" % PORT,
            }
            return self._send(200, json.dumps(ad).encode())
        if self.path.startswith("/img.png"):
            return self._send(200, IMG, "image/png")
        self._send(404)

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n).decode()
        print("TRACK", self.path, body, flush=True)
        self._send(200, b"{}")


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
