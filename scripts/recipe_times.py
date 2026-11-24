"""How long each recipe takes, start to table, in minutes.

    python scripts/recipe_times.py            # fill in recipes that have no time yet
    python scripts/recipe_times.py --refresh  # look every recipe up again
    python scripts/recipe_times.py --report   # list what has a time and what does not, no network

Writes data/source/recipe_times.json: {slug: minutes}. The build copies each
one into the runtime data as "minutes", and the phone app counts back from
when the household eats to say when to start cooking.

The time is the "total time" HelloFresh prints on the recipe's page (the page
named in data/source/step_photos.json). A recipe with no page, or a time that
is wrong for this kitchen, is fixed by typing the minutes into the json by
hand; a number already there is kept unless --refresh is given.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hellofresh import PAGES_DIR, _get, extract_recipe_jsonld  # noqa: E402
from recipe_text import slugify  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = ROOT / "data" / "source" / "recipes.json"
PHOTOS_PATH = ROOT / "data" / "source" / "step_photos.json"
TIMES_PATH = ROOT / "data" / "source" / "recipe_times.json"

PAUSE_SECONDS = 3.0
RECIPE_ID = re.compile(r"[0-9a-f]{24}")
ISO_DURATION = re.compile(r"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:\d+S)?)?$")

# Outside these a "time" is a mistake on the page, not a dinner.
SHORTEST, LONGEST = 5, 240


# ---------------------------------------------------------------------------
# Pure helpers (tested offline)


def minutes_from_iso(text: object) -> int | None:
    """"PT35M" -> 35, "PT1H10M" -> 70; None for anything else or out of range."""
    match = ISO_DURATION.match(text.strip()) if isinstance(text, str) else None
    if not match or not any(match.groups()):
        return None
    days, hours, minutes = (int(part or 0) for part in match.groups())
    total = days * 1440 + hours * 60 + minutes
    return total if SHORTEST <= total <= LONGEST else None


def minutes_from_recipe(recipe: dict | None) -> int | None:
    """The page's total time; where it gives only the parts, their sum."""
    if not isinstance(recipe, dict):
        return None
    total = minutes_from_iso(recipe.get("totalTime"))
    if total is not None:
        return total
    parts = [minutes_from_iso(recipe.get(key)) for key in ("prepTime", "cookTime")]
    known = [part for part in parts if part is not None]
    return sum(known) if known and sum(known) <= LONGEST else None


def valid_times(raw: object) -> dict[str, int]:
    """Only the entries the build can use: a slug and whole minutes in range."""
    if not isinstance(raw, dict):
        return {}
    return {slug: value for slug, value in raw.items()
            if isinstance(slug, str) and isinstance(value, int) and not isinstance(value, bool) and SHORTEST <= value <= LONGEST}


# ---------------------------------------------------------------------------
# Network


def page_recipe(url: str) -> dict | None:
    """The Recipe block of a HelloFresh page, from the page cache when it is there."""
    ids = RECIPE_ID.findall(url)
    path = PAGES_DIR / f"{ids[-1]}.json" if ids else None
    if path is not None and path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8")).get("recipe")
        except json.JSONDecodeError:
            pass
    time.sleep(PAUSE_SECONDS)
    try:
        recipe = extract_recipe_jsonld(_get(url).decode("utf-8", errors="replace"))
    except RuntimeError as error:
        print(f"  [!] {error}", file=sys.stderr)
        return None
    if path is not None:
        PAGES_DIR.mkdir(parents=True, exist_ok=True)
        record = {"sitemapId": ids[-1], "url": url, "lastmod": "", "fetched": time.strftime("%Y-%m-%d"), "finalId": ids[-1], "recipe": recipe}
        path.write_text(json.dumps(record, ensure_ascii=False, indent=1), encoding="utf-8")
    return recipe


# ---------------------------------------------------------------------------


def load_times() -> dict[str, int]:
    return valid_times(json.loads(TIMES_PATH.read_text(encoding="utf-8"))) if TIMES_PATH.exists() else {}


def save_times(times: dict[str, int]) -> None:
    TIMES_PATH.write_text(json.dumps(dict(sorted(times.items())), indent=2) + "\n", encoding="utf-8", newline="\n")


def main(argv: list[str]) -> int:
    refresh = "--refresh" in argv
    report_only = "--report" in argv
    slugs = [slugify(recipe.get("name", "")) for recipe in json.loads(SOURCE_PATH.read_text(encoding="utf-8"))]
    pages = json.loads(PHOTOS_PATH.read_text(encoding="utf-8")) if PHOTOS_PATH.exists() else {}
    times = load_times()
    missing = []

    for slug in slugs:
        if report_only:
            print(f"{'[OK]' if slug in times else '[X] '} {slug}: {times.get(slug, 'no time')}")
            continue
        if slug in times and not refresh:
            continue
        url = pages.get(slug, {}).get("page", "")
        found = minutes_from_recipe(page_recipe(url)) if url else None
        if found is None:
            missing.append(slug)
            continue
        times[slug] = found
        print(f"[OK] {slug}: {found} minutes")
        save_times(times)

    if not report_only:
        # A recipe that was renamed or removed takes its time with it.
        kept = {slug: minutes for slug, minutes in times.items() if slug in slugs}
        if kept != times or not TIMES_PATH.exists():
            save_times(kept)
    if missing:
        print("\nNo time found for (type the minutes into data/source/recipe_times.json):")
        for slug in missing:
            print(f"  {slug}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
