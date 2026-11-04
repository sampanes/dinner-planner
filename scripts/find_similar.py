"""Find HelloFresh recipes that look like the ones rated well in the vault.

    python scripts/find_similar.py                  # writes ~/Downloads/dinner-planner-similar-recipes.html
    python scripts/find_similar.py --top 60 --limit 800
    python scripts/find_similar.py --out path.html --force

How it works
  1. Every vault recipe gets a weight from its two star ratings: 5/5 pulls
     hard toward itself, 0/1 pushes away, 2.5 is neutral.
  2. The HelloFresh sitemap (about 17k pages) is narrowed by slug words that
     appear in the names and ingredients of the liked recipes, newest first,
     to --limit pages. Each page's Recipe block is fetched once and cached in
     data/cache/hellofresh/pages/.
  3. Each recipe becomes a bag of ingredient names, ingredient words and
     title words (idf-weighted). A candidate's score is the rating-weighted
     cosine similarity to the three liked vault recipes it most resembles,
     minus the same for the two disliked ones it most resembles. Menu-ops
     variants, unrated pages, dishes you already have, and near-identical
     variants of a better candidate are folded away.
  4. The top --top candidates go to one local HTML page with the photo in
     the same 1200x800 crop the site uses, a "why" line, the ingredients and
     the import command for scripts/import_hellofresh.py.

Only the network fetch is non-deterministic; with a warm cache the output is
a pure function of the vault and the cache.
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import math
import re
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import hellofresh as hf  # noqa: E402
from recipe_text import _singular, normalize_text  # noqa: E402

SOURCE_PATH = hf.ROOT / "data" / "source" / "recipes.json"
CANDIDATES_PATH = hf.CACHE_DIR / "candidates.json"
DEFAULT_OUT = Path.home() / "Downloads" / "dinner-planner-similar-recipes.html"

STOPWORDS = {
    "and", "or", "of", "the", "a", "an", "in", "with", "to", "for", "mix", "blend",
    "unit", "units", "fresh", "large", "small", "whole", "style", "cup", "cups",
    "oz", "ounce", "ounces", "tablespoon", "teaspoon", "taste", "one", "pan",
    "pot", "sheet", "skillet", "easy", "quick", "n",
}
NEAREST_LIKED = 3  # the strongest pulls that count toward a candidate
NEAREST_DISLIKED = 2  # the strongest pushes that count against it
PHRASE_WEIGHT = 1.0  # a whole ingredient name in common ("italian pork sausage")
WORD_WEIGHT = 0.5  # a word in common ("sausage")
NAME_WEIGHT = 0.6  # a word of the title in common ("bake")
TITLE_STOPWORDS = {
    "pepper", "salt", "garlic", "butter", "oil", "sauce", "plus", "just", "delicious",
    "serving", "2x", "the", "for", "bu", "made", "extra", "our", "new", "classic",
}
# Shared staples are true but tell you nothing; the why-line lists them last.
STAPLES = {"salt", "pepper", "oil", "butter", "water", "sugar", "flour", "garlic", "yellow onion", "stock concentrate", "sour cream"}
HAVE_THRESHOLD = 0.85  # cosine to a vault recipe: you already have this dish
VARIANT_THRESHOLD = 0.70  # cosine between candidates: same dish, different protein/veg (a protein swap measures ~0.77)
PAGE_IMAGE_TRANSFORM = "c_fill,w_600,h_400,f_auto,q_auto"

# HelloFresh's sitemap also lists its internal menu variants ("[SWAP PORK
# SAUSAGE TO CHICKEN SAUSAGE] Rigatoni", "BYOP Pasta Bar", "Family 4p/8p ...",
# "20MM ...", "MA only Compliant ..."). They are never rated and are not what
# a customer sees, so they are dropped by name and by slug.
INTERNAL_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in (
        r"^\s*\[", r"\bswap\b", r"\bupgrade\b", r"\bside add\b", r"\bprotein double\b",
        r"\bbyop\b", r"\bfamily\s+\d", r"\b\d+p/\d+p\b", r"\bonly compliant\b", r"\bcompliant\b",
        r"\(d2v\)", r"\bsku\b", r"^\s*\d+mm\b", r"\bdouble\s+(?:chicken|beef|pork|shrimp|steak)\b",
        r"\badd\s+(?:chicken|beef|pork|shrimp|bacon|veggie|sausage)\b", r"\bveggie to\b", r"\bto veggie\b",
        r"^\s*w\d+\s+r\d+\b", r"\badd on\b", r"\brecipette\b", r"\bmake ahead\b", r"\bsharing side\b",
        r"\|\s*\d", r"\bservings plan\b", r"\bkid'?s lunch\b", r"\(cut\b", r"\bplan:",
    )
]


def is_internal(text: str) -> bool:
    """True for a HelloFresh menu-ops name or slug, not a customer recipe."""
    text = text.replace("-", " ")
    return any(pattern.search(text) for pattern in INTERNAL_PATTERNS)


# ---------------------------------------------------------------------------
# Vault ratings


def rating_weight(recipe: dict) -> float:
    """-1.0 (hated) .. +1.0 (loved); 2.5 average stars is 0."""
    pink = float(recipe.get("pinkStar", 0) or 0)
    blue = float(recipe.get("blueStar", 0) or 0)
    return ((pink + blue) / 2 - 2.5) / 2.5


def stars(recipe: dict) -> str:
    return f"{recipe.get('pinkStar', 0)}/{recipe.get('blueStar', 0)}"


# ---------------------------------------------------------------------------
# Bags of words


def tokens(text: str) -> list[str]:
    words = re.split(r"[^a-z0-9]+", normalize_text(text).lower())
    out = []
    for word in words:
        if len(word) < 2 or word in STOPWORDS or word.isdigit():
            continue
        out.append(_singular(word))
    return out


def phrase(name: str) -> str:
    """The canonical ingredient name as one token: "ing:italian pork sausage"."""
    return "ing:" + " ".join(tokens(name))


def bag_from(ingredient_names: list[str], title: str) -> dict[str, float]:
    bag: dict[str, float] = {}
    for name in ingredient_names:
        words = tokens(name)
        if not words:
            continue
        bag[phrase(name)] = PHRASE_WEIGHT
        for token in words:
            bag[token] = max(bag.get(token, 0.0), WORD_WEIGHT)
    for token in tokens(title):
        if token not in TITLE_STOPWORDS:
            bag[token] = min(1.0, bag.get(token, 0.0) + NAME_WEIGHT)
    return bag


def vault_ingredient_names(recipe: dict) -> list[str]:
    return [ingredient.get("name", "") for ingredient in recipe.get("ingredients", [])]


def hf_ingredient_names(recipe: dict) -> list[str]:
    return [hf.parse_hf_ingredient(str(raw))[1] for raw in recipe.get("recipeIngredient", [])]


def bag_from_vault(recipe: dict) -> dict[str, float]:
    return bag_from(vault_ingredient_names(recipe), recipe.get("name", ""))


def bag_from_hf(recipe: dict) -> dict[str, float]:
    return bag_from(hf_ingredient_names(recipe), hf.short_name(str(recipe.get("name", ""))))


def idf_table(bags: list[dict[str, float]]) -> dict[str, float]:
    df: dict[str, int] = {}
    for bag in bags:
        for token in bag:
            df[token] = df.get(token, 0) + 1
    n = len(bags)
    return {token: math.log((n + 1) / (count + 1)) + 1.0 for token, count in df.items()}


def vectorize(bag: dict[str, float], idf: dict[str, float]) -> dict[str, float]:
    vector = {token: weight * idf.get(token, 1.0) for token, weight in bag.items()}
    norm = math.sqrt(sum(value * value for value in vector.values())) or 1.0
    return {token: value / norm for token, value in vector.items()}


def cosine(a: dict[str, float], b: dict[str, float]) -> float:
    if len(a) > len(b):
        a, b = b, a
    return sum(value * b[token] for token, value in a.items() if token in b)


# ---------------------------------------------------------------------------
# Sitemap prefilter


def slug_vocabulary(vault: list[dict]) -> dict[str, float]:
    """Word -> signed weight, from the names and ingredients of rated recipes."""
    vocabulary: dict[str, float] = {}
    for recipe in vault:
        weight = rating_weight(recipe)
        if weight == 0:
            continue
        seen = set(tokens(recipe.get("name", "")))
        for ingredient in recipe.get("ingredients", []):
            if ingredient.get("name", "").lower() not in STAPLES:
                seen.update(tokens(ingredient.get("name", "")))
        seen -= TITLE_STOPWORDS | {_singular(word) for staple in STAPLES for word in tokens(staple)}
        for token in seen:
            # Dislikes push half as hard as likes pull, so a shared staple
            # does not blacklist a whole category.
            vocabulary[token] = vocabulary.get(token, 0.0) + (weight if weight > 0 else weight * 0.5)
    return vocabulary


def prefilter(entries: list[dict], vocabulary: dict[str, float], skip_ids: set[str], min_year: int, limit: int) -> list[dict]:
    scored = []
    for entry in entries:
        if entry["id"] in skip_ids or entry["lastmod"][:4] < str(min_year) or is_internal(entry["slug"]):
            continue
        words = set(tokens(entry["slug"].replace("-", " ")))
        score = sum(vocabulary.get(word, 0.0) for word in words)
        if score > 0:
            scored.append((score, entry["lastmod"], entry))
    scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
    return [entry for _score, _lastmod, entry in scored[:limit]]


# ---------------------------------------------------------------------------
# Scoring


def vault_image_ids(vault: list[dict]) -> set[str]:
    ids = set()
    for recipe in vault:
        match = hf.RECIPE_ID.search(recipe.get("image", ""))
        if match:
            ids.add(match.group(1))
    return ids


def same_dish(name: str, vault_names: list[str]) -> bool:
    """"Garlic Butter Shrimp Scampi over Spaghetti" is the vault's "Garlic Butter Shrimp Scampi"."""
    lowered = name.lower()
    return any(lowered == other or lowered.startswith(other + " ") or other.startswith(lowered + " ") for other in vault_names)


