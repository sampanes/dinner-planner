"""Build runtime data, the validation report and the static recipe pages.

    python scripts/build_runtime_data.py          # write everything
    python scripts/build_runtime_data.py --check  # exit 1 if anything on disk is stale

Inputs:  data/source/recipes.json (human edited)
Outputs: data/runtime/*.json, data/reports/validation_report.md, recipes/*.html

The recipe pages carry schema.org Recipe JSON-LD so a recipe can be imported
into Alexa+ (or any recipe app) by sharing its link.
"""

import html
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hellofresh import image_at  # noqa: E402
from recipe_text import (  # noqa: E402
    MAX_SPOKEN_STEP_CHARS,
    ingredient_refs,
    non_ascii_count,
    normalize_text,
    parse_instructions,
    slugify,
    timer_hints,
)
from recipe_tags import haves, haves_catalog, moods, proteins  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = ROOT / "data" / "source" / "recipes.json"
RUNTIME_DIR = ROOT / "data" / "runtime"
REPORTS_DIR = ROOT / "data" / "reports"
PAGES_DIR = ROOT / "recipes"
SITE_BASE = "https://sampanes.github.io/dinner-planner/"
SITE_NAME = "Dinner Planner"


# ---------------------------------------------------------------------------
# Runtime recipes
# ---------------------------------------------------------------------------


def ingredient_text(amount: str, name: str) -> str:
    """"400g spaghetti", "2 zucchini" (not "2 unit zucchini"), "salt, to taste"."""
    amount = re.sub(r"\s*units?$", "", amount.strip(), flags=re.IGNORECASE)
    if not amount or amount.lower() == "to taste":
        return f"{name}, to taste" if amount else name
    return f"{amount} {name}"


def build_runtime_recipe(recipe: dict) -> dict:
    recipe_name = normalize_text(recipe.get("name", ""))
    steps, notes = parse_instructions(recipe.get("instructions", ""))

    ingredients = []
    search_tokens = set()
    for ingredient in recipe.get("ingredients", []):
        display_name = normalize_text(ingredient.get("name", ""))
        canonical_name = display_name.lower()
        amount_text = normalize_text(ingredient.get("amount", ""))
        ingredients.append(
            {
                "id": slugify(display_name) or f"ingredient-{len(ingredients) + 1}",
                "displayName": display_name,
                "canonicalName": canonical_name,
                "aliases": [canonical_name] if canonical_name else [],
                "amountText": amount_text,
                "text": ingredient_text(amount_text, display_name),
            }
        )
        if canonical_name:
            search_tokens.add(canonical_name)

    runtime_steps = []
    for step in steps:
        for part in step["parts"]:
            runtime_steps.append(
                {
                    "index": len(runtime_steps) + 1,
                    "sourceStep": step["sourceStep"],
                    "section": step["section"],
                    "speakShort": part,
                    "displayText": part,
                    "ingredientRefs": ingredient_refs(part, ingredients),
                    "timerHints": timer_hints(part, ingredients),
                }
            )

    search_tokens.update(token for token in slugify(recipe_name).split("-") if token)
    slug = slugify(recipe_name) or f"recipe-{recipe.get('id')}"

    return {
        "id": str(recipe.get("id")),
        "name": recipe_name,
        "displayName": recipe_name,
        "slug": slug,
        "pageUrl": f"{SITE_BASE}recipes/{slug}.html",
        "aliases": [recipe_name.lower()] if recipe_name else [],
        "categories": proteins(recipe_name, ingredients),
        "tags": moods(recipe_name, ingredients),
        "haves": haves(ingredients),
        "ingredients": ingredients,
        "steps": runtime_steps,
        "notes": notes,
        "searchTokens": sorted(search_tokens),
        "image": (recipe.get("image") or "").strip(),
        "sourceStars": {
            "pink": recipe.get("pinkStar"),
            "blue": recipe.get("blueStar"),
        },
    }


def build_indexes(runtime_recipes: list[dict]) -> tuple[dict, dict]:
    alias_index = {}
    ingredient_index = {}
    for recipe in runtime_recipes:
        for alias in recipe["aliases"]:
            alias_index.setdefault(alias, []).append(recipe["id"])
        for ingredient in recipe["ingredients"]:
            ingredient_index.setdefault(ingredient["canonicalName"], []).append(recipe["id"])
    return alias_index, ingredient_index


# ---------------------------------------------------------------------------
# Validation report
# ---------------------------------------------------------------------------


def source_non_ascii(source_recipes: list[dict]) -> list[str]:
    findings = []
    for recipe in source_recipes:
        fields = {"name": recipe.get("name", ""), "instructions": recipe.get("instructions", "")}
        for ingredient in recipe.get("ingredients", []):
            fields[f"ingredient '{ingredient.get('name', '')}'"] = ingredient.get("name", "") + ingredient.get("amount", "")
        for field, value in fields.items():
            count = non_ascii_count(value)
            if count:
                findings.append(f"- recipe {recipe.get('id')} ({recipe.get('name', '')}): {count} non-ASCII in {field}")
    return findings


