"""Text normalization and instruction parsing shared by the build scripts.

Everything here is deterministic and ASCII-only on output. The web app, the
generated recipe pages and any future voice client all read the result of
these functions, so they are the one place where recipe text is cleaned up.
"""

import re
import unicodedata

# Characters that have a plain ASCII spelling.
FRACTIONS = {
    "\u00bd": "1/2",
    "\u00bc": "1/4",
    "\u00be": "3/4",
    "\u2153": "1/3",
    "\u2154": "2/3",
    "\u215b": "1/8",
    "\u215c": "3/8",
    "\u215d": "5/8",
    "\u215e": "7/8",
}

SIMPLE_REPLACEMENTS = {
    "\u2010": "-",  # hyphen
    "\u2011": "-",  # non-breaking hyphen
    "\u2012": "-",  # figure dash
    "\u2013": "-",  # en dash
    "\u2014": "-",  # em dash
    "\u2018": "'",
    "\u2019": "'",
    "\u201c": '"',
    "\u201d": '"',
    "\u2026": "...",
    "\u00a0": " ",
    "\u2022": "-",  # bullet
    "\u00d7": "x",
    "\u2044": "/",  # fraction slash
}

FRACTION_CLASS = "[" + "".join(FRACTIONS) + "]"

MAX_SPOKEN_STEP_CHARS = 200


def normalize_text(text: str) -> str:
    """Return an ASCII-only version of recipe text, keeping newlines."""
    if not text:
        return ""

    # HelloFresh glyph artifact: "11/2 cups" is "1 1/2 cups" when the slash is U+2044.
    text = re.sub(r"(?<=\d)(\d)\u2044(\d)", r" \1/\2", text)
    # "1\u00bd" -> "1 1/2", "\u00bd cup" -> "1/2 cup"
    text = re.sub(
        r"(\d)?(" + FRACTION_CLASS + ")",
        lambda m: ((m.group(1) + " ") if m.group(1) else "") + FRACTIONS[m.group(2)],
        text,
    )
    # Degrees: "375\u00b0F" -> "375 degrees F", "160\u00b0." -> "160 degrees."
    text = re.sub(r"\u00b0\s*([FC])\b", r" degrees \1", text)
    text = text.replace("\u00b0", " degrees")

    for old, new in SIMPLE_REPLACEMENTS.items():
        text = text.replace(old, new)

    # Accented letters lose their accents; anything else non-ASCII is dropped.
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = "".join(ch for ch in text if ord(ch) < 128)

    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" +\n", "\n", text)
    text = re.sub(r"\n +", "\n", text)
    return text.strip()


def non_ascii_count(text: str) -> int:
    return sum(1 for ch in (text or "") if ord(ch) > 127)


def slugify(value: str) -> str:
    value = normalize_text(value).lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-")


# ---------------------------------------------------------------------------
# Instruction parsing
# ---------------------------------------------------------------------------

NUMBER_LINE = re.compile(r"^\s*(\d+)\s*$")
NUMBERED_PARAGRAPH = re.compile(r"(?:^|\n)\s*(\d+)[.)]\s+")
LINE_BULLET = re.compile(r"^\s*[-*]\s+")
INLINE_BULLET = re.compile(r"\s-\s+(?=[A-Z])")
MAX_HEADING_CHARS = 60


def _split_parts(chunk: str) -> list[str]:
    """Split one step's text into spoken parts on line and inline bullets."""
    pieces = []
    for line in chunk.split("\n"):
        line = line.strip()
        if not line:
            continue
        line = LINE_BULLET.sub("", line)
        pieces.extend(p.strip() for p in INLINE_BULLET.split(line) if p.strip())
    return pieces


def _is_heading(line: str) -> bool:
    if len(line) > MAX_HEADING_CHARS or LINE_BULLET.match(line) or NUMBER_LINE.match(line):
        return False
    return not line.endswith((".", "!", "?", ":"))


def _parse_numbered(text: str) -> tuple[list[dict], list[str]]:
    """Layout: "1. text" paragraphs separated by blank lines."""
    steps = []
    notes = []
    matches = list(NUMBERED_PARAGRAPH.finditer(text))
    preamble = text[: matches[0].start()].strip()
    if preamble:
        notes.append(" ".join(preamble.split()))
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        chunk = text[match.end() : end].strip()
        parts = _split_parts(chunk)
        if parts:
            steps.append({"sourceStep": int(match.group(1)), "section": None, "parts": parts})
    return steps, notes