def score_candidates(vault: list[dict], fetched: list[tuple[dict, dict]], top: int, include_unrated: bool = False) -> tuple[list[dict], dict]:
    """fetched = [(sitemap entry, Recipe block)] -> (ranked candidates, stats)."""
    vault_bags = [bag_from_vault(recipe) for recipe in vault]
    hf_bags = [bag_from_hf(recipe) for _entry, recipe in fetched]
    idf = idf_table(vault_bags + hf_bags)
    vault_vectors = [vectorize(bag, idf) for bag in vault_bags]
    weights = [rating_weight(recipe) for recipe in vault]
    vault_names = [hf.short_name(recipe["name"]).lower() for recipe in vault]
    vault_phrases = [{phrase(name) for name in vault_ingredient_names(recipe)} for recipe in vault]
    have_ids = vault_image_ids(vault)

    stats = {"fetched": len(fetched), "already_have": 0, "variants": 0, "internal": 0, "unrated": 0}
    scored = []
    for (entry, recipe), bag in zip(fetched, hf_bags):
        full_name = str(recipe.get("name", ""))
        name = hf.short_name(full_name)
        if is_internal(full_name) or is_internal(entry.get("slug", "")):
            stats["internal"] += 1
            continue
        rating = recipe.get("aggregateRating") or {}
        if not include_unrated and not _float(rating.get("ratingValue")):
            stats["unrated"] += 1
            continue
        vector = vectorize(bag, idf)
        sims = [cosine(vector, other) for other in vault_vectors]
        if same_dish(name, vault_names) or hf.recipe_id_from(recipe) in have_ids or max(sims, default=0) >= HAVE_THRESHOLD:
            stats["already_have"] += 1
            continue
        contributions = [weight * sim for weight, sim in zip(weights, sims)]
        pulls = sorted((index for index, value in enumerate(contributions) if value > 0), key=lambda index: -contributions[index])
        pushes = sorted((index for index, value in enumerate(contributions) if value < 0), key=lambda index: contributions[index])
        score = sum(contributions[index] for index in pulls[:NEAREST_LIKED]) + sum(contributions[index] for index in pushes[:NEAREST_DISLIKED])
        drivers = pulls[:2]
        candidate_phrases = {phrase(name) for name in hf_ingredient_names(recipe)}
        shared: dict[str, float] = {}
        for index in drivers:
            for token in candidate_phrases & vault_phrases[index]:
                shared[token[4:]] = max(shared.get(token[4:], 0.0), idf.get(token, 1.0))
        scored.append(
            {
                "sitemapId": entry["id"],
                "finalId": hf.recipe_id_from(recipe),
                "url": entry["url"],
                "lastmod": entry.get("lastmod", ""),
                "name": name,
                "fullName": normalize_text(str(recipe.get("name", ""))),
                "score": round(score, 4),
                "hfRating": _float(rating.get("ratingValue")),
                "hfRatingCount": _int(rating.get("ratingCount")),
                "cuisine": str(recipe.get("recipeCuisine", "") or ""),
                "totalTime": str(recipe.get("totalTime", "") or ""),
                "image": hf.uniform_image_url(_image_url(recipe)),
                "drivers": [f"{vault[index]['name']} ({stars(vault[index])})" for index in drivers],
                "shared": [name for name, _weight in sorted(shared.items(), key=lambda item: (item[0] in STAPLES, -item[1]))[:6]],
                "ingredients": [hf.parse_hf_ingredient(str(raw))[1] for raw in recipe.get("recipeIngredient", [])],
                "variants": [],
                "_vector": vector,
            }
        )

    scored.sort(key=lambda item: (-item["score"], -(item["hfRatingCount"] or 0), item["name"]))
    kept: list[dict] = []
    for candidate in scored:
        twin = next(
            (other for other in kept if cosine(candidate["_vector"], other["_vector"]) >= VARIANT_THRESHOLD or same_dish(candidate["name"], [other["name"].lower()])),
            None,
        )
        if twin is not None:
            twin["variants"].append({"name": candidate["fullName"], "url": candidate["url"], "sitemapId": candidate["sitemapId"]})
            stats["variants"] += 1
            continue
        kept.append(candidate)
        if len(kept) >= top:
            break
    for number, candidate in enumerate(kept, 1):
        candidate["n"] = number
        candidate.pop("_vector", None)
    return kept, stats


