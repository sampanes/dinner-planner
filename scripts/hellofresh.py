"""HelloFresh public recipe pages as a source of new recipes.

Every page under https://www.hellofresh.com/recipes/<slug>-<id> carries a
schema.org Recipe block (ingredients with amounts, bullet steps, the studio
photo, cuisine, rating). The public sitemap lists all of them. This module
knows how to read the sitemap, pull the Recipe block out of a page, and turn
it into the shape data/source/recipes.json uses.

Network access lives in fetch_* functions only; everything else is pure so
the tests can run offline.
"""

from __future__ import annotations

import gzip
import json
import re
import sys
import time
import urllib.error
import urllib.request
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from recipe_text import normalize_text  # noqa: E402
from reformat_json import apply_replacements, replace_tuples  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / "data" / "cache" / "hellofresh"
PAGES_DIR = CACHE_DIR / "pages"
SITEMAP_URL = "https://www.hellofresh.com/sitemap_recipe_pages.xml"
SITEMAP_PATH = CACHE_DIR / "sitemap.xml"
SITEMAP_MAX_AGE_DAYS = 7

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) dinner-planner/1.0 (personal recipe import)"

# One crop for every photo so the vault, the recipe pages and the Alexa card
# all show the same 3:2 shape.
IMAGE_TRANSFORM = "c_fill,w_1200,h_800,f_auto,q_auto"
IMAGE_HOST = "https://img.hellofresh.com"

RECIPE_ID = re.compile(r"([0-9a-f]{24})")

UNITS = {
    "unit", "units", "ounce", "ounces", "oz", "tablespoon", "tablespoons", "tbsp",
    "teaspoon", "teaspoons", "tsp", "cup", "cups", "clove", "cloves", "thumb",
    "thumbs", "slice", "slices", "pound", "pounds", "lb", "lbs", "milliliter",
    "milliliters", "ml", "gram", "grams", "g", "jar", "jars", "can", "cans",
    "package", "packages", "packet", "packets", "sprig", "sprigs", "bunch",
    "stalk", "stalks", "head", "heads", "piece", "pieces", "box", "bag", "pinch",
}

AMOUNT_PATTERN = re.compile(r"^\s*(\d+\s+\d+/\d+|\d+/\d+|\d*\.\d+|\d+)\s+(.*)$")

# Marketing tails HelloFresh appends to some titles.
TITLE_TAIL = re.compile(
    r"\s*(?:2x the delicious servings!?|2x the portions.*|just for the .*|one recipe.*|chedda is betta.*|\|.*|plus .*|topped.*|note:.*|now get .*)$",
    re.IGNORECASE,
)
TITLE_PORTION = re.compile(r"^(?:xl\s+)?2x\s+|\s+2x\s+", re.IGNORECASE)
# "Zucchini Pomodoro & Beef Penne Bake Zucchini Pomodoro with ...": the card
# subtitle glued on after the title repeats the title's first words.
TITLE_REPEAT = re.compile(r"^(\S+\s+\S+)\b.+?\s(?=\1\b)", re.IGNORECASE)


# ---------------------------------------------------------------------------
# Sitemap


def parse_sitemap(xml: str) -> list[dict]:
    """[{"url", "id", "slug", "lastmod"}] for every recipe page in the sitemap."""
    entries = []
    for block in re.findall(r"<url>(.*?)</url>", xml, re.S):
        loc = re.search(r"<loc>(.*?)</loc>", block)
        if not loc:
            continue
        url = loc.group(1).strip()
        lastmod = re.search(r"<lastmod>(.*?)</lastmod>", block)
        tail = url.rsplit("/", 1)[-1]
        match = re.search(r"-([0-9a-f]{24})$", tail)
        if not match:
            continue
        entries.append(
            {
                "url": url,
                "id": match.group(1),
                "slug": tail[: match.start()],
                "lastmod": lastmod.group(1).strip() if lastmod else "",
            }
        )
    return entries


