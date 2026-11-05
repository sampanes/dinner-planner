"""Add HelloFresh recipes to data/source/recipes.json.

    python scripts/import_hellofresh.py 3 7 12          # card numbers from the last find_similar.py run
    python scripts/import_hellofresh.py --from data/handoff/next-hellofresh-recipes.md 3 7 12
    python scripts/import_hellofresh.py https://www.hellofresh.com/recipes/<slug>-<id>
    python scripts/import_hellofresh.py <24-hex id> --servings 2

Card numbers resolve against data/cache/hellofresh/candidates.json when
find_similar.py has run on this machine, else against the committed handoff
data/handoff/next-hellofresh-recipes.md; --from names either file outright.
Each recipe lands unrated (0/0 stars), scaled to --servings (default 4, the
vault's convention; HelloFresh pages are written for 2), with the photo in
the uniform 1200x800 crop and the steps in the bare-number bullet layout the
build parses. Pages are fetched on demand, so a fresh clone needs no cache.
Names already in the vault are skipped. Afterwards:

    python scripts/build_runtime_data.py
    python -m unittest discover -s tests
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hellofresh as hf  # noqa: E402
from reformat_json import write_recipes  # noqa: E402

SOURCE_PATH = hf.ROOT / "data" / "source" / "recipes.json"
CANDIDATES_PATH = hf.CACHE_DIR / "candidates.json"

# "| 7 | Name | ... | [page](https://www.hellofresh.com/recipes/slug-<id>) |": the card number, the name, the last link.
HANDOFF_ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*(.*?)\s*\|.*\]\((https?://[^)\s]+)\)")


def parse_handoff(text: str) -> list[dict]:
    """Candidates from the markdown table find_similar.py writes (card number, name and HelloFresh url per row)."""
    candidates = []
    for line in text.splitlines():
        row = HANDOFF_ROW.match(line.strip())
        match = hf.RECIPE_ID.search(row.group(3)) if row else None
        if row and match:
            candidates.append({"n": int(row.group(1)), "name": row.group(2), "url": row.group(3), "sitemapId": match.group(1), "finalId": match.group(1), "lastmod": ""})
    return candidates


def load_candidates(path: Path | None) -> tuple[list[dict], Path | None]:
    """(candidates, the file they came from): --from, else this machine's last ranking, else the committed handoff."""
    if path is None:
        path = next((candidate for candidate in (CANDIDATES_PATH, hf.HANDOFF_PATH) if candidate.exists()), None)
        if path is None:
            return [], None
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() == ".json":
        return json.loads(text).get("candidates", []), path
    return parse_handoff(text), path


def resolve(selector: str, candidates: list[dict], source: Path | None = None) -> dict:
    """A sitemap-style entry {"url", "id", "slug", "lastmod"} for a card number, id or url."""
    selector = selector.strip().lstrip("#")
    if selector.isdigit():
        for candidate in candidates:
            if candidate.get("n") == int(selector):
                return {"url": candidate["url"], "id": candidate["sitemapId"], "slug": candidate["name"], "lastmod": candidate.get("lastmod", "")}
        raise SystemExit(f"ERROR: no card #{selector} in {source or 'any ranking'} (run find_similar.py first)")
    match = hf.RECIPE_ID.search(selector)
    if not match:
        raise SystemExit(f"ERROR: {selector!r} is not a card number, a HelloFresh id or a recipe url")
    recipe_id = match.group(1)
    for candidate in candidates:
        if recipe_id in (candidate.get("sitemapId"), candidate.get("finalId")):
            return {"url": candidate["url"], "id": candidate["sitemapId"], "slug": candidate["name"], "lastmod": candidate.get("lastmod", "")}
    url = selector if selector.startswith("http") else f"https://www.hellofresh.com/recipes/{recipe_id}"
    return {"url": url, "id": recipe_id, "slug": "", "lastmod": ""}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("selectors", nargs="+", help="card numbers, HelloFresh ids or recipe urls")
    parser.add_argument("--from", dest="source", type=Path, default=None, help="the ranking the card numbers refer to (candidates.json or the handoff .md)")
    parser.add_argument("--servings", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true", help="print the converted recipes, write nothing")
    args = parser.parse_args(argv)

    candidates, source = load_candidates(args.source)
    if source is not None:
        print(f"cards from {source.relative_to(hf.ROOT).as_posix() if source.is_relative_to(hf.ROOT) else source} ({len(candidates)} candidates)")
    vault = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    names = {recipe["name"].lower() for recipe in vault}
    next_id = max((int(recipe.get("id", 0)) for recipe in vault), default=0) + 1

    added = []
    for selector in args.selectors:
        entry = resolve(selector, candidates, source)
        recipe = hf.fetch_recipe(entry)
        if not recipe:
            print(f"skip {selector}: no Recipe block at {entry['url']}")
            continue
        converted = hf.to_source_recipe(recipe, next_id, args.servings)
        if converted["name"].lower() in names:
            print(f"skip {selector}: '{converted['name']}' is already in the vault")
            continue
        if not converted["ingredients"] or not converted["instructions"]:
            print(f"skip {selector}: '{converted['name']}' has no ingredients or steps")
            continue
        names.add(converted["name"].lower())
        next_id += 1
        added.append(converted)
        print(f"add  #{converted['id']:<3} {converted['name']}  ({len(converted['ingredients'])} ingredients, from {entry['url']})")

    if args.dry_run:
        print(json.dumps(added, indent=2))
        return 0
    if not added:
        print("Nothing added.")
        return 1
    write_recipes(vault + added, SOURCE_PATH)
    print(f"Wrote {len(added)} recipe(s) to {SOURCE_PATH.relative_to(hf.ROOT)}. Next: python scripts/build_runtime_data.py && python -m unittest discover -s tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