def build_validation_report(source_recipes: list[dict], runtime_recipes: list[dict], alias_index: dict) -> str:
    duplicate_aliases = {alias: ids for alias, ids in alias_index.items() if len(ids) > 1}
    long_steps = []
    numbering_gaps = []
    no_image = []
    no_steps = []
    for recipe in runtime_recipes:
        label = f"{recipe['id']} ({recipe['name']})"
        if not recipe["steps"]:
            no_steps.append(f"- {label}")
        if not recipe["image"]:
            no_image.append(f"- {label}")
        for step in recipe["steps"]:
            length = len(step["speakShort"])
            if length > MAX_SPOKEN_STEP_CHARS:
                long_steps.append(f"- {label}: step {step['index']} (source step {step['sourceStep']}) is {length} chars")
        source_numbers = sorted({step["sourceStep"] for step in recipe["steps"]})
        if source_numbers and source_numbers != list(range(1, len(source_numbers) + 1)):
            numbering_gaps.append(f"- {label}: source step numbers {source_numbers}")
    non_ascii = source_non_ascii(source_recipes)

    lines = [
        "# Validation Report",
        "",
        "Generated by `scripts/build_runtime_data.py`. Do not edit by hand.",
        "",
        f"- Runtime recipes: {len(runtime_recipes)}",
        f"- Runtime steps: {sum(len(r['steps']) for r in runtime_recipes)}",
        f"- Duplicate recipe aliases: {len(duplicate_aliases)}",
        f"- Steps over {MAX_SPOKEN_STEP_CHARS} chars (too long for one spoken turn): {len(long_steps)}",
        f"- Recipes with step numbering gaps: {len(numbering_gaps)}",
        f"- Recipes without an image: {len(no_image)}",
        f"- Recipes without steps: {len(no_steps)}",
        f"- Source fields with non-ASCII characters: {len(non_ascii)}",
        "",
    ]

    def section(title: str, items: list[str], ok_text: str) -> None:
        lines.append(f"## {title}")
        lines.append("")
        lines.extend(items if items else [ok_text])
        lines.append("")

    section(
        "Duplicate aliases",
        [f"- `{alias}` -> {', '.join(ids)}" for alias, ids in sorted(duplicate_aliases.items())],
        "None.",
    )
    section(
        "Long steps",
        long_steps,
        "None. Every step fits one spoken turn.",
    )
    section("Step numbering gaps", numbering_gaps, "None.")
    section("Recipes without steps", no_steps, "None.")
    section("Recipes without an image", no_image, "None.")
    section(
        "Non-ASCII in source",
        non_ascii,
        "None. Run `python scripts/normalize_source.py` if this list ever fills up.",
    )
    lines.append("## Notes")
    lines.append("")
    lines.append("- A long step is a warning for the author: split it in `data/source/recipes.json`.")
    lines.append("- `ingredientRefs` and `timerHints` on runtime steps are heuristics, not ground truth.")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Static recipe pages
# ---------------------------------------------------------------------------

RECIPE_CSS = """\
:root {
  --ink: #1f2937;
  --muted: #6b7280;
  --accent: #d97706;
  --paper: #fffdf8;
  --card: #ffffff;
  --line: #e5e7eb;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--paper);
  color: var(--ink);
  font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  font-size: 18px;
  line-height: 1.55;
}
main { max-width: 760px; margin: 0 auto; padding: 20px 20px 60px; }
nav.top { display: flex; flex-wrap: wrap; gap: 16px; font-size: 15px; margin-bottom: 18px; }
nav.top a { color: var(--accent); text-decoration: none; }
nav.top a:hover { text-decoration: underline; }
h1 { font-size: 2rem; line-height: 1.2; margin: 0 0 6px; }
h2 { font-size: 1.3rem; margin: 32px 0 10px; padding-bottom: 6px; border-bottom: 2px solid var(--line); }
h3 { font-size: 1.05rem; margin: 0 0 4px; color: var(--accent); }
p.meta { color: var(--muted); margin: 0 0 14px; font-size: 15px; }
img.hero { width: 100%; max-height: 360px; object-fit: cover; border-radius: 14px; display: block; }
ul.ingredients { list-style: none; padding: 0; margin: 0; }
ul.ingredients li { display: flex; gap: 12px; padding: 7px 0; border-bottom: 1px solid var(--line); }
ul.ingredients li:last-child { border-bottom: 0; }
ul.ingredients .amount { min-width: 120px; color: var(--muted); }
ol.steps { padding-left: 1.4em; margin: 0; }
ol.steps > li { margin: 0 0 18px; padding-left: 4px; }
ol.steps p { margin: 0 0 8px; }
section.notes p { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px 14px; }
footer { margin-top: 40px; color: var(--muted); font-size: 13px; }
ul.recipe-index { list-style: none; padding: 0; margin: 0; display: grid; gap: 10px; }
ul.recipe-index li { display: flex; align-items: center; gap: 14px; background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 8px 12px; }
ul.recipe-index img { width: 64px; height: 64px; object-fit: cover; border-radius: 8px; flex: none; }
ul.recipe-index a { color: var(--ink); text-decoration: none; font-weight: 600; }
ul.recipe-index a:hover { color: var(--accent); }
ul.recipe-index .count { margin-left: auto; color: var(--muted); font-size: 14px; white-space: nowrap; }
@media (max-width: 480px) {
  body { font-size: 17px; }
  ul.ingredients .amount { min-width: 90px; }
}
"""