def fetch_sitemap(force: bool = False) -> list[dict]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    fresh = SITEMAP_PATH.exists() and (time.time() - SITEMAP_PATH.stat().st_mtime) < SITEMAP_MAX_AGE_DAYS * 86400
    if force or not fresh:
        SITEMAP_PATH.write_bytes(_get(SITEMAP_URL))
    return parse_sitemap(SITEMAP_PATH.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Pages


def _get(url: str, retries: int = 3) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Encoding": "gzip"})
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                if response.headers.get("Content-Encoding", "").lower() == "gzip":
                    body = gzip.decompress(body)
                return body
        except (urllib.error.URLError, TimeoutError, OSError) as error:  # noqa: PERF203
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"GET {url} failed: {last_error}")


def extract_recipe_jsonld(html: str) -> dict | None:
    """The schema.org Recipe object from a page, or None."""
    for match in re.finditer(r"<script[^>]*type=\"application/ld\+json\"[^>]*>(.*?)</script>", html, re.S):
        try:
            data = json.loads(match.group(1))
        except json.JSONDecodeError:
            continue
        items = data if isinstance(data, list) else [data]
        for item in items:
            if isinstance(item, dict) and item.get("@type") == "Recipe":
                return item
            if isinstance(item, dict) and isinstance(item.get("@graph"), list):
                for node in item["@graph"]:
                    if isinstance(node, dict) and node.get("@type") == "Recipe":
                        return node
    return None


def recipe_id_from(recipe: dict) -> str:
    """The 24-hex HelloFresh id, taken from @id, then the image url."""
    for value in (recipe.get("@id", ""), str(recipe.get("image", "")), str(recipe.get("thumbnailUrl", ""))):
        match = RECIPE_ID.search(value)
        if match:
            return match.group(1)
    return ""


def page_cache_path(sitemap_id: str) -> Path:
    return PAGES_DIR / f"{sitemap_id}.json"


def fetch_recipe(entry: dict, force: bool = False) -> dict | None:
    """The cached or freshly fetched Recipe block for a sitemap entry.

    The cache records a miss too (a page without a Recipe block), so a rerun
    does not refetch it.
    """
    path = page_cache_path(entry["id"])
    if path.exists() and not force:
        try:
            return json.loads(path.read_text(encoding="utf-8")).get("recipe")
        except json.JSONDecodeError:
            pass  # a half-written cache file from a concurrent run: fetch again
    PAGES_DIR.mkdir(parents=True, exist_ok=True)
    try:
        html = _get(entry["url"]).decode("utf-8", errors="replace")
        recipe = extract_recipe_jsonld(html)
    except RuntimeError as error:
        print(f"  skip {entry['id']}: {error}", file=sys.stderr)
        return None
    record = {
        "sitemapId": entry["id"],
        "url": entry["url"],
        "lastmod": entry.get("lastmod", ""),
        "fetched": time.strftime("%Y-%m-%d"),
        "finalId": recipe_id_from(recipe) if recipe else "",
        "recipe": recipe,
    }
    path.write_text(json.dumps(record, ensure_ascii=False, indent=1), encoding="utf-8")
    return recipe


def load_cached(sitemap_id: str) -> dict | None:
    path = page_cache_path(sitemap_id)
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Conversion to the source schema


def uniform_image_url(url: str) -> str:
    """Rewrite a known photo host to one fixed 1200x800 crop.

    HelloFresh photos (img./media.hellofresh.com) take Cloudinary-style
    transforms in the first path segment; Unsplash takes query parameters.
    Anything else is returned unchanged.
    """
    if not url:
        return url
    match = re.match(r"^https?://(?:img|media)\.hellofresh\.com/([^/]+)/(.+)$", url)
    if match:
        first, rest = match.group(1), match.group(2)
        # The first segment is a transform when it holds comma-separated key_value pairs.
        if re.fullmatch(r"(?:[a-z]{1,3}_[A-Za-z0-9.:]+,?)+", first):
            return f"{IMAGE_HOST}/{IMAGE_TRANSFORM}/{rest}"
        return f"{IMAGE_HOST}/{IMAGE_TRANSFORM}/{first}/{rest}"
    match = re.match(r"^(https?://images\.unsplash\.com/[^?]+)", url)
    if match:
        return f"{match.group(1)}?auto=format&fit=crop&w=1200&h=800&q=80"
    return url


