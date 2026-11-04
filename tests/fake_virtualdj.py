"""A stand-in for VirtualDJ's Network Control plugin, for tests/djsync_test.gd.

Answers /query?script=... like VirtualDJ does for one deck playing
"deadmau5 - Strobe" (200 s long) from the moment the server starts.
Extra test-only paths: /truth (the real position in seconds), /pause, /quit.

    python3 tests/fake_virtualdj.py [port]
"""
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LENGTH = 200.0
state = {"t0": time.monotonic() - 30.0, "playing": True, "paused_at": 0.0}


def position() -> float:
    if not state["playing"]:
        return state["paused_at"]
    return time.monotonic() - state["t0"]


ANSWERS = {
    "get_activedeck": lambda: "1",
    "deck 1 get_loaded_song 'title'": lambda: "Strobe",
    "deck 1 get_loaded_song 'artist'": lambda: "deadmau5",
    "deck 1 get_filepath": lambda: "C:\\Music\\strobe.mp3",
    "deck 1 get_songlength": lambda: f"{LENGTH}",
    "deck 1 get_time total": lambda: "3:20",
    "deck 1 get_bpm absolute": lambda: "128.0",
    "deck 1 get_bpm": lambda: "128.0",
    "deck 1 loaded": lambda: "yes",
    "deck 1 play": lambda: "true" if state["playing"] else "false",
    "deck 1 get_position": lambda: f"{position() / LENGTH:.7f}",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive, like the plugin
    disable_nagle_algorithm = True

    def log_message(self, *args):
        pass

    def reply(self, text: str, code: int = 200):
        body = text.encode()
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/truth":
            return self.reply(f"{position():.6f}")
        if url.path == "/pause":
            state["paused_at"] = position()
            state["playing"] = False
            return self.reply("true")
        if url.path == "/quit":
            self.reply("bye")
            self.server.shutdown_requested = True
            return
        if url.path != "/query":
            return self.reply("", 404)
        script = parse_qs(url.query).get("script", [""])[0]
        answer = ANSWERS.get(script)
        self.reply(answer() if answer else "error:-1")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.shutdown_requested = False
    server.timeout = 0.05
    while not server.shutdown_requested:
        server.handle_request()
    server.server_close()