def esc(value: object) -> str:
    return html.escape(str(value), quote=True)


def json_ld(recipe: dict) -> str:
    source_steps = {}
    for step in recipe["steps"]:
        source_steps.setdefault(step["sourceStep"], {"section": step["section"], "parts": []})
        source_steps[step["sourceStep"]]["parts"].append(step["speakShort"])

    use_sections = any(group["section"] or len(group["parts"]) > 1 for group in source_steps.values())
    instructions = []
    for number, group in sorted(source_steps.items()):
        steps = [{"@type": "HowToStep", "text": part} for part in group["parts"]]
        if use_sections:
            instructions.append(
                {
                    "@type": "HowToSection",
                    "name": group["section"] or f"Step {number}",
                    "itemListElement": steps,
                }
            )
        else:
            instructions.extend(steps)

    data = {
        "@context": "https://schema.org",
        "@type": "Recipe",
        "name": recipe["name"],
        "url": recipe["pageUrl"],
        "description": description(recipe),
        "author": {"@type": "Organization", "name": SITE_NAME},
        "recipeIngredient": [ingredient["text"] for ingredient in recipe["ingredients"]],
        "recipeInstructions": instructions,
        "keywords": ", ".join(recipe["searchTokens"]),
    }
    if recipe["image"]:
        data["image"] = [recipe["image"]]
    if recipe["notes"]:
        data["comment"] = [{"@type": "Comment", "text": note} for note in recipe["notes"]]
    # "</" cannot appear inside a script element.
    return json.dumps(data, indent=2, ensure_ascii=True).replace("</", "<\\/")


def description(recipe: dict) -> str:
    source_steps = len({step["sourceStep"] for step in recipe["steps"]})
    return f"{recipe['name']}: {len(recipe['ingredients'])} ingredients, {source_steps} steps."


def render_recipe_page(recipe: dict) -> str:
    stars = recipe["sourceStars"]
    source_steps = []
    for step in recipe["steps"]:
        if not source_steps or source_steps[-1]["number"] != step["sourceStep"]:
            source_steps.append({"number": step["sourceStep"], "section": step["section"], "parts": []})
        source_steps[-1]["parts"].append(step["displayText"])

    ingredient_items = "\n".join(
        f'      <li><span class="amount">{esc(i["amountText"])}</span><span>{esc(i["displayName"])}</span></li>'
        for i in recipe["ingredients"]
    )
    step_items = []
    for group in source_steps:
        heading = f"<h3>{esc(group['section'])}</h3>" if group["section"] else ""
        paragraphs = "".join(f"<p>{esc(part)}</p>" for part in group["parts"])
        step_items.append(f"      <li>{heading}{paragraphs}</li>")
    notes_html = ""
    if recipe["notes"]:
        notes_html = "\n    <section class=\"notes\">\n      <h2>Notes</h2>\n" + "".join(
            f"      <p>{esc(note)}</p>\n" for note in recipe["notes"]
        ) + "    </section>"
    hero = f'\n      <img class="hero" src="{esc(recipe["image"])}" alt="{esc(recipe["name"])}">' if recipe["image"] else ""
    og_image = f'\n  <meta property="og:image" content="{esc(recipe["image"])}">' if recipe["image"] else ""
    rating = f" Ratings: pink {stars['pink'] or 0}/5, blue {stars['blue'] or 0}/5."

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{esc(recipe["name"])} - {SITE_NAME}</title>
  <meta name="description" content="{esc(description(recipe))}">
  <link rel="canonical" href="{esc(recipe["pageUrl"])}">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="{SITE_NAME}">
  <meta property="og:title" content="{esc(recipe["name"])}">
  <meta property="og:description" content="{esc(description(recipe))}">
  <meta property="og:url" content="{esc(recipe["pageUrl"])}">{og_image}
  <link rel="stylesheet" href="recipe.css">
  <script type="application/ld+json">
{json_ld(recipe)}
  </script>