def short_name(full_name: str) -> str:
    """"Chicken Sausage Cavatappi Bolognese with Zucchini & Parmesan" -> the headline.

    The "with ..." clause is the card's subtitle. It is dropped only when the
    headline still has three words, so "Chicken Thyme with Zucchini Couscous"
    stays whole.
    """
    name = TITLE_PORTION.sub(" ", TITLE_TAIL.sub("", normalize_text(full_name))).strip()
    repeat = TITLE_REPEAT.match(name)
    if repeat:
        name = name[: repeat.end()].strip()
    head, sep, _tail = name.partition(" with ")
    if sep and len(head.split()) >= 3:
        return head.strip()
    return name


def parse_hf_ingredient(text: str) -> tuple[str, str]:
    """"1 unit Yellow Onion" -> ("1 unit", "yellow onion"); " Salt" -> ("to taste", "salt")."""
    text = normalize_text(text).strip()
    match = AMOUNT_PATTERN.match(text)
    if not match:
        return "to taste", apply_replacements(text, replace_tuples)
    amount, rest = match.group(1), match.group(2).strip()
    words = rest.split(" ", 1)
    if words and words[0].lower() in UNITS and len(words) == 2:
        amount = f"{amount} {words[0].lower()}"
        rest = words[1]
    return amount, apply_replacements(rest.strip(), replace_tuples)


def scale_amount(amount: str, factor: Fraction) -> str:
    """Multiply the leading number of an amount: "1.5 ounce" x2 -> "3 ounce"."""
    match = AMOUNT_PATTERN.match(amount)
    if not match or factor == 1:
        return amount
    number, rest = match.group(1), match.group(2)
    value = sum(Fraction(part) for part in number.split()) * factor
    whole, remainder = divmod(value.numerator, value.denominator)
    if remainder == 0:
        text = str(whole)
    elif whole:
        text = f"{whole} {Fraction(remainder, value.denominator)}"
    else:
        text = str(Fraction(remainder, value.denominator))
    return f"{text} {rest}".strip()


def steps_to_instructions(steps: list) -> str:
    """HowToStep list -> the bare-number layout the parser reads.

    Each HelloFresh step is a few "- " bullets; the card's hard line wraps are
    joined back into sentences.
    """
    blocks = []
    for index, step in enumerate(steps, 1):
        if isinstance(step, dict):
            text = step.get("text", "")
            heading = normalize_text(step.get("name", "")).strip()
        else:
            text, heading = str(step), ""
        text = normalize_text(text)
        text = re.sub(r"[ \t]*\n[ \t]*", " ", text)
        bullets = [part.strip() for part in re.split(r"\s*-\s+(?=[A-Z(])", " " + text) if part.strip()]
        lines = []
        if heading and heading != text[:len(heading)]:
            lines.append(heading)
        lines.append(str(index))
        lines.extend(f"- {bullet}" for bullet in bullets)
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks)


def servings_factor(recipe: dict, target_servings: int) -> Fraction:
    raw = recipe.get("recipeYield", "")
    if isinstance(raw, list):
        raw = raw[0] if raw else ""
    match = re.search(r"\d+", str(raw))
    if not match or int(match.group()) <= 0:
        return Fraction(1)
    return Fraction(target_servings, int(match.group()))


def to_source_recipe(recipe: dict, new_id: int, target_servings: int = 4) -> dict:
    """A data/source/recipes.json entry from a Recipe JSON-LD block, unrated."""
    factor = servings_factor(recipe, target_servings)
    ingredients = []
    for raw in recipe.get("recipeIngredient", []):
        amount, name = parse_hf_ingredient(str(raw))
        ingredients.append({"name": name, "amount": scale_amount(amount, factor)})
    image = recipe.get("image", "")
    if isinstance(image, list):
        image = image[0] if image else ""
    if isinstance(image, dict):
        image = image.get("url", "")
    return {
        "id": new_id,
        "name": short_name(str(recipe.get("name", ""))),
        "image": uniform_image_url(str(image)),
        "instructions": steps_to_instructions(recipe.get("recipeInstructions", [])),
        "pinkStar": 0,
        "blueStar": 0,
        "ingredients": ingredients,
    }
