import json
from pathlib import Path

# Replacement tuples
replace_tuples = [
    ("beef stock concentrate", "stock concentrate"),
    ("beef stock", "stock"),
    ("olive oil", "oil"),
    ("all-purpose flour", "flour"),
    ("white sugar", "sugar")
]

def apply_replacements(text, replacements):
    text = text.lower()
    for old, new in replacements:
        if text == old:
            return new
    return text

def reformat_ingredients(ingredients, replacements):
    return [
        {
            "name": apply_replacements(ing["name"], replacements),
            "amount": ing["amount"].lower()
        }
        for ing in ingredients
    ]

def write_recipes(recipes, out_path):
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("[\n")
        for idx, recipe in enumerate(recipes):
            recipe_copy = recipe.copy()
            ingredients = recipe_copy.pop("ingredients", [])

            # Build object lines manually
            f.write("  {\n")
            keys = list(recipe_copy.keys())
            for i, key in enumerate(keys):
                value = recipe_copy[key]
                line = f'    {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)}'
                f.write(line + ",\n")

            # Manually add "ingredients" as final field
            f.write('    "ingredients": [\n')
            for j, ing in enumerate(ingredients):
                ing_line = f'      {json.dumps(ing, separators=(", ", ": "))}'
                if j < len(ingredients) - 1:
                    ing_line += ","
                f.write(ing_line + "\n")
            f.write("    ]\n")

            f.write("  }")
            if idx < len(recipes) - 1:
                f.write(",\n")
            else:
                f.write("\n")
        f.write("]\n")

def main():
    path = Path(__file__).parent / "recipes.json"

    if not path.exists():
        print("❌ File not found:", path)
        return
    if path.stat().st_size == 0:
        print("❌ File is empty:", path)
        return

    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            print("❌ JSON decode error:", e)
            return

    # Apply replacements and normalization
    for recipe in data:
        if "ingredients" in recipe:
            recipe["ingredients"] = reformat_ingredients(recipe["ingredients"], replace_tuples)

    # Write a complete valid array
    write_recipes(data, path)


if __name__ == "__main__":
    main()