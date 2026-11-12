"""Check what a real VirtualDJ answers, without starting Precision.

Run it on the computer with VirtualDJ, with a track loaded on deck 1 and
playing (then run it again paused, and again with a track on deck 2):

    python vdj_probe.py [--host 127.0.0.1] [--port 80] [--password XXX]
                        [--os2l-seconds 10] [--out vdj_probe_report.txt]

It asks every question Precision asks, plus a few alternative spellings, and
prints a table of what came back. Send the report file (or paste it).
Python 3.8+, nothing to install.
"""
import argparse
import json
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# (what we use it for, command). {d} is the deck number.
CORE = [
    ("active deck", "get_activedeck"),
    ("title", "deck {d} get_loaded_song 'title'"),
    ("artist", "deck {d} get_loaded_song 'artist'"),
    ("file path", "deck {d} get_filepath"),
    ("length (s)", "deck {d} get_songlength"),
    ("length text", "deck {d} get_time total"),
    ("bpm (now)", "deck {d} get_bpm"),
    ("bpm (original)", "deck {d} get_bpm absolute"),
    ("loaded?", "deck {d} loaded"),
    ("playing?", "deck {d} play"),
    ("position 0..1", "deck {d} get_position"),
]
# Only needed if a CORE one fails; shows which spelling works on this build.
ALTERNATES = [
    ("active deck (alt)", "deck active get_deck"),
    ("active deck (alt 2)", "get_deck"),
    ("title (alt)", "deck {d} get_title"),
    ("artist (alt)", "deck {d} get_artist"),
    ("file path (alt)", "deck {d} get_filepath"),
    ("length (alt)", "deck {d} get_length"),
    ("elapsed text", "deck {d} get_time"),
    ("elapsed (ms)", "deck {d} get_time 'elapsed'"),
    ("position (alt)", "deck {d} get_position 'absolute'"),
    ("is playing (alt)", "deck {d} is_playing"),
    ("pitch", "deck {d} pitch"),
    ("beat position", "deck {d} get_beat"),
    ("version", "get_version"),
    ("os2l option", "setting 'os2lDirectIp'"),
]


def ask(base, script, password, timeout=2.0):
    url = f"{base}/query?script={urllib.parse.quote(script, safe='')}"
    if password:
        url += "&bearer=" + urllib.parse.quote(password, safe="")
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
            return r.status, body, (time.perf_counter() - t0) * 1000
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), (time.perf_counter() - t0) * 1000
    except Exception as e:  # noqa: BLE001
        return None, f"{type(e).__name__}: {e}", (time.perf_counter() - t0) * 1000


def verdict(status, body):
    if status is None:
        return "NO ANSWER"
    if status in (401, 403):
        return "REFUSED (password?)"
    if status >= 400:
        return f"HTTP {status}"
    b = body.strip()
    if b.lower().startswith("error"):
        return "NOT UNDERSTOOD"
    if not b:
        return "empty"
    return "ok"


