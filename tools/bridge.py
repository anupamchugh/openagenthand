#!/usr/bin/env python3
"""Serve a bounded local event feed and connect explicit read-only demo producers."""

import argparse
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hmac
import json
import os
import re
import secrets
import selectors
import subprocess
import sys
from threading import Lock
import time
from urllib.request import Request, urlopen
from uuid import uuid4


LABELS = {
    "scout-start": ("researcher", "working", "Scout is choosing a signal"),
    "scout-sent": ("researcher", "done", "Scout delivered a valid signal"),
    "scout-failed": ("researcher", "failed", "Scout returned no valid signal"),
    "reviewer-wait": ("reviewer", "waiting", "Waiting for the scout"),
    "reviewer-start": ("reviewer", "working", "Interpreter received the scout’s signal"),
    "reviewer-matched": ("reviewer", "done", "Interpreter echoed the scout’s signal"),
    "reviewer-failed": ("reviewer", "failed", "Interpreter did not confirm the signal"),
    "github-start": ("builder", "working", "Threadmark is reading GitHub stars"),
    "github-done": ("builder", "done", "Threadmark returned public GitHub stars"),
    "github-empty": ("builder", "done", "Threadmark returned an empty public stars page"),
    "github-failed": ("builder", "failed", "Threadmark did not return a valid stars page"),
    "fixture": ("tester", "done", "Local fixture reached the hand"),
}


def serve(bind, port, token):
    events = deque(maxlen=195)
    latest = {}
    run_id = str(uuid4())
    lock = Lock()
    sequence = 0

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *_):
            pass

        def authorized(self):
            if self.path != "/v1/events":
                self.send_error(404)
                return False
            actual = self.headers.get("Authorization", "").encode()
            if not hmac.compare_digest(actual, f"Bearer {token}".encode()):
                self.send_error(401)
                return False
            return True

        def do_GET(self):
            if not self.authorized():
                return
            with lock:
                by_id = {event["id"]: event for event in (*events, *latest.values())}
                data = json.dumps({
                    "runID": run_id,
                    "events": [by_id[key] for key in sorted(by_id)],
                }).encode()
            self.send_response(200)
            for key, value in {
                "Content-Type": "application/json", "Cache-Control": "no-store",
                "Content-Length": str(len(data)),
            }.items():
                self.send_header(key, value)
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            nonlocal sequence
            if self.client_address[0] != "127.0.0.1":
                self.send_error(403)
                return
            if not self.authorized():
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 128:
                    raise ValueError()
                agent, phase, detail = LABELS[json.loads(self.rfile.read(length))]
            except (KeyError, TypeError, ValueError):
                self.send_error(400)
                return
            with lock:
                sequence += 1
                event = {"id": sequence, "agent": agent, "phase": phase, "detail": detail}
                events.append(event)
                latest[agent] = event
            self.send_response(204)
            self.end_headers()

    with ThreadingHTTPServer((bind, port), Handler) as server:
        print(f"Port: {server.server_port}", flush=True)
        if "OPEN_AGENT_HAND_TOKEN" not in os.environ:
            print(f"Session token: {token}", flush=True)
        server.serve_forever()


def post(port, token, change):
    request = Request(
        f"http://127.0.0.1:{port}/v1/events", method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        data=json.dumps(change).encode(),
    )
    with urlopen(request, timeout=5):
        pass


def codex(prompt):
    result = subprocess.run(
        ["codex", "exec", "--skip-git-repo-check", "--sandbox", "read-only", "--json", prompt],
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, text=True, timeout=120,
    )
    if result.returncode != 0:
        return ""
    reply = ""
    for line in result.stdout.splitlines():
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        item = row.get("item", {})
        if row.get("type") == "item.completed" and item.get("type") == "agent_message":
            reply = item.get("text", "").strip()
    return reply.upper()


