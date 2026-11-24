"""The recipe notes written in the phone app, read at this computer.

The phones keep the household's plan, and the notes on recipes ("add parmesan
as a step", or "garlic salt goes in here" on one step), in a private relay
topic that only the household code opens. This script joins that topic as a
listener, the way a linked kitchen screen does (house.js): it folds in what
the phones send and tells them what it holds. A phone that hears it is missing
something sends it, the next time that phone syncs (every 20 seconds while the
app is open).

A note waits on the phones until the recipe is fixed here. The loop:

    1. python scripts/house_notes.py --wait 60     read the notes (open the app on a phone to hurry it)
    2. work each note into data/source/recipes.json, keeping the recipe's
       number of card steps (the step photos are matched by that count)
    3. python scripts/build_runtime_data.py, the tests, commit, push
    4. python scripts/house_notes.py --done <slug or key>

--done is the one thing this script writes: it clears the note, the same way a
phone deleting it would, so both phones drop it. Nothing else is ever written.

The code and what was heard are kept in private/house.json, which git ignores.

    python scripts/house_notes.py --link       paste the household code (phone app: Settings)
    python scripts/house_notes.py              print the notes, each with the step it is on
    python scripts/house_notes.py --wait 90    ask the phones again and wait for answers
    python scripts/house_notes.py --json       the notes as a JSON list
    python scripts/house_notes.py --done SLUG  clear every note on that recipe (or pass one note's key)

Recipes asked for from a phone ride along. Sharing a recipe's page into the
phone app keeps its link as ask/<id>; this script lists them under the notes,
and once the recipe is in data/source/recipes.json, --done ask/<id> clears it
from both phones.
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
RESEND_DAYS = 14
SEND_AT_ONCE = 20
ISO =re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$")
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
    """Says what this computer holds, and sends again the notes it cleared lately."""
    mine = digest_of(state["entries"], time.time() * 1000)
    if not force and mine == state.get("announced") and time.time() - state.get("announcedAt", 0) < ANNOUNCE_EVERY_S:
        return
    own = own_writes(state, datetime.now(timezone.utc))
    query = urllib.parse.urlencode({"title": "Kitchen computer checked in", "tags": "plate_with_cutlery", "priority": "1"})
    # A few at a time: the relay caps a message's size.
    for start in range(0, max(len(own), 1), SEND_AT_ONCE):
        line = WIRE + json.dumps({"d": state["dev"], "g": mine, "s": own[start:start + SEND_AT_ONCE]}, separators=(",", ":"))
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
    """The notes on whole recipes, slug -> note."""
    return {k[5:]: e[0] for k, e in sorted(state["entries"].items())
            if k.startswith("note/") and k.count("/") == 1 and isinstance(e[0], str) and e[0]}


def step_id(step_text: str) -> str:
    """A short, stable name for a step, from its text (plan.dart stepId: FNV-1a over UTF-8)."""
    h = 0x811C9DC5
    for b in step_text.encode("utf-8"):
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    return f"{h:08x}"


def load_recipes() -> dict[str, dict]:
    try:
        data = json.loads(RECIPES_PATH.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    rows = data if isinstance(data, list) else data.get("recipes", [])
    return {r["slug"]: r for r in rows if isinstance(r, dict) and "slug" in r}


def note_rows(state: dict, recipes: dict[str, dict]) -> list[dict]:
    """Every note, with the step it is on looked up in the recipes as they read today.

    A note on one step is kept under note/<slug>/<step id>; its value is how the
    step started, a line break, then the note (plan.dart Plan.notes). `step` is
    the step's number on the kitchen page; it is None for a note on the whole
    recipe, and also when the step has been rewritten since (`loose`).
    """
    rows = []
    for key, entry in state["entries"].items():
        value = entry[0]
        parts = key.split("/")
        if parts[0] != "note" or len(parts) not in (2, 3) or not isinstance(value, str) or not value:
            continue
        slug = parts[1]
        recipe = recipes.get(slug, {})
        row = {"key": key, "slug": slug, "name": recipe.get("displayName") or recipe.get("name") or slug,
               "note": value, "step": None, "of": None, "cardStep": None, "stepText": None, "anchor": None,
               "loose": False, "at": entry[1]}
        if len(parts) == 3:
            cut = value.find("\n")
            row["note"] = (value if cut < 0 else value[cut + 1:]).strip()
            row["anchor"] = value[:cut] if cut > 0 else None
            if not row["note"]:
                continue
            steps = recipe.get("steps") or []
            at = next((i for i, s in enumerate(steps) if step_id(s.get("displayText", "")) == parts[2]), None)
            if at is None:
                row["loose"] = True
            else:
                row.update(step=at + 1, of=len(steps), cardStep=steps[at].get("sourceStep"), stepText=steps[at].get("displayText"))
        rows.append(row)
    rows.sort(key=lambda r: (r["name"].lower(), r["slug"], r["step"] is not None or r["loose"], r["loose"], r["step"] or 0, r["at"]))
    return rows


def asked_for(state: dict) -> list[dict]:
    """The recipes asked for from a phone and not yet added, oldest first."""
    rows = [{"key": k, "link": e[0], "at": e[1]} for k, e in state["entries"].items()
            if k.startswith("ask/") and k.count("/") == 1 and isinstance(e[0], str) and e[0]]
    return sorted(rows, key=lambda r: r["at"])


def describe(row: dict) -> str:
    """One note as a line for a person (or an agent) about to fix the recipe."""
    if row["step"] is not None:
        where = f"step {row['step']} of {row['of']} (card step {row['cardStep']}): \"{row['stepText']}\""
    elif row["loose"]:
        where = "a step that has changed since" + (f", which began \"{row['anchor']}\"" if row["anchor"] else "")
    else:
        where = "the whole recipe"
    return f"  - {where}\n      NOTE: {row['note']}\n      key:  {row['key']}"


def mark_done(state: dict, targets: list[str], now: datetime) -> list[str]:
    """Clears notes that are now part of the recipe; returns the keys cleared.

    A target is a recipe's slug (all of its notes) or one note's key. The
    clearing is written like any phone's write, dated just after the note it
    replaces, so every phone drops the note when it next syncs.
    """
    cleared = []
    for key, entry in sorted(state["entries"].items()):
        parts = key.split("/")
        if entry[0] is None:
            continue
        if parts[0] == "ask" and len(parts) == 2:
            # A recipe that was asked for is cleared by its own key only.
            if key not in targets:
                continue
        elif parts[0] != "note" or len(parts) not in (2, 3):
            continue
        elif key not in targets and parts[1] not in targets:
            continue
        after = datetime.strptime(entry[1], "%Y-%m-%dT%H:%M:%S.%f%z") + timedelta(milliseconds=1)
        state["entries"][key] = [None, stamp(max(now, after)), state["dev"]]
        cleared.append(key)
    return cleared


def own_writes(state: dict, now: datetime) -> list[list]:
    """What this computer wrote lately, sent again with each check-in until the phones have it."""
    cutoff = stamp(now - timedelta(days=RESEND_DAYS))
    return [[k, *e] for k, e in sorted(state["entries"].items()) if e[2] == state["dev"] and e[1] >= cutoff]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Read the recipe notes written in the phone app.")
    ap.add_argument("--link", action="store_true", help="paste the household code from the phone app")
    ap.add_argument("--unlink", action="store_true", help="forget the household code")
    ap.add_argument("--wait", type=int, default=0, metavar="SECONDS", help="ask the phones again and wait this long for answers")
    ap.add_argument("--json", action="store_true", help="print the notes as a JSON list, one object per note")
    ap.add_argument("--done", nargs="+", metavar="SLUG_OR_KEY",
                    help="clear notes that are now in the recipe: a recipe's slug (all its notes) or one note's key")
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

    cleared = []
    try:
        refresh(state, force=args.wait > 0)
        if args.done:
            # After hearing the phones, so a note changed since it was read is cleared as it stands now.
            cleared = mark_done(state, args.done, datetime.now(timezone.utc))
            if cleared:
                announce(state, force=True)
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

    rows = note_rows(state, load_recipes())
    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=1))
        return 0
    if args.done:
        for key in cleared:
            print(f"[OK] Cleared {key}. The phones drop it when they next sync.")
        if not cleared:
            print("[!] Nothing to clear under: " + ", ".join(args.done))
    asks = asked_for(state)
    if not rows:
        print("No notes waiting.")
    slug = None
    for row in rows:
        if row["slug"] != slug:
            slug = row["slug"]
            print(f"\n{row['name']}  ({slug})")
        print(describe(row))
    if rows:
        print("\nOnce a note is in the recipe:  python scripts/house_notes.py --done <slug or key>")
    if asks:
        print("\nRecipes asked for from a phone:")
        for ask in asks:
            print(f"  - {ask['link']}\n      key:  {ask['key']}")
        print("\nOnce one is in data/source/recipes.json:  python scripts/house_notes.py --done ask/<id>")
    return 0


if __name__ == "__main__":
    sys.exit(main())