def _parse_bare_numbers(text: str) -> tuple[list[dict], list[str]]:
    """Layout: HelloFresh cards. A number alone on a line starts a step, the
    short line right before it is the section heading, bullets are parts, and
    a paragraph after the last step that is not a bullet is a recipe note."""
    lines = text.split("\n")
    steps = []
    notes = []
    current = None
    blank_before = False

    for index, raw in enumerate(lines):
        line = raw.strip()
        if not line:
            blank_before = True
            continue

        number = NUMBER_LINE.match(line)
        if number:
            current = {"sourceStep": int(number.group(1)), "section": None, "parts": []}
            steps.append(current)
            blank_before = False
            continue

        next_nonblank = next((l.strip() for l in lines[index + 1 :] if l.strip()), "")
        if NUMBER_LINE.match(next_nonblank) and _is_heading(line):
            # Heading for the step that starts on the next line.
            pending = {"sourceStep": None, "section": line, "parts": []}
            steps.append(pending)
            current = pending
            blank_before = False
            continue

        if current is None:
            notes.append(line)
        elif LINE_BULLET.match(line) or INLINE_BULLET.search(line):
            current["parts"].extend(_split_parts(line))
        elif blank_before and current["parts"]:
            notes.append(line)
        elif current["parts"]:
            current["parts"][-1] = current["parts"][-1] + " " + line
        else:
            current["parts"].append(line)
        blank_before = False

    # Merge a heading record with the numbered record that follows it.
    merged = []
    for step in steps:
        if merged and merged[-1]["sourceStep"] is None and step["sourceStep"] is not None:
            merged[-1]["sourceStep"] = step["sourceStep"]
            merged[-1]["parts"].extend(step["parts"])
        else:
            merged.append(step)
    merged = [s for s in merged if s["parts"]]
    for i, step in enumerate(merged, start=1):
        if step["sourceStep"] is None:
            step["sourceStep"] = i
    return merged, notes


def parse_instructions(instructions: str) -> tuple[list[dict], list[str]]:
    """Return (steps, notes). Each step is {sourceStep, section, parts}."""
    text = normalize_text(instructions)
    if not text:
        return [], []
    if NUMBERED_PARAGRAPH.search(text):
        return _parse_numbered(text)
    if any(NUMBER_LINE.match(line) for line in text.split("\n")):
        return _parse_bare_numbers(text)
    paragraphs = [" ".join(p.split()) for p in re.split(r"\n\s*\n+", text) if p.strip()]
    steps = []
    for i, paragraph in enumerate(paragraphs, start=1):
        parts = _split_parts(paragraph) or [paragraph]
        steps.append({"sourceStep": i, "section": None, "parts": parts})
    return steps, []


# ---------------------------------------------------------------------------
# Step annotations
# ---------------------------------------------------------------------------

TIME_PATTERN = re.compile(
    r"\b(\d+)(?:\s*(?:-|to)\s*(\d+))?\s*(minutes?|mins?|min|seconds?|secs?|sec|hours?|hrs?|hr)\b",
    re.IGNORECASE,
)

UNIT_SECONDS = {"min": 60, "sec": 1, "hour": 3600, "hr": 3600}


# Pantry items that are almost never what a timer is for.
STAPLES = {"salt", "pepper", "oil", "olive oil", "butter", "sugar", "flour", "water"}

SENTENCE_END = re.compile(r"(?<=[.!?;])\s+")


def timer_hints(text: str, ingredients: list[dict] | None = None) -> list[dict]:
    """Durations mentioned in a step, longest bound in seconds.

    With ingredients, each hint also gets a "label" naming what the timer is
    for: the first non-staple ingredient in the same sentence, else the
    sentence's opening verb ("bake"). A kitchen timer called "step 4" tells
    nobody across the room which pot to check.
    """
    hints = []
    for match in TIME_PATTERN.finditer(text):
        unit = match.group(3).lower()
        multiplier = UNIT_SECONDS["hour"] if unit.startswith("h") else UNIT_SECONDS["sec"] if unit.startswith("s") else UNIT_SECONDS["min"]
        high = int(match.group(2) or match.group(1))
        hint = {"text": match.group(0), "seconds": high * multiplier}
        if ingredients is not None:
            label = _timer_label(text, match.start(), ingredients)
            if label:
                hint["label"] = label
        hints.append(hint)
    return hints


