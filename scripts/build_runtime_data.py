import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE_PATH = ROOT / "data" / "source" / "recipes.json"
RUNTIME_DIR = ROOT / "data" / "runtime"
REPORTS_DIR = ROOT / "data" / "reports"


def slugify(value: str) -> str:
    value = value.lower().strip()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


def split_steps(instructions: str) -> list[str]:
    text = instructions.strip()
    numbered = re.split(r"\n\s*\d+\.\s+", f"\n{text}")
    steps = [step.strip(" \n.-") for step in numbered if step.strip()]
    if steps:
        return steps

    paragraphs = [part.strip() for part in re.split(r"\n\s*\n+", text) if part.strip()]
    return paragraphs or [text]


def build_runtime_recipe(recipe: dict) -> dict:
    steps = split_steps(recipe.get("instructions", ""))
    normalized_ingredients = []
    search_tokens = set()

    for ingredient in recipe.get("ingredients", []):
        display_name = ingredient.get("name", "").strip()
        canonical_name = display_name.lower()
        amount_text = ingredient.get("amount", "").strip()
        normalized_ingredients.append(
            {
                "id": slugify(display_name) or f"ingredient-{len(normalized_ingredients) + 1}",
                "displayName": display_name,
                "canonicalName": canonical_name,
                "aliases": [canonical_name] if canonical_name else [],
                "amountText": amount_text,
            }
        )
        if canonical_name:
            search_tokens.add(canonical_name)

    runtime_steps = []
    for index, step in enumerate(steps, start=1):
        runtime_steps.append(
            {
                "index": index,
                "speakShort": step,
                "displayText": step,
                "ingredientRefs": [],
            }
        )

    recipe_name = recipe.get("name", "").strip()
    search_tokens.update(token for token in re.split(r"[^a-z0-9]+", recipe_name.lower()) if token)

    return {
        "id": str(recipe.get("id")),
        "name": recipe_name,
        "displayName": recipe_name,
        "aliases": [recipe_name.lower()] if recipe_name else [],
        "categories": [],
        "tags": [],
        "ingredients": normalized_ingredients,
        "steps": runtime_steps,
        "searchTokens": sorted(search_tokens),
        "image": recipe.get("image", "").strip(),
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


def build_validation_report(runtime_recipes: list[dict], alias_index: dict) -> str:
    duplicate_aliases = {alias: ids for alias, ids in alias_index.items() if len(ids) > 1}

    lines = [
        "# Validation Report",
        "",
        f"- Runtime recipes: {len(runtime_recipes)}",
        f"- Duplicate recipe aliases: {len(duplicate_aliases)}",
        "",
    ]

    if duplicate_aliases:
        lines.append("## Duplicate Aliases")
        lines.append("")
        for alias, ids in sorted(duplicate_aliases.items()):
            lines.append(f"- `{alias}` -> {', '.join(ids)}")
        lines.append("")
    else:
        lines.append("No duplicate recipe aliases detected in the current first-pass runtime build.")
        lines.append("")

    lines.append("## Notes")
    lines.append("")
    lines.append("- This is a phase-0 runtime scaffold, not the final Alexa-ready schema.")
    lines.append("- Manual aliases, timer suggestions, grouped ingredients, and richer step parsing come next.")
    lines.append("")
    return "\n".join(lines)


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    source_recipes = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    runtime_recipes = [build_runtime_recipe(recipe) for recipe in source_recipes]
    alias_index, ingredient_index = build_indexes(runtime_recipes)

    write_json(RUNTIME_DIR / "recipes.runtime.json", runtime_recipes)
    write_json(RUNTIME_DIR / "aliases.index.json", alias_index)
    write_json(RUNTIME_DIR / "ingredients.index.json", ingredient_index)

    report = build_validation_report(runtime_recipes, alias_index)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    (REPORTS_DIR / "validation_report.md").write_text(report, encoding="utf-8")

    print(f"Built runtime data for {len(runtime_recipes)} recipes.")


if __name__ == "__main__":
    main()
