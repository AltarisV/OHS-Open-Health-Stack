#!/usr/bin/env python3
"""Serves docs/test-ui and proxies the OHS services under one origin.

Why this exists: the test console is a browser page, so every call it makes is
subject to CORS. Served straight from `python -m http.server`, the page lives on
one origin and each port-forward is another, and of the services only EHRbase and
Keycloak send CORS headers at all - Eos, openFHIR and the Cohort Explorer backend
send none, so steps 4, 6 and 7 can never read a response. Eos is the nastiest
case: its POST is a "simple request", so the conversion really does run and only
the *response* is withheld from the page, which looks exactly like a failure that
did nothing.

Putting the console and the services behind a single origin removes the problem
at the root instead of asking five services to grow a CORS policy each. Nothing
here is a security control - it binds to loopback and forwards whatever it gets.

This does not apply behind the ingress/gateway, where everything already shares
one origin.

Usage:
    bash scripts/port-forward.sh          # in another terminal
    python scripts/test-ui-proxy.py       # then open the URL it prints

Override an upstream when your port-forwards differ:
    python scripts/test-ui-proxy.py --map eos=http://localhost:9082
"""

import argparse
import http.server
import socket
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Route prefix -> upstream. The console's config fields hold "/svc/<name>", and
# everything after that prefix is forwarded unchanged, so the paths the console
# builds ("/ehrbase/rest/...", "/auth/realms/...") still arrive intact upstream.
UPSTREAMS = {
    "ehrbase": "http://localhost:8080",
    "openfhir": "http://localhost:8081",
    "eos": "http://localhost:8082",
    "keycloak": "http://localhost:8083",
    "ceb": "http://localhost:8084",
    "cef": "http://localhost:8085",
}

PREFIX = "/svc/"

# Hop-by-hop headers must not be forwarded (RFC 9110 7.6.1). Content-Length and
# Host are dropped because urllib recomputes them for the upstream request.
HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    upstreams: dict = UPSTREAMS

    def do_GET(self):
        self.route()

    def do_POST(self):
        self.route()

    def do_PUT(self):
        self.route()

    def do_DELETE(self):
        self.route()

    def do_OPTIONS(self):
        # Same-origin means the browser never sends a preflight to us, but a
        # stray one must not fall through to the static file handler.
        if self.path.startswith(PREFIX):
            self.route()
        else:
            self.send_response(200)
            self.end_headers()

    def route(self):
        if self.path.startswith(PREFIX):
            self.proxy()
        elif self.command == "GET":
            super().do_GET()
        else:
            self.send_error(405, "Only GET is served from disk")

    def proxy(self):
        rest = self.path[len(PREFIX):]
        name, _, tail = rest.partition("/")
        base = self.upstreams.get(name)
        if base is None:
            self.send_error(404, f"Unknown upstream '{name}'")
            return
        url = f"{base}/{tail}"

        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None

        headers = {
            k: v for k, v in self.headers.items()
            if k.lower() not in HOP_BY_HOP
        }

        req = urllib.request.Request(url, data=body, method=self.command,
                                     headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                self.relay(resp.status, resp.headers, resp.read())
        except urllib.error.HTTPError as e:
            # A 4xx/5xx is a real answer from the service - the console needs to
            # show it, not a proxy error page.
            self.relay(e.code, e.headers, e.read())
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            reason = getattr(e, "reason", e)
            self.send_error(502, f"Upstream {name} unreachable: {reason}")

    def relay(self, status, headers, payload):
        self.send_response(status)
        for k, v in headers.items():
            if k.lower() not in HOP_BY_HOP:
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        sys.stderr.write(f"  {self.address_string()} {fmt % args}\n")


def main():
    repo_root = Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8888)
    ap.add_argument("--docs", default=str(repo_root / "docs"),
                    help="directory served at / (default: the repo's docs/)")
    ap.add_argument("--map", action="append", default=[], metavar="NAME=URL",
                    help="override an upstream, e.g. eos=http://localhost:9082")
    args = ap.parse_args()

    upstreams = dict(UPSTREAMS)
    for entry in args.map:
        name, sep, url = entry.partition("=")
        if not sep or name not in upstreams:
            ap.error(f"--map expects NAME=URL with NAME one of "
                     f"{', '.join(sorted(upstreams))}; got '{entry}'")
        upstreams[name] = url.rstrip("/")

    docs = Path(args.docs).resolve()
    if not (docs / "test-ui" / "index.html").is_file():
        ap.error(f"{docs} does not contain test-ui/index.html")

    Handler.upstreams = upstreams

    def factory(*a, **kw):
        return Handler(*a, directory=str(docs), **kw)

    class Server(http.server.ThreadingHTTPServer):
        # Without this a service that is slow to answer blocks every other
        # request, including the page's own static assets.
        daemon_threads = True
        allow_reuse_address = True

    try:
        httpd = Server(("127.0.0.1", args.port), factory)
    except OSError as e:
        if e.errno in (socket.EADDRINUSE, 10048):
            sys.exit(f"Port {args.port} is already in use. Pass --port.")
        raise

    print(f"Console : http://localhost:{args.port}/test-ui/")
    print(f"Serving : {docs}")
    print("Upstream:")
    for name, url in sorted(upstreams.items()):
        print(f"  {PREFIX}{name:<9} -> {url}")
    print("\nCtrl+C to stop.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