def relay(publish):
    publish("reviewer-wait")
    publish("scout-start")
    try:
        signal = codex("Pick MOON, STAR, or PULSE. Reply with only the chosen word. Do not use tools.")
    except (OSError, subprocess.TimeoutExpired):
        signal = ""
    if signal not in {"MOON", "STAR", "PULSE"}:
        publish("scout-failed")
        publish("reviewer-failed")
        return False
    publish("scout-sent")
    publish("reviewer-start")
    try:
        matched = codex(f"The scout sent {signal}. Reply with that word only. Do not use tools.") == signal
    except (OSError, subprocess.TimeoutExpired):
        matched = False
    publish("reviewer-matched" if matched else "reviewer-failed")
    return matched


def threadmark_page(command, username):
    with subprocess.Popen([command], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0) as process:
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                pending = bytearray()

                def request(method, params, identifier=None):
                    message = {"jsonrpc": "2.0", "method": method, "params": params}
                    if identifier is not None:
                        message["id"] = identifier
                    process.stdin.write(json.dumps(message).encode() + b"\n")
                    if identifier is None:
                        return None
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        while b"\n" in pending:
                            line, _, remainder = pending.partition(b"\n")
                            pending[:] = remainder
                            result = json.loads(line)
                            if result.get("id") == identifier:
                                return result.get("result")
                        if selector.select(max(0, deadline - time.monotonic())):
                            data = os.read(process.stdout.fileno(), 65536)
                            if not data or len(pending) + len(data) > 1_000_000:
                                break
                            pending.extend(data)
                    return None

                if not request("initialize", {
                    "protocolVersion": "2024-11-05", "capabilities": {},
                    "clientInfo": {"name": "open-agent-hand", "version": "0.1.0"},
                }, 1):
                    return None
                request("notifications/initialized", {})
                reply = request("tools/call", {
                    "name": "github_starred", "arguments": {"username": username, "max_items": 5},
                }, 2)
                if not reply or reply.get("isError"):
                    return None
                for item in reply.get("content", []):
                    try:
                        result = json.loads(item.get("text", ""))
                    except (TypeError, ValueError):
                        continue
                    if isinstance(result, dict) and result.get("status") == "collected":
                        rows = result.get("repositories")
                        if isinstance(rows, list) and len(rows) <= 5:
                            return len(rows)
        finally:
            process.terminate()
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8672)
    operations = parser.add_subparsers(dest="operation", required=True)
    server = operations.add_parser("serve")
    server.add_argument("--bind", choices=("127.0.0.1", "0.0.0.0"), default="127.0.0.1")
    operations.add_parser("codex-relay")
    operations.add_parser("fixture")
    threadmark = operations.add_parser("threadmark")
    threadmark.add_argument("username")
    threadmark.add_argument("--command", default="threadmark-mcp")
    args = parser.parse_args()
    token = os.environ.get("OPEN_AGENT_HAND_TOKEN") or secrets.token_urlsafe(32)
    if not re.fullmatch(r"[A-Za-z0-9_-]{24,512}", token):
        parser.error("Use a URL-safe session token with at least 24 characters.")
    if args.operation == "serve":
        serve(args.bind, args.port, token)
        return 0
    if "OPEN_AGENT_HAND_TOKEN" not in os.environ:
        parser.error("Set OPEN_AGENT_HAND_TOKEN to the server's session token.")

    def publish(change):
        post(args.port, token, change)

    if args.operation == "fixture":
        publish("fixture")
        return 0
    if args.operation == "codex-relay":
        return 0 if relay(publish) else 1
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})", args.username):
        parser.error("Provide a GitHub login.")
    publish("github-start")
    try:
        count = threadmark_page(args.command, args.username)
    except (OSError, ValueError):
        count = None
    publish("github-failed" if count is None else "github-done" if count else "github-empty")
    if count is not None:
        print(f"Threadmark returned {count} public starred repositories.")
    return int(count is None)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
    except OSError as error:
        sys.exit(f"Open Agent Hand: {error}")
