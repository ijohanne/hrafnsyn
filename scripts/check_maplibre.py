#!/usr/bin/env python3
"""Serve the real vendored browser regression on loopback, without a CSP mask.

Run in the Nix shell, open the printed URL, and require ALL CHECKS PASSED.
Only the fixture and manifest-listed vendor assets can be served.
"""

import argparse
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "priv/static/vendor"
MANIFEST = json.loads((VENDOR / "maplibre-manifest.json").read_text())
LEGACY_SOURCE = None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            path = ROOT / "test/fixtures/maplibre_attribution.html"
            content_type = "text/html; charset=utf-8"
        elif self.path == "/vendor/maplibre-legacy.js" and LEGACY_SOURCE is not None:
            self.send_content(LEGACY_SOURCE, "text/javascript")
            return
        elif self.path == "/vendor/maplibre-gl.mjs" and LEGACY_SOURCE is not None:
            shim = b'import "./maplibre-legacy.js"; const {Map, AttributionControl, NavigationControl, ScaleControl, Marker, Popup, getVersion} = window.maplibregl; export {Map, AttributionControl, NavigationControl, ScaleControl, Marker, Popup, getVersion};'
            self.send_content(shim, "text/javascript")
            return
        elif self.path.removeprefix("/vendor/") in MANIFEST["sha256"]:
            path = VENDOR / self.path.removeprefix("/vendor/")
            content_type = "text/css" if path.suffix == ".css" else "text/javascript"
        else:
            self.send_error(404)
            return
        self.send_content(path.read_bytes(), content_type)

    def send_content(self, contents, content_type):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(contents)))
        self.end_headers()
        self.wfile.write(contents)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--baseline-ref", help="Demonstrate the vulnerable original UMD from this Git revision")
    args = parser.parse_args()
    if args.baseline_ref:
        LEGACY_SOURCE = subprocess.check_output(
            ["git", "-C", str(ROOT), "show", f"{args.baseline_ref}:priv/static/vendor/maplibre-gl.js"]
        )
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Open http://127.0.0.1:{server.server_port}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