# Opening verbs that say on their own what the timer is for.
TELLING_VERBS = {"bake", "roast", "broil", "simmer", "boil", "toast", "rest", "marinate", "microwave", "steam", "cool", "chill"}


def _timer_label(text: str, position: int, ingredients: list[dict]) -> str:
    # The sentence holding the time, then the ones before it, nearest first:
    # "Add tomatoes. Cook, stirring, 1-2 minutes." times the tomatoes.
    end_match = SENTENCE_END.search(text, position)
    head = text[:end_match.start() if end_match else len(text)]
    sentences = [s for s in SENTENCE_END.split(head) if s.strip()]
    by_id = {i["id"]: i for i in ingredients}
    for sentence in reversed(sentences):
        for ingredient_id in ingredient_refs(sentence, ingredients):
            name = by_id[ingredient_id]["canonicalName"]
            if name not in STAPLES:
                return name
    # No food named: the last telling verb before the time ("cover and bake 20 min").
    before = sentences[-1][: max(0, position - (len(head) - len(sentences[-1])))] if sentences else ""
    verbs = [w for w in re.findall(r"[a-z]+", before.lower()) if w in TELLING_VERBS]
    return verbs[-1] if verbs else ""


def _singular(word: str) -> str:
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith("oes") and len(word) > 4:  # potatoes, tomatoes
        return word[:-2]
    if word.endswith("es") and len(word) > 4 and word[-3] in "sxz":
        return word[:-2]
    if word.endswith("s") and not word.endswith("ss") and len(word) > 3:
        return word[:-1]
    return word


# Last words that only say what kind of thing the ingredient is. Recipes call
# "penne pasta" penne and "mozzarella cheese" mozzarella, so for these the word
# before is the one to look for; on its own "cheese" would also hit "cream cheese".
KIND_WORDS = {"pasta", "cheese", "pepper", "peppers"}
# Last words too generic to stand for the ingredient alone ("hot sauce" must not
# light up on "until the sauce thickens").
GENERIC_WORDS = {
    "sauce", "paste", "blend", "seasoning", "spice", "mix", "base", "concentrate",
    "dressing", "glaze", "powder", "flakes", "crema", "block", "beans", "greens",
}
# Words before a KIND_WORD that do not name the ingredient by themselves.
# Proteins recipes name by the animal alone ("add chicken" for "diced chicken thighs").
PROTEIN_WORDS = {"chicken", "beef", "pork", "turkey", "sausage", "shrimp", "salmon", "steak", "bacon"}
VAGUE_MODIFIERS = {"cream", "fresh", "green", "red", "bell", "long", "chili", "jack", "cheese"}


def _candidates(name: str) -> set[str]:
    words = name.split()
    candidates = {name, _singular(name)}
    if len(words) < 2:
        return candidates
    candidates.update(w for w in words if w in PROTEIN_WORDS)
    last = words[-1]
    if last in KIND_WORDS:
        candidates.add(" ".join(words[-2:]))
        if words[-2] not in VAGUE_MODIFIERS and len(words[-2]) >= 4:
            candidates.add(words[-2])
    elif last not in GENERIC_WORDS and len(last) >= 4:
        candidates.add(last)
        candidates.add(_singular(last))
    return {c for c in candidates if c}


def ingredient_refs(text: str, ingredients: list[dict]) -> list[str]:
    """Ids of ingredients mentioned in the text, in the order the text names
    them. Heuristic, hints only. A mention inside a longer mention of another
    ingredient does not count ("pepper" inside "bell pepper")."""
    lowered = text.lower()
    hits = []  # (start, end, id)
    for ingredient in ingredients:
        name = ingredient["canonicalName"]
        if not name:
            continue
        spans = [
            (m.start(), m.end())
            for c in _candidates(name)
            for m in re.finditer(r"\b" + re.escape(c) + r"(?:s|es)?\b", lowered)
        ]
        hits.extend((s, e, ingredient["id"]) for s, e in spans)
    kept = {}
    for start, end, ingredient_id in hits:
        inside_longer = any(
            other != ingredient_id and s <= start and end <= e and (e - s) > (end - start)
            for s, e, other in hits
        )
        if not inside_longer and (ingredient_id not in kept or start < kept[ingredient_id]):
            kept[ingredient_id] = start
    return sorted(kept, key=lambda i: kept[i])
