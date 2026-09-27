#!/usr/bin/env python3
"""Read-only, loopback-only viewer for coaching records and referenced local media."""

from __future__ import annotations

import argparse
import json
import mimetypes
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))
from analysis.knowledge_library import KnowledgeLibrary


def referenced_files(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from referenced_files(item)
    elif isinstance(value, list):
        for item in value:
            yield from referenced_files(item)
    elif isinstance(value, str) and value.startswith(".videos/coaching-knowledge/"):
        yield value


def make_handler(library: KnowledgeLibrary):
    catalogue = library.catalogue()
    media_root = (ROOT / ".videos/coaching-knowledge").resolve()
    allowed = {}
    for relative in referenced_files(catalogue):
        path = (ROOT / relative).resolve()
        if path.is_relative_to(media_root):
            allowed[relative] = path
    catalogue["available_assets"] = [key for key, path in allowed.items() if path.is_file()]
    payload = json.dumps(catalogue).encode()
    static_root = ROOT / "tools/knowledge-viewer"

    class Handler(BaseHTTPRequestHandler):
        def do_HEAD(self):
            self.do_GET()

        def do_GET(self):
            route = unquote(urlsplit(self.path).path)
            if route == "/api/library":
                self.send_response(200)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(payload)
                return
            if route in ("/", "/app.js", "/style.css"):
                path = static_root / ("index.html" if route == "/" else route[1:])
            elif route.startswith("/media/"):
                path = allowed.get(route[len("/media/"):])
            else:
                path = None
            if path is None or not path.is_file():
                self.send_error(404, "Local asset is unavailable")
                return
            size = path.stat().st_size
            start, end = 0, size - 1
            range_header = self.headers.get("Range")
            if range_header:
                match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header)
                if not match or not any(match.groups()):
                    self.send_error(416)
                    return
                first, last = match.groups()
                if first:
                    start = int(first)
                    end = min(int(last), size - 1) if last else size - 1
                else:
                    start = max(0, size - int(last))
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
            self.send_response(206 if range_header else 200)
            self.send_header("Content-Type", mimetypes.guess_type(path.name)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(end - start + 1))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("X-Content-Type-Options", "nosniff")
            if range_header:
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            self.end_headers()
            if self.command == "HEAD":
                return
            try:
                with path.open("rb") as stream:
                    stream.seek(start)
                    remaining = end - start + 1
                    while remaining:
                        block = stream.read(min(256 * 1024, remaining))
                        if not block:
                            break
                        self.wfile.write(block)
                        remaining -= len(block)
            except (BrokenPipeError, ConnectionResetError):
                pass  # A video player cancels old ranges when seeking.

    return Handler


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8769)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), make_handler(KnowledgeLibrary()))
    print(f"Coaching library: http://127.0.0.1:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