</head>
<body>
  <main class="recipe">
    <nav class="top">
      <a href="index.html">All recipe pages</a>
      <a href="../index.html">Recipe vault</a>
      <a href="../groupings.html">Meal shuffler</a>
    </nav>
    <header>
      <h1>{esc(recipe["name"])}</h1>
      <p class="meta">{esc(description(recipe))}{esc(rating)}</p>{hero}
    </header>
    <section class="ingredients">
      <h2>Ingredients</h2>
      <ul class="ingredients">
{ingredient_items}
      </ul>
    </section>
    <section class="steps">
      <h2>Steps</h2>
      <ol class="steps">
{chr(10).join(step_items)}
      </ol>
    </section>{notes_html}
    <footer>Generated from data/source/recipes.json by scripts/build_runtime_data.py.</footer>
  </main>
</body>
</html>
"""


def render_index_page(runtime_recipes: list[dict]) -> str:
    items = []
    for recipe in sorted(runtime_recipes, key=lambda r: r["name"].lower()):
        thumb = f'<img src="{esc(image_at(recipe["image"], 128, 128))}" alt="" loading="lazy">' if recipe["image"] else ""
        source_steps = len({step["sourceStep"] for step in recipe["steps"]})
        items.append(
            f'      <li>{thumb}<a href="{esc(recipe["slug"])}.html">{esc(recipe["name"])}</a>'
            f'<span class="count">{len(recipe["ingredients"])} ingredients, {source_steps} steps</span></li>'
        )
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Recipe pages - {SITE_NAME}</title>
  <meta name="description" content="One page per recipe, with schema.org Recipe data for importing into recipe apps and Alexa+.">
  <link rel="canonical" href="{SITE_BASE}recipes/index.html">
  <link rel="stylesheet" href="recipe.css">
</head>
<body>
  <main>
    <nav class="top">
      <a href="../index.html">Recipe vault</a>
      <a href="../groupings.html">Meal shuffler</a>
    </nav>
    <h1>Recipe pages</h1>
    <p class="meta">{len(runtime_recipes)} recipes. Share a page link with Alexa+ (Alexa app share sheet or Alexa.com) to add it to the recipe library.</p>
    <ul class="recipe-index">
{chr(10).join(items)}
    </ul>
    <footer>Generated from data/source/recipes.json by scripts/build_runtime_data.py.</footer>
  </main>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


def build_outputs(source_recipes: list[dict]) -> dict[Path, str]:
    """Return every output file as {path: text}."""
    runtime_recipes = [build_runtime_recipe(recipe) for recipe in source_recipes]
    alias_index, ingredient_index = build_indexes(runtime_recipes)

    def dump(data: object) -> str:
        return json.dumps(data, indent=2) + "\n"

    outputs = {
        RUNTIME_DIR / "recipes.runtime.json": dump(runtime_recipes),
        RUNTIME_DIR / "aliases.index.json": dump(alias_index),
        RUNTIME_DIR / "ingredients.index.json": dump(ingredient_index),
        RUNTIME_DIR / "haves.json": dump(haves_catalog(runtime_recipes)),
        REPORTS_DIR / "validation_report.md": build_validation_report(source_recipes, runtime_recipes, alias_index),
        PAGES_DIR / "recipe.css": RECIPE_CSS,
        PAGES_DIR / "index.html": render_index_page(runtime_recipes),
    }
    for recipe in runtime_recipes:
        outputs[PAGES_DIR / f"{recipe['slug']}.html"] = render_recipe_page(recipe)
    return outputs


def stale_outputs(outputs: dict[Path, str]) -> list[Path]:
    stale = []
    for path, text in outputs.items():
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            stale.append(path)
    for extra in PAGES_DIR.glob("*.html"):
        if extra not in outputs:
            stale.append(extra)
    return stale


def load_source() -> list[dict]:
    return json.loads(SOURCE_PATH.read_text(encoding="utf-8"))


def main(argv: list[str]) -> int:
    check = "--check" in argv
    outputs = build_outputs(load_source())

    if check:
        stale = stale_outputs(outputs)
        if stale:
            print("Stale outputs (run python scripts/build_runtime_data.py):")
            for path in stale:
                print(f"  {path.relative_to(ROOT)}")
            return 1
        print(f"Up to date: {len(outputs)} files.")
        return 0

    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")
    for extra in PAGES_DIR.glob("*.html"):
        if extra not in outputs:
            extra.unlink()
            print(f"Removed stale page {extra.relative_to(ROOT)}")
    recipe_count = sum(1 for p in outputs if p.parent == PAGES_DIR and p.suffix == ".html" and p.name != "index.html")
    print(f"Built runtime data and {recipe_count} recipe pages ({len(outputs)} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
