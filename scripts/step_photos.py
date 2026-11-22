"""Find the HelloFresh step-by-step photos for each recipe.

    python scripts/step_photos.py            # fill in recipes that have no entry yet
    python scripts/step_photos.py --refresh  # look every recipe up again
    python scripts/step_photos.py --report   # list what matched and what did not, no network

Writes data/source/step_photos.json: {slug: {"page": url, "photos": [url, ...]}}
with one photo url (or "") per HelloFresh step. The photos stay on HelloFresh's
image server; nothing is downloaded into the repo. The build only uses a
recipe's photos when their count matches the recipe's own step count, so a
recipe that was typed in with different steps never shows the wrong picture.

A recipe is matched to its page by the HelloFresh id in its main photo url,
then by an exact name match against the sitemap. Anything still unmatched is
listed with the closest sitemap names; to fix one, put its page url in the
json by hand ({"page": "https://www.hellofresh.com/recipes/...", "photos": []})
and run this again.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hellofresh import CACHE_DIR, IMAGE_HOST, _get, fetch_sitemap  # noqa: E402
from recipe_text import parse_instructions, slugify  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = ROOT / "data" / "source" / "recipes.json"
PHOTOS_PATH = ROOT / "data" / "source" / "step_photos.json"
STEPS_CACHE = CACHE_DIR / "steps"

STEP_TRANSFORM = "c_fill,w_960,h_640,f_auto,q_auto"
PAUSE_SECONDS = 3.0
RECIPE_ID = re.compile(r"[0-9a-f]{24}")


# ---------------------------------------------------------------------------
# Pure helpers (tested offline)


def photo_url(path: str) -> str:
    """A step photo's site path ("/<id>/step-ab12.jpeg") as a sized image url."""
    return f"{IMAGE_HOST}/{STEP_TRANSFORM}/hellofresh_s3/{path.lstrip('/')}" if path else ""


def _find_steps(node: object) -> list | None:
    """The first list under a "steps" key whose items look like recipe steps."""
    if isinstance(node, dict):
        steps = node.get("steps")
        if isinstance(steps, list) and steps and all(isinstance(s, dict) and "images" in s for s in steps):
            return steps
        children = node.values()
    elif isinstance(node, list):
        children = node
    else:
        return None
    for child in children:
        found = _find_steps(child)
        if found is not None:
            return found
    return None


def step_photos_from_html(page: str) -> list[str] | None:
    """One photo url ("" when a step has none) per step, in step order, or None."""
    for match in re.finditer(r"<script[^>]*type=\"application/json\"[^>]*>(.*?)</script>", page, re.S):
        try:
            data = json.loads(match.group(1))
        except json.JSONDecodeError:
            continue
        steps = _find_steps(data)
        if steps is None:
            continue
        steps = sorted(steps, key=lambda s: s.get("index") or 0)
        photos = []
        for step in steps:
            images = step.get("images") or []
            path = images[0].get("path", "") if images and isinstance(images[0], dict) else ""
            photos.append(photo_url(path))
        return photos
    return None


def source_step_count(recipe: dict) -> int:
    steps, _ = parse_instructions(recipe.get("instructions", ""))
    return len(steps)


def candidates_for(recipe: dict, sitemap: list[dict]) -> list[dict]:
    """Sitemap entries for this recipe, best first: by photo id, then exact name."""
    by_id = {entry["id"]: entry for entry in sitemap}
    found = [by_id[i] for i in RECIPE_ID.findall(recipe.get("image", "")) if i in by_id]
    name = recipe.get("name", "")
    # HelloFresh spells "&" either way and keeps "shepherd-s" in some slugs.
    slugs = {slugify(name.replace("&", " ").replace("'", "")), slugify(name.replace("&", " and ").replace("'", "")),
             slugify(name.replace("&", " ")), slugify(name.replace("&", " and "))}
    same_name = [entry for entry in sitemap if entry["slug"] in slugs and entry not in found]
    same_name.sort(key=lambda entry: entry.get("lastmod", ""), reverse=True)
    return found + same_name


def closest_names(name: str, sitemap: list[dict], limit: int = 3) -> list[str]:
    words = set(slugify(name).split("-")) - {"with", "and", "in", "a", "the"}
    scored = []
    for entry in sitemap:
        other = set(entry["slug"].split("-"))
        if words & other:
            scored.append((len(words & other) / len(words | other), entry["url"]))
    scored.sort(reverse=True)
    seen, out = set(), []
    for _, url in scored:
        key = re.sub(r"-[0-9a-f]{24}$", "", url)
        if key not in seen:
            seen.add(key)
            out.append(url)
        if len(out) == limit:
            break
    return out


# ---------------------------------------------------------------------------
# Network


def fetch_step_photos(url: str) -> list[str] | None:
    """The page's step photos, cached under data/cache (gitignored)."""
    STEPS_CACHE.mkdir(parents=True, exist_ok=True)
    key = (RECIPE_ID.findall(url) or [slugify(url)])[-1]
    path = STEPS_CACHE / f"{key}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8")).get("photos")
    time.sleep(PAUSE_SECONDS)
    try:
        page = _get(url).decode("utf-8", errors="replace")
    except RuntimeError as error:
        print(f"  [!] {error}", file=sys.stderr)
        return None
    photos = step_photos_from_html(page)
    path.write_text(json.dumps({"url": url, "photos": photos}, indent=1), encoding="utf-8")
    return photos


# ---------------------------------------------------------------------------


def load_photos() -> dict:
    return json.loads(PHOTOS_PATH.read_text(encoding="utf-8")) if PHOTOS_PATH.exists() else {}


def save_photos(photos: dict) -> None:
    PHOTOS_PATH.write_text(json.dumps(dict(sorted(photos.items())), indent=2) + "\n", encoding="utf-8", newline="\n")


def main(argv: list[str]) -> int:
    refresh = "--refresh" in argv
    report_only = "--report" in argv
    recipes = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    photos = load_photos()
    sitemap = [] if report_only else fetch_sitemap()
    unmatched = []

    for recipe in recipes:
        slug = slugify(recipe.get("name", ""))
        want = source_step_count(recipe)
        entry = photos.get(slug, {})
        if report_only:
            got = len(entry.get("photos", []))
            status = "[OK]" if got and got == want else "[X] "
            print(f"{status} {slug}: {got} photos, {want} steps")
            continue
        if entry.get("photos") and not refresh:
            continue

        pages = [entry["page"]] if entry.get("page") else [c["url"] for c in candidates_for(recipe, sitemap)]
        best = None
        for page in pages:
            found = fetch_step_photos(page)
            if not found:
                continue
            if best is None or (len(found) == want and len(best[1]) != want):
                best = (page, found)
            if len(found) == want:
                break
        if best is None:
            unmatched.append(recipe.get("name", ""))
            continue
        photos[slug] = {"page": best[0], "photos": best[1]}
        note = "" if len(best[1]) == want else f"  [!] {len(best[1])} photos for {want} steps, will not show"
        print(f"[OK] {slug}{note}")
        save_photos(photos)

    if unmatched:
        print("\nNo HelloFresh page found for:")
        for name in unmatched:
            print(f"  {name}")
            for url in closest_names(name, sitemap):
                print(f"      maybe {url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