def _float(value: object) -> float | None:
    try:
        return round(float(value), 2)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def _int(value: object) -> int | None:
    try:
        return int(float(value))  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def _image_url(recipe: dict) -> str:
    image = recipe.get("image", "")
    if isinstance(image, list):
        image = image[0] if image else ""
    if isinstance(image, dict):
        image = image.get("url", "")
    return str(image)


# ---------------------------------------------------------------------------
# Page


def _duration(iso: str) -> str:
    match = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?", iso or "")
    if not match or not iso:
        return ""
    hours, minutes = int(match.group(1) or 0), int(match.group(2) or 0)
    return f"{hours * 60 + minutes} min"


def render_page(vault: list[dict], candidates: list[dict], stats: dict, built: str) -> str:
    esc = html.escape
    liked = sorted((recipe for recipe in vault if rating_weight(recipe) > 0), key=rating_weight, reverse=True)
    disliked = sorted((recipe for recipe in vault if rating_weight(recipe) < 0), key=rating_weight)
    top_score = max((candidate["score"] for candidate in candidates), default=1.0) or 1.0

    cards = []
    for candidate in candidates:
        image = candidate["image"].replace(hf.IMAGE_TRANSFORM, PAGE_IMAGE_TRANSFORM)
        subtitle = candidate["fullName"][len(candidate["name"]):].strip() if candidate["fullName"].lower().startswith(candidate["name"].lower()) else candidate["fullName"]
        meta = []
        if candidate["hfRating"]:
            count = f" ({candidate['hfRatingCount']:,})" if candidate["hfRatingCount"] else ""
            meta.append(f"&#x2605; {candidate['hfRating']:.1f}{count}")
        if candidate["cuisine"]:
            meta.append(esc(candidate["cuisine"]))
        if _duration(candidate["totalTime"]):
            meta.append(_duration(candidate["totalTime"]))
        why = ""
        if candidate["drivers"]:
            shared = ", ".join(candidate["shared"]) or "the overall ingredient mix"
            why = f"Shares <b>{esc(shared)}</b> with {esc(' and '.join(candidate['drivers']))}."
        variants = ""
        if candidate["variants"]:
            items = "".join(f'<li><a href="{esc(v["url"])}" target="_blank" rel="noopener">{esc(v["name"])}</a></li>' for v in candidate["variants"])
            variants = f'<details><summary>+{len(candidate["variants"])} variant{"s" if len(candidate["variants"]) > 1 else ""} of the same dish</summary><ul>{items}</ul></details>'
        ingredients = "".join(f"<li>{esc(name)}</li>" for name in candidate["ingredients"])
        width = max(4, round(100 * candidate["score"] / top_score))
        cards.append(
            f"""
    <article class="card" id="c{candidate['n']}">
      <a href="{esc(candidate['url'])}" target="_blank" rel="noopener"><img src="{esc(image)}" alt="" loading="lazy" width="600" height="400"></a>
      <div class="body">
        <div class="num">#{candidate['n']}</div>
        <h2>{esc(candidate['name'])}</h2>
        <p class="sub">{esc(subtitle)}</p>
        <p class="meta">{' &middot; '.join(meta)}</p>
        <div class="bar" title="match {candidate['score']:.2f}"><span style="width:{width}%"></span></div>
        <p class="why">{why}</p>
        <details><summary>{len(candidate['ingredients'])} ingredients</summary><ul class="ing">{ingredients}</ul></details>
        {variants}
        <p class="links"><a href="{esc(candidate['url'])}" target="_blank" rel="noopener">HelloFresh page</a></p>
      </div>
    </article>"""
        )

    liked_list = "".join(f"<li>{esc(recipe['name'])} <span>{stars(recipe)}</span></li>" for recipe in liked)
    disliked_list = "".join(f"<li>{esc(recipe['name'])} <span>{stars(recipe)}</span></li>" for recipe in disliked)
    numbers = " ".join(str(candidate["n"]) for candidate in candidates[:3])
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Dinner Planner: recipes like the ones you liked</title>
<style>
  :root {{ --ink: #222; --muted: #666; --line: #e3e3e3; --accent: #c2185b; --bg: #f6f6f6; }}
  body {{ font-family: -apple-system, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 24px; background: var(--bg); color: var(--ink); }}
  header {{ max-width: 1400px; margin: 0 auto 20px; }}
  header h1 {{ margin: 0 0 6px; font-size: 26px; }}
  header p {{ margin: 4px 0; color: var(--muted); }}
  .signals {{ display: flex; gap: 32px; flex-wrap: wrap; margin: 12px 0 0; }}
  .signals div {{ background: #fff; border: 1px solid var(--line); border-radius: 10px; padding: 10px 14px; min-width: 280px; }}
  .signals h3 {{ margin: 0 0 6px; font-size: 14px; }}
  .signals ul {{ margin: 0; padding-left: 18px; font-size: 13px; columns: 2; column-gap: 24px; }}
  .signals li span {{ color: var(--muted); }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 18px; max-width: 1400px; margin: 0 auto; }}
  .card {{ background: #fff; border: 1px solid var(--line); border-radius: 12px; overflow: hidden; display: flex; flex-direction: column; }}
  .card img {{ display: block; width: 100%; aspect-ratio: 3 / 2; object-fit: cover; background: #ddd; }}
  .body {{ padding: 12px 14px 14px; position: relative; }}
  .num {{ position: absolute; top: -34px; left: 10px; background: var(--accent); color: #fff; font-weight: 700; padding: 4px 10px; border-radius: 8px; font-size: 14px; }}
  h2 {{ font-size: 17px; margin: 2px 0 2px; line-height: 1.25; }}
  .sub {{ margin: 0 0 6px; color: var(--muted); font-size: 13px; }}
  .meta {{ margin: 0 0 8px; font-size: 13px; }}
  .bar {{ height: 6px; background: #eee; border-radius: 3px; overflow: hidden; margin: 0 0 8px; }}
  .bar span {{ display: block; height: 100%; background: var(--accent); }}
  .why {{ margin: 0 0 8px; font-size: 13px; line-height: 1.4; }}
  details {{ font-size: 13px; margin: 0 0 6px; }}
  summary {{ cursor: pointer; color: var(--muted); }}
  ul.ing {{ columns: 2; column-gap: 18px; margin: 6px 0 0; padding-left: 18px; }}
  .links {{ margin: 6px 0 0; font-size: 13px; }}
  footer {{ max-width: 1400px; margin: 28px auto 0; background: #fff; border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; }}
  footer code, pre {{ background: #f1f1f1; padding: 2px 6px; border-radius: 4px; font-size: 13px; }}
  pre {{ padding: 10px 12px; overflow-x: auto; }}
</style>
</head>
<body>
<header>
  <h1>Recipes like the ones you liked</h1>
  <p>{len(candidates)} HelloFresh recipes ranked by how much their ingredients and dish type match your ratings. Built {esc(built)} from {stats['fetched']} fetched pages; {stats['internal']} were HelloFresh menu-ops variants, {stats['unrated']} had no customer rating, {stats['already_have']} were dishes you already have and {stats['variants']} were folded in as variants. Photos are shown in the same 1200x800 crop the site now uses.</p>
  <div class="signals">
    <div><h3>Pulled toward (liked)</h3><ul>{liked_list}</ul></div>
    <div><h3>Pushed away (disliked)</h3><ul>{disliked_list or '<li>none</li>'}</ul></div>
  </div>
</header>
<section class="grid">{''.join(cards)}
</section>
<footer>
  <p>To add any of these to the vault, run this from the repo with the card numbers you want (the recipe is scaled to 4 servings, unrated, with the uniform photo crop), then rebuild:</p>
  <pre>python scripts/import_hellofresh.py {esc(numbers)}
python scripts/build_runtime_data.py
python -m unittest discover -s tests</pre>
  <p>Rerun <code>python scripts/find_similar.py</code> after rating the new ones and the list re-ranks around what you thought of them.</p>
</footer>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Main


def unique_path(path: Path, force: bool) -> Path:
    if force or not path.exists():
        return path
    stamp = datetime.date.today().isoformat()
    candidate = path.with_name(f"{path.stem}-{stamp}{path.suffix}")
    counter = 2
    while candidate.exists():
        candidate = path.with_name(f"{path.stem}-{stamp}-{counter}{path.suffix}")
        counter += 1
    return candidate


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--limit", type=int, default=800, help="sitemap pages to fetch after the slug prefilter")
    parser.add_argument("--top", type=int, default=40, help="candidates on the page")
    parser.add_argument("--min-year", type=int, default=2021, help="ignore sitemap entries last modified before this year")
    parser.add_argument("--include-unrated", action="store_true", help="keep recipes with no customer rating (new or never shipped)")
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--force", action="store_true", help="overwrite --out instead of adding a date suffix")
    parser.add_argument("--refresh-sitemap", action="store_true")
    parser.add_argument("--offline", action="store_true", help="re-rank from the page cache only, no fetching")
    args = parser.parse_args(argv)

    vault = json.loads(SOURCE_PATH.read_text(encoding="utf-8"))
    vocabulary = slug_vocabulary(vault)
    entries = hf.fetch_sitemap(force=args.refresh_sitemap)
    chosen = prefilter(entries, vocabulary, vault_image_ids(vault), args.min_year, args.limit)
    print(f"sitemap: {len(entries)} pages; prefilter kept {len(chosen)}")
    if args.offline:
        chosen = [entry for entry in chosen if hf.page_cache_path(entry["id"]).exists()]
        print(f"offline: {len(chosen)} of those are cached")

    fetched: list[tuple[dict, dict]] = []
    cached = sum(1 for entry in chosen if hf.page_cache_path(entry["id"]).exists())
    print(f"fetching {len(chosen) - cached} pages ({cached} cached) with {args.workers} workers")
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(hf.fetch_recipe, entry): entry for entry in chosen}
        done = 0
        for future in as_completed(futures):
            done += 1
            recipe = future.result()
            if recipe:
                fetched.append((futures[future], recipe))
            if done % 50 == 0 or done == len(futures):
                print(f"  {done}/{len(futures)} pages, {len(fetched)} with a Recipe block", file=sys.stderr)
    fetched.sort(key=lambda item: item[0]["id"])

    candidates, stats = score_candidates(vault, fetched, args.top, args.include_unrated)
    print(f"scored {stats['fetched']}: {stats['internal']} internal variants, {stats['unrated']} unrated, {stats['already_have']} already in the vault, {stats['variants']} folded as variants")
    built = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    hf.CACHE_DIR.mkdir(parents=True, exist_ok=True)
    CANDIDATES_PATH.write_text(json.dumps({"built": built, "candidates": candidates}, ensure_ascii=False, indent=1), encoding="utf-8")

    out = unique_path(args.out, args.force)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(render_page(vault, candidates, stats, built), encoding="utf-8")
    print(f"{len(candidates)} candidates -> {out}")
    for candidate in candidates[:10]:
        print(f"  #{candidate['n']:<3} {candidate['score']:.3f}  {candidate['name']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
