"""Rewrite data/source/recipes.json as plain ASCII.

    python scripts/normalize_source.py          # rewrite in place
    python scripts/normalize_source.py --check  # exit 1 if the source has non-ASCII

Bullets pasted from HelloFresh cards become "- " lines, fractions become
"1/2", degree signs become "degrees", curly quotes and dashes become their
plain forms, accents are dropped, and every photo url on a known host is
rewritten to the one 1200x800 crop (hellofresh.uniform_image_url). The file
layout written by reformat_json.py is preserved so the diff stays readable.
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hellofresh import uniform_image_url  # noqa: E402
from recipe_text import non_ascii_count, normalize_text  # noqa: E402
from reformat_json import write_recipes  # noqa: E402

SOURCE_PATH = Path(__file__).resolve().parent.parent / "data" / "source" / "recipes.json"


def normalize_instructions(text: str) -> str:
    # A bullet in the middle of a line starts a new line; a bullet at the start
    # of a line becomes a plain "- " bullet.
    text = re.sub(r"[ \t]+\u2022[ \t]+", "\n- ", text)
    text = re.sub(r"(^|\n)[ \t]*\u2022[ \t]*", r"\1- ", text)
    return normalize_text(text)


def normalize_recipe(recipe: dict) -> dict:
    out = dict(recipe)
    out["name"] = normalize_text(recipe.get("name", ""))
    out["image"] = uniform_image_url(recipe.get("image", ""))
    out["instructions"] = normalize_instructions(recipe.get("instructions", ""))
    out["ingredients"] = [
        {**ingredient, "name": normalize_text(ingredient.get("name", "")), "amount": normalize_text(ingredient.get("amount", ""))}
        for ingredient in recipe.get("ingredients", [])
    ]
    return out


def count_non_ascii(recipes: list[dict]) -> int:
    return non_ascii_count(json.dumps(recipes, ensure_ascii=False))


def main(argv: list[str]) -> int:
    recipes = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    before = count_non_ascii(recipes)
    normalized = [normalize_recipe(recipe) for recipe in recipes]
    changed = sum(1 for old, new in zip(recipes, normalized) if old != new)
    if "--check" in argv:
        if before or changed:
            print(f"{before} non-ASCII characters and {changed} un-normalized recipes in {SOURCE_PATH.name}; run python scripts/normalize_source.py")
            return 1
        print(f"{SOURCE_PATH.name} is ASCII and normalized.")
        return 0

    write_recipes(normalized, SOURCE_PATH)
    after = count_non_ascii(normalized)
    print(f"Normalized {len(normalized)} recipes ({changed} changed): {before} non-ASCII characters before, {after} after.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
