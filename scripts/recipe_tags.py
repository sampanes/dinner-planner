"""Tags the kitchen picker filters on, worked out from each recipe's name and ingredients.

    moods(name, ingredients)     -> ["Tex-Mex", "Cheesy", ...]
    proteins(name, ingredients)  -> ["Beef"], or ["Veggie"] when there is no meat
    haves(ingredients)           -> ["ground beef", "zucchini", "tortillas", ...]

Heuristics, not truth: they only steer big buttons on the kitchen screen, and a
wrong guess costs one extra tile in a filtered list.
"""

import re

# Stock concentrates and broths name a meat they do not contain.
NOT_PROTEIN = re.compile(r"\b(stock|broth|bouillon|base)\b")

PROTEINS = [
    ("Beef", r"\bbeef\b|\bsirloin\b|\bsteak\b"),
    ("Chicken", r"\bchicken\b"),
    ("Pork & sausage", r"\bpork\b|\bsausage\b|\bbacon\b"),
    ("Turkey", r"\bturkey\b"),
    ("Seafood", r"\bshrimp\b|\bsalmon\b|\btilapia\b|\bcod\b|\bfish\b|\bscallops?\b"),
]

# (mood, pattern over the recipe name, pattern over ingredient names)
MOODS = [
    ("Tex-Mex",
     r"tex-mex|taco|enchilada|fajita|quesadilla|burrito|nacho|tostada|flauta|baja|cantina|southwest|poblano|chili-lime|lone star|tortilla",
     r"tortilla|southwest|mexican|taco|enchilada|chipotle|salsa|poblano|fajita|queso"),
    ("Pasta",
     r"penne|rigatoni|spaghetti|tortelloni|ravioli|cavatappi|fusilli|linguine|pasta|mac & cheese",
     r"penne|rigatoni|spaghetti|tortelloni|ravioli|cavatappi|fusilli|linguine|\bpasta\b|macaroni|orzo"),
    ("Cheesy", r"chees|melt|mozzarella|queso|mac & cheese|parmesan|cheddar", None),
    ("Creamy", r"cream|rosa|alfredo|scampi|dijon", r"cream sauce base|heavy cream|cream cheese"),
    ("Spicy", r"spicy|firecracker|kick|chipotle|sriracha|hot\b", r"hot sauce|sriracha|chipotle|jalape|gochujang|cayenne|chili paste"),
    ("Handhelds", r"melt|burger|stromboli|calzone|wrap|sandwich|quesadilla|burrito|flauta|tostada", None),
    ("Bowls & soups", r"bowl|soup|chili\b|stew|salad", None),
    ("Asian", r"bulgogi|teriyaki|sesame|sweet chili|firecracker|stir-fry|lo mein|udon|ramen|korean|thai|bibimbap",
     r"\bsoy\b|sesame|ginger|sriracha|gochujang|hoisin|teriyaki|ponzu|sweet chili"),
]

# What-do-we-have picker: (label, group, pattern over one ingredient name).
# Order is the order the buttons appear in.
HAVES = [
    ("ground beef", "Protein", r"ground beef|^beef$"),
    ("steak", "Protein", r"sirloin|steak"),
    ("chicken", "Protein", r"chicken (breast|tender|thigh|cutlet)|^chicken$"),
    ("ground turkey", "Protein", r"turkey"),
    ("sausage", "Protein", r"sausage"),
    ("bacon", "Protein", r"bacon"),
    ("shrimp", "Protein", r"shrimp"),
    ("salmon", "Protein", r"salmon"),
    ("zucchini", "Produce", r"zucchini"),
    ("onion", "Produce", r"(^|yellow |red |white )onion"),
    ("peppers", "Produce", r"bell pepper|green pepper|poblano"),
    ("tomatoes", "Produce", r"^(roma |grape |cherry )?tomato(es)?$"),
    ("mushrooms", "Produce", r"mushroom"),
    ("spinach", "Produce", r"spinach"),
    ("potatoes", "Produce", r"potato"),
    ("carrots", "Produce", r"carrot"),
    ("broccoli", "Produce", r"broccoli"),
    ("green beans", "Produce", r"green bean"),
    ("lime", "Produce", r"^limes?$"),
    ("lemon", "Produce", r"^lemons?$"),
    ("scallions", "Produce", r"scallion|green onion"),
    ("cilantro", "Produce", r"cilantro"),
    ("cucumber", "Produce", r"cucumber"),
    ("sour cream", "Dairy", r"sour cream"),
    ("cream cheese", "Dairy", r"cream cheese"),
    ("mozzarella", "Dairy", r"mozzarella"),
    ("cheddar", "Dairy", r"cheddar"),
    ("parmesan", "Dairy", r"parmesan"),
    ("mexican cheese", "Dairy", r"mexican cheese|monterey jack|pepper jack"),
    ("ricotta", "Dairy", r"ricotta"),
    ("tortillas", "Pantry", r"tortilla(s)?$"),
    ("pasta", "Pantry", r"penne|rigatoni|spaghetti|tortelloni|ravioli|cavatappi|fusilli|linguine|\bpasta\b|macaroni|orzo"),
    ("rice", "Pantry", r"\brice\b"),
    ("couscous", "Pantry", r"couscous"),
    ("bread & buns", "Pantry", r"\bbuns?\b|bread\b|ciabatta|\brolls?\b|hoagie|naan|pizza dough"),
    ("marinara", "Pantry", r"marinara"),
    ("black beans", "Pantry", r"black beans"),
    ("tortilla chips", "Pantry", r"tortilla chips"),
    ("panko", "Pantry", r"panko"),
]


def _names(ingredients: list[dict]) -> list[str]:
    return [i.get("canonicalName", "") for i in ingredients]


def proteins(name: str, ingredients: list[dict]) -> list[str]:
    text = " | ".join([name.lower()] + [n for n in _names(ingredients) if not NOT_PROTEIN.search(n)])
    found = [label for label, pattern in PROTEINS if re.search(pattern, text)]
    return found or ["Veggie"]


def moods(name: str, ingredients: list[dict]) -> list[str]:
    title = name.lower()
    ingredient_text = " | ".join(_names(ingredients))
    found = []
    for label, name_pattern, ingredient_pattern in MOODS:
        if re.search(name_pattern, title) or (ingredient_pattern and re.search(ingredient_pattern, ingredient_text)):
            found.append(label)
    cheeses = sum(1 for n in _names(ingredients) if re.search(r"chees|mozzarella|parmesan|cheddar|ricotta|queso", n))
    if "Cheesy" not in found and cheeses >= 3:
        found.append("Cheesy")
    return sorted(found, key=[m for m, _, _ in MOODS].index)


def haves(ingredients: list[dict]) -> list[str]:
    names = _names(ingredients)
    return [label for label, _, pattern in HAVES if any(re.search(pattern, n) for n in names)]


def haves_catalog(runtime_recipes: list[dict], minimum: int = 2) -> list[dict]:
    """The picker's buttons: every HAVES label at least `minimum` recipes use, in HAVES order."""
    counts = {}
    for recipe in runtime_recipes:
        for label in recipe.get("haves", []):
            counts[label] = counts.get(label, 0) + 1
    return [{"label": label, "group": group, "count": counts[label]}
            for label, group, _ in HAVES if counts.get(label, 0) >= minimum]