def listen_os2l(port, seconds, result):
    """Accept VirtualDJ's OS2L connection and count beat messages."""
    result.update(listening=False, clients=0, beats=0, other=[], first=[], error="")
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind(("0.0.0.0", port))
    except OSError as e:
        result["error"] = f"can't listen on {port}: {e} (is Precision running? close it)"
        return
    srv.listen(4)
    srv.settimeout(0.2)
    result["listening"] = True
    conns, bufs = [], {}
    end = time.time() + seconds
    while time.time() < end:
        try:
            c, addr = srv.accept()
            c.settimeout(0.05)
            conns.append(c)
            bufs[c] = b""
            result["clients"] += 1
        except socket.timeout:
            pass
        for c in conns:
            try:
                data = c.recv(4096)
            except (socket.timeout, BlockingIOError):
                continue
            except OSError:
                continue
            if not data:
                continue
            bufs[c] += data
            while b"}" in bufs[c]:
                i = bufs[c].index(b"}") + 1
                chunk, bufs[c] = bufs[c][:i], bufs[c][i:]
                try:
                    msg = json.loads(chunk.decode("utf-8", "replace").strip())
                except ValueError:
                    result["other"].append(chunk[:80].decode("utf-8", "replace"))
                    continue
                if msg.get("evt") == "beat":
                    result["beats"] += 1
                    if len(result["first"]) < 5:
                        result["first"].append(msg)
                elif len(result["other"]) < 10:
                    result["other"].append(msg)
    srv.close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=80)
    ap.add_argument("--password", default="")
    ap.add_argument("--deck", type=int, default=0, help="deck to probe (default: the active one)")
    ap.add_argument("--os2l-port", type=int, default=9996)
    ap.add_argument("--os2l-seconds", type=float, default=10.0, help="0 to skip the OS2L check")
    ap.add_argument("--out", default="vdj_probe_report.txt")
    a = ap.parse_args()

    lines = []

    def out(s=""):
        print(s)
        lines.append(s)

    base = f"http://{a.host}:{a.port}"
    out(f"VirtualDJ probe  {time.strftime('%Y-%m-%d %H:%M:%S')}  python {sys.version.split()[0]}  target {base}")

    os2l = {}
    th = None
    if a.os2l_seconds > 0:
        th = threading.Thread(target=listen_os2l, args=(a.os2l_port, a.os2l_seconds, os2l))
        th.start()

    status, body, ms = ask(base, "get_activedeck", a.password)
    if status is None:
        out(f"\nCan't reach VirtualDJ's Network Control at {base}: {body}")
        out("Check: Network Control enabled (Settings > Extensions > Effects > Other), set as an")
        out("Auto-Start master effect, and the port in its cog matches --port.")
        if th:
            th.join()
        open(a.out, "w").write("\n".join(lines) + "\n")
        return 1

    deck = a.deck
    if not deck:
        digits = "".join(ch for ch in body if ch.isdigit())
        deck = int(digits) if digits else 1
    out(f"probing deck {deck}\n")

    out(f"{'what':<20} {'command':<38} {'verdict':<20} {'ms':>6}  answer")
    out("-" * 110)
    results = {}
    for section, items in (("CORE", CORE), ("ALTERNATES (only matter if a core one failed)", ALTERNATES)):
        out(f"-- {section}")
        for label, cmd in items:
            c = cmd.format(d=deck)
            st, bd, ms = ask(base, c, a.password)
            v = verdict(st, bd)
            results[c] = v
            out(f"{label:<20} {c:<38} {v:<20} {ms:6.1f}  {bd.strip()[:60]!r}")

    # Is position moving, and how fast do answers come back?
    out("\n-- position over 3 seconds (should rise ~1 s per second if playing)")
    pc = f"deck {deck} get_position"
    samples = []
    t_end = time.time() + 3
    lat = []
    while time.time() < t_end:
        st, bd, ms = ask(base, pc, a.password)
        lat.append(ms)
        try:
            samples.append((time.time(), float(bd.strip().strip("'\"").replace(",", "."))))
        except ValueError:
            pass
        time.sleep(0.05)
    if len(samples) >= 2:
        (t0, p0), (t1, p1) = samples[0], samples[-1]
        out(f"first={p0:.6f} last={p1:.6f} over {t1 - t0:.2f}s, {len(samples)} reads, "
            f"latency avg {sum(lat) / len(lat):.1f} ms max {max(lat):.1f} ms")
        out("value looks like a " + ("percentage 0-100" if p1 > 1.0 else "fraction 0-1"))
        _, ld, _ = ask(base, f"deck {deck} get_songlength", a.password)
        try:
            length = float(ld.strip().strip("'\"").replace(",", "."))
            if p1 != p0 and t1 > t0:
                scale = 100.0 if p1 > 1.0 else 1.0
                out(f"implied speed: {((p1 - p0) / scale * length) / (t1 - t0):.3f} s of track per real second (1.000 = normal)")
        except ValueError:
            out("couldn't read get_songlength as a number")
    else:
        out("no numeric position readings")

    if th:
        out(f"\n-- OS2L: listened on port {a.os2l_port} for {a.os2l_seconds:.0f}s (press play in VirtualDJ now)")
        th.join()
        if os2l.get("error"):
            out(os2l["error"])
        else:
            out(f"clients connected: {os2l['clients']}, beat messages: {os2l['beats']}")
            for m in os2l["first"]:
                out(f"  beat: {m}")
            for m in os2l["other"]:
                out(f"  other: {m}")
            if os2l["clients"] == 0:
                out("VirtualDJ never connected. Set the option os2lDirectIp to 127.0.0.1:%d (Settings > Options)," % a.os2l_port)
                out("restart VirtualDJ if needed, and make sure a deck is playing.")

    bad = [c for c, v in results.items() if v != "ok" and c in [x[1].format(d=deck) for x in CORE]]
    out("\nSUMMARY")
    out("All core commands answered." if not bad else "Core commands with problems: " + "; ".join(bad))
    open(a.out, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"\nSaved to {a.out}")
    return 0 if not bad else 2


if __name__ == "__main__":
    sys.exit(main())
