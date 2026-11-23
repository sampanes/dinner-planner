"""The recipe notes written in the phone app, read at this computer.

The phones keep the household's plan, and the notes on recipes ("add parmesan
as a step"), in a private relay topic that only the household code opens. This
script joins that topic as a listener, the way a linked kitchen screen does
(house.js): it never writes a plan entry, it folds in what the phones send and
tells them what it holds. A phone that hears it is missing something sends it,
the next time that phone syncs (every 20 seconds while the app is open).

The code and what was heard are kept in private/house.json, which git ignores.

    python scripts/house_notes.py --link       paste the household code (phone app: Settings)
    python scripts/house_notes.py              print the notes
    python scripts/house_notes.py --wait 90    ask the phones again and wait for answers
    python scripts/house_notes.py --json       the notes as JSON, slug -> note
    python scripts/house_notes.py --unlink     forget the code

Mirrors apps/dinner_planner/lib/core/sync_core.dart; tests/test_house_mirror.py
checks the digest against the phone app's.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import secrets
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE_PATH = ROOT / "private" / "house.json"
RECIPES_PATH = ROOT / "data" / "runtime" / "recipes.runtime.json"

WIRE = "dp2 "
CLOCK_SLACK = timedelta(minutes=10)
DIGEST_DAYS = 30
KEEP_DAYS = 60
ANNOUNCE_EVERY_S = 10 * 60
ISO = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$")
DAY_KEY = re.compile(r"/(\d{4}-\d\d-\d\d)$")
TOPIC = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


# ---------- household codes (relay.dart Household.fromCode) ----------
def house_from_code(code: str) -> dict | None:
    text = re.sub(r"\s+", "", code or "")
    if not text:
        return None
    try:
        raw = json.loads(base64.urlsafe_b64decode(text + "=" * (-len(text) % 4)).decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None
    if not isinstance(raw, dict):
        return None
    server, topic, token = raw.get("s"), raw.get("t"), raw.get("k")
    if not isinstance(server, str) or not isinstance(topic, str) or not TOPIC.match(topic):
        return None
    parts = urllib.parse.urlparse(server.strip())
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return None
    token = token.strip() if isinstance(token, str) and token.strip() else None
    return {"s": server.strip().rstrip("/"), "t": topic, "k": token}


# ---------- entries and digest (sync_core.dart) ----------
def entry_from_wire(raw) -> tuple | None:
    if not isinstance(raw, list) or len(raw) != 4:
        return None
    k, v, at, dev = raw
    if not isinstance(k, str) or not k or len(k) > 80:
        return None
    if not (v is None or isinstance(v, (str, int, float, bool))):
        return None
    if isinstance(v, str) and len(v) > 400:
        return None
    if not isinstance(at, str) or not ISO.match(at):
        return None
    if not isinstance(dev, str) or not dev or len(dev) > 32:
        return None
    return k, v, at, dev


def beats(at: str, dev: str, cur_at: str, cur_dev: str) -> bool:
    """Newest write wins; a tie goes to the larger device id."""
    return at > cur_at or (at == cur_at and dev > cur_dev)


def stamp(t: datetime) -> str:
    """UTC time as fixed-width text, so that comparing the text compares the time."""
    u = t.astimezone(timezone.utc)
    return u.strftime("%Y-%m-%dT%H:%M:%S.") + f"{u.microsecond // 1000:03d}Z"


def utc_day(ms: float) -> str:
    return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")


def older_than(key: str, cutoff_day: str) -> bool:
    m = DAY_KEY.search(key)
    return bool(m) and m.group(1) < cutoff_day


def digest_of(entries: dict, now_ms: float) -> str:
    """A fingerprint of the whole state; equal to the phones' when both hold the same facts."""
    cutoff = utc_day(now_ms - DIGEST_DAYS * 864e5)
    keys = sorted(k for k in entries if not older_than(k, cutoff))
    text = json.dumps([[k, *entries[k]] for k in keys], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def receive(state: dict, line: str, now: datetime) -> bool:
    """Folds one "dp2 ..." line in; True when it changed anything."""
    try:
        raw = json.loads(line[len(WIRE):])
    except ValueError:
        return False
    if not isinstance(raw, dict) or not isinstance(raw.get("d"), str) or raw["d"] == state["dev"]:
        return False
    latest = stamp(now + CLOCK_SLACK)
    changed = False
    for item in raw.get("s") if isinstance(raw.get("s"), list) else []:
        e = entry_from_wire(item)
        if not e or e[2] > latest:
            continue
        k, v, at, dev = e
        cur = state["entries"].get(k)
        if cur and not beats(at, dev, cur[1], cur[2]):
            continue
        state["entries"][k] = [v, at, dev]
        changed = True
    return changed


def tidy(state: dict, now_ms: float) -> None:
    cutoff = utc_day(now_ms - KEEP_DAYS * 864e5)
    for k in [k for k in state["entries"] if older_than(k, cutoff)]:
        del state["entries"][k]


# ---------- relay ----------
def _request(house: dict, url: str, data: bytes | None = None) -> bytes:
    req = urllib.request.Request(url, data=data, method="POST" if data is not None else "GET")
    if house.get("k"):
        req.add_header("Authorization", f"Bearer {house['k']}")
    if data is not None:
        req.add_header("Content-Type", "text/plain; charset=utf-8")
    with urllib.request.urlopen(req, timeout=30) as res:
        return res.read()


def poll_lines(house: dict, since) -> list[dict]:
    body = _request(house, f"{house['s']}/{house['t']}/json?poll=1&since={since}").decode("utf-8", "replace")
    out = []
    for row in body.split("\n"):
        try:
            msg = json.loads(row)
        except ValueError:
            continue
        if not isinstance(msg, dict) or msg.get("event") != "message" or not isinstance(msg.get("message"), str):
            continue
        for part in msg["message"].split("\n"):
            out.append({"id": msg.get("id"), "time": msg.get("time"), "line": part})
    return out


def announce(state: dict, force: bool) -> None:
    mine = digest_of(state["entries"], time.time() * 1000)
    if not force and mine == state.get("announced") and time.time() - state.get("announcedAt", 0) < ANNOUNCE_EVERY_S:
        return
    line = WIRE + json.dumps({"d": state["dev"], "g": mine, "s": []}, separators=(",", ":"))
    query = urllib.parse.urlencode({"title": "Kitchen computer checked in", "tags": "plate_with_cutlery", "priority": "1"})
    _request(state["house"], f"{state['house']['s']}/{state['house']['t']}?{query}",
             f"The kitchen computer is reading the notes.\n\n{line}".encode("utf-8"))
    state["announced"], state["announcedAt"] = mine, time.time()


def refresh(state: dict, force: bool) -> bool:
    """Reads what the phones sent and says what this computer holds."""
    cursor = state.get("cursor") or 0
    rows = poll_lines(state["house"], cursor - 1 if cursor else "all")
    seen = set(state.get("seen", []))
    now = datetime.now(timezone.utc)
    changed = False
    for row in rows:
        if not row["line"].startswith(WIRE):
            continue
        key = f"{row['id']}:{len(row['line'])}"
        if key in seen:
            continue
        seen.add(key)
        changed = receive(state, row["line"], now) or changed
        if isinstance(row["time"], int) and row["time"] > cursor:
            cursor = state["cursor"] = row["time"]
    state["seen"] = sorted(seen)[-300:]
    state["heardAt"] = time.time()
    tidy(state, time.time() * 1000)
    announce(state, force)
    return changed


# ---------- state file ----------
def load_state() -> dict | None:
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def save_state(state: dict | None) -> None:
    if state is None:
        STATE_PATH.unlink(missing_ok=True)
        return
    STATE_PATH.parent.mkdir(exist_ok=True)
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def notes(state: dict) -> dict[str, str]:
    return {k[5:]: e[0] for k, e in sorted(state["entries"].items())
            if k.startswith("note/") and isinstance(e[0], str) and e[0]}


def recipe_names() -> dict[str, str]:
    try:
        data = json.loads(RECIPES_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    rows = data if isinstance(data, list) else data.get("recipes", [])
    return {r["slug"]: r.get("displayName") or r.get("name") or r["slug"] for r in rows if "slug" in r}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Read the recipe notes written in the phone app.")
    ap.add_argument("--link", action="store_true", help="paste the household code from the phone app")
    ap.add_argument("--unlink", action="store_true", help="forget the household code")
    ap.add_argument("--wait", type=int, default=0, metavar="SECONDS", help="ask the phones again and wait this long for answers")
    ap.add_argument("--json", action="store_true", help="print slug -> note as JSON")
    args = ap.parse_args(argv)
    # A note may hold letters the Windows console's code page cannot show.
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    if args.unlink:
        save_state(None)
        print("[OK] Forgot the household code.")
        return 0
    if args.link:
        house = house_from_code(input("Household code (phone app, Settings): "))
        if not house:
            print("[X] That is not a household code.")
            return 1
        save_state({"house": house, "dev": f"show-pc-{secrets.token_hex(4)}", "cursor": 0, "entries": {}, "seen": []})
        print(f"[OK] Linked. Saved in {STATE_PATH.relative_to(ROOT)} (git ignores it).")
        args.wait = args.wait or 60

    state = load_state()
    if not state:
        print("[!] Not linked yet: run  python scripts/house_notes.py --link")
        return 1

    try:
        refresh(state, force=args.wait > 0)
        end = time.time() + args.wait
        while time.time() < end:
            if not args.json:
                print(f"... waiting for the phones ({int(end - time.time())}s left; open the app on one to hurry it)", flush=True)
            time.sleep(min(10, max(0, end - time.time())))
            refresh(state, force=False)
    except OSError as e:
        print(f"[!] Could not reach the relay ({e}). Showing what was heard before.", file=sys.stderr)
    finally:
        save_state(state)

    found = notes(state)
    if args.json:
        print(json.dumps(found, ensure_ascii=False, indent=1))
        return 0
    names = recipe_names()
    if not found:
        print("No notes yet.")
    for slug, note in sorted(found.items(), key=lambda kv: names.get(kv[0], kv[0]).lower()):
        print(f"- {names.get(slug, slug)} ({slug}): {note}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
