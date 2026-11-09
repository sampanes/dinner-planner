"""Fold changes made in kitchen mode (ratings, "we cooked this", the week's plan) into the repo.

    python scripts/pull_changes.py                 # read ntfy.sh, apply, rebuild
    python scripts/pull_changes.py --from FILE     # read saved ntfy JSON lines instead
    python scripts/pull_changes.py --dry-run       # say what would change, write nothing

Devices send each change as a push message to the ntfy.sh topic named in
data/source/kitchen.json (see sync.js). The message ends with one machine line,
"dp1 {json}". This script reads every cached message (ntfy.sh keeps them about
12 hours; devices re-send anything not yet committed), checks it, and writes:

  ratings  -> pinkStar / blueStar in data/source/recipes.json
  cooked   -> data/source/log.json "cooked"
  plan     -> data/source/log.json "plan"

Applying the same message twice changes nothing, and an older message never
overrides a newer one, so it is safe to run as often as you like
(.github/workflows/sync.yml runs it every hour).
"""

import argparse
import datetime
import json
import re
import sys
import urllib.request
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_runtime_data as build  # noqa: E402
from recipe_text import normalize_text, slugify  # noqa: E402
from reformat_json import write_recipes  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "data" / "source" / "kitchen.json"
LOG_PATH = ROOT / "data" / "source" / "log.json"
NTFY = "https://ntfy.sh"
MARK = "dp1 "
ISO = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z$")
STAR_KEY = {"pink": "pinkStar", "blue": "blueStar"}
# A message dated past now + CLOCK_SLACK is refused: newest-wins would let it
# block every real rating after it (a forged date, or a device with a wrong clock).
CLOCK_SLACK = datetime.timedelta(minutes=10)
# Changes applied per run; the rest wait for the next run. Stops a flood of
# messages from turning into one enormous commit.
MAX_CHANGES = 50


def fetch_lines(topic: str) -> list[str]:
    url = f"{NTFY}/{topic}/json?poll=1&since=all"
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "dinner-planner-sync"}), timeout=30) as res:
        return res.read().decode("utf-8").splitlines()


def parse_events(lines: list[str]) -> list[dict]:
    """The dp1 payloads in ntfy's JSON-lines poll output, oldest first."""
    events = []
    for line in lines:
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        if msg.get("event") != "message":
            continue
        for text_line in (msg.get("message") or "").splitlines():
            if text_line.startswith(MARK):
                try:
                    event = json.loads(text_line[len(MARK):])
                except ValueError:
                    continue
                if isinstance(event, dict):
                    events.append(event)
    return sorted(events, key=lambda e: str(e.get("at", "")))


def problem(event: dict, slugs: set[str], latest: str) -> str:
    """Why an event cannot be applied, or "" when it is fine. `latest` is the newest allowed "at"."""
    if not isinstance(event.get("id"), str) or not event["id"]:
        return "no id"
    if not isinstance(event.get("at"), str) or not ISO.match(event["at"]):
        return "bad time"
    if event["at"] > latest:
        return "dated in the future"
    kind = event.get("k")
    if kind == "rate":
        if event.get("slug") not in slugs:
            return "unknown recipe"
        if event.get("who") not in STAR_KEY:
            return "unknown person"
        if not isinstance(event.get("stars"), int) or not 0 <= event["stars"] <= 5:
            return "bad stars"
        return ""
    if kind == "cooked":
        return "" if event.get("slug") in slugs else "unknown recipe"
    if kind == "plan":
        plan = event.get("slugs")
        if not isinstance(plan, list) or not 1 <= len(plan) <= 10:
            return "bad plan"
        return "" if all(s in slugs for s in plan) else "unknown recipe in plan"
    return "unknown kind"


def apply_events(events: list[dict], recipes: list[dict], log: dict, now: datetime.datetime | None = None) -> list[str]:
    """Apply events in place; return one line per real change, then one per kind of skip."""
    by_slug = {slugify(normalize_text(r.get("name", ""))): r for r in recipes}
    names = {slug: normalize_text(r.get("name", "")) for slug, r in by_slug.items()}
    now = now or datetime.datetime.now(datetime.timezone.utc)
    latest = (now + CLOCK_SLACK).strftime("%Y-%m-%dT%H:%M:%SZ")
    changes = []
    skipped = Counter()
    applied = 0
    for event in events:
        why = problem(event, set(by_slug), latest)
        if not why and applied >= MAX_CHANGES:
            why = f"over the {MAX_CHANGES}-per-run limit (next run)"
        if why:
            skipped[why] += 1
            continue
        kind = event["k"]
        if kind == "rate":
            rated = log["rated"].setdefault(event["slug"], {})
            if rated.get(event["who"], "") >= event["at"]:
                continue
            rated[event["who"]] = event["at"]
            applied += 1
            recipe = by_slug[event["slug"]]
            key = STAR_KEY[event["who"]]
            if recipe.get(key) != event["stars"]:
                changes.append(f"{event['who']} rated {names[event['slug']]}: {recipe.get(key)} -> {event['stars']}")
                recipe[key] = event["stars"]
        elif kind == "cooked":
            # One dinner per recipe per day: also what stops a flood of fresh ids.
            if any(c["id"] == event["id"] or (c["slug"] == event["slug"] and c["at"][:10] == event["at"][:10]) for c in log["cooked"]):
                continue
            applied += 1
            log["cooked"].append({"id": event["id"], "slug": event["slug"], "at": event["at"]})
            log["cooked"].sort(key=lambda c: c["at"])
            changes.append(f"cooked {names[event['slug']]} ({event['at'][:10]})")
        elif kind == "plan":
            current = log.get("plan")
            if current and current.get("at", "") >= event["at"]:
                continue
            log["plan"] = {"id": event["id"], "slugs": event["slugs"], "at": event["at"]}
            applied += 1
            changes.append(f"plan: {', '.join(names[s] for s in event['slugs'])}")
    changes.extend(f"skipped {n}: {why}" for why, n in skipped.items())
    return changes


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--from", dest="source", help="ntfy JSON-lines file to read instead of ntfy.sh")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    config = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    lines = Path(args.source).read_text(encoding="utf-8").splitlines() if args.source else fetch_lines(config["ntfyTopic"])
    events = parse_events(lines)

    recipes = json.loads(build.SOURCE_PATH.read_text(encoding="utf-8"))
    log = json.loads(LOG_PATH.read_text(encoding="utf-8"))
    log.setdefault("plan", None)
    log.setdefault("cooked", [])
    log.setdefault("rated", {})
    before = json.dumps(log, sort_keys=True)
    changes = apply_events(events, recipes, log)

    print(f"{len(events)} message(s), {len(changes)} change(s).")
    for line in changes:
        print(f"  {line}")
    if args.dry_run or json.dumps(log, sort_keys=True) == before:
        return 0

    write_recipes(recipes, build.SOURCE_PATH)
    LOG_PATH.write_text(json.dumps(log, indent=2) + "\n", encoding="utf-8", newline="\n")
    return build.main([])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
