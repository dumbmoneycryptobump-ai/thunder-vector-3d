"""Serve one exported Godot Web directory. Local-only by default; no COOP needed."""
from __future__ import annotations

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class WebHandler(SimpleHTTPRequestHandler):
    extensions_map = {
        **SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".webmanifest": "application/manifest+json; charset=utf-8",
    }

    def send_head(self):
        # SimpleHTTPRequestHandler normalizes URL paths; also reject escaping links.
        root = Path(self.directory).resolve()
        target = Path(self.translate_path(self.path)).resolve()
        if not target.is_relative_to(root):
            self.send_error(403, "Path outside export directory")
            return None
        # The base handler may implicitly open index.html for a directory URL.
        # Validate that final file too, rather than only its containing directory.
        if target.is_dir():
            for name in ("index.html", "index.htm"):
                index = target / name
                if index.is_file():
                    if not index.resolve().is_relative_to(root):
                        self.send_error(403, "Index outside export directory")
                        return None
                    break
        return super().send_head()

    def list_directory(self, path):
        self.send_error(403, "Directory listing is disabled")
        return None

    def end_headers(self):
        # Revalidate mutable export names. Godot's versioned PWA cache handles offline.
        self.send_header("Cache-Control", "no-cache, max-age=0, must-revalidate")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "same-origin")
        # Deliberately no COOP/COEP: this project uses the single-threaded template.
        super().end_headers()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True, help="Exported site directory, not the source repository")
    parser.add_argument("--bind", default="127.0.0.1", help="Use 0.0.0.0 explicitly for trusted-LAN phone testing")
    parser.add_argument("--port", type=int, default=8060)
    args = parser.parse_args()
    directory = args.directory.resolve(strict=True)
    if not directory.is_dir() or not (directory / "index.html").is_file() or not (directory / "index.wasm").is_file():
        parser.error("directory must contain an exported index.html and index.wasm")
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    with ThreadingHTTPServer((args.bind, args.port), partial(WebHandler, directory=str(directory))) as server:
        print(f"Serving {directory}\nURL: http://{args.bind}:{args.port}/", flush=True)
        print("Single-threaded Web export; HTTPS or localhost is required for PWA/offline caching.", flush=True)
        if args.bind not in {"127.0.0.1", "::1", "localhost"}:
            print("LAN exposure explicitly enabled. Use the computer's LAN IP on the phone; do not expose this development server publicly.", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("Server stopped.", flush=True)


if __name__ == "__main__":
    main()
