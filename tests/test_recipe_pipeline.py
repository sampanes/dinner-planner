"""Tests for the recipe build pipeline.

    python -m unittest discover -s tests -v
"""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_runtime_data as build  # noqa: E402
import normalize_source  # noqa: E402
from recipe_text import (  # noqa: E402
    ingredient_refs,
    non_ascii_count,
    normalize_text,
    parse_instructions,
    slugify,
    timer_hints,
)


class NormalizeTextTests(unittest.TestCase):
    def test_fractions_and_glued_fraction_slash(self):
        self.assertEqual(normalize_text("Reserve 11\u20442 cups"), "Reserve 1 1/2 cups")
        self.assertEqual(normalize_text("1\u20442-inch-thick"), "1/2-inch-thick")
        self.assertEqual(normalize_text("\u00bd cup"), "1/2 cup")
        self.assertEqual(normalize_text("1\u00bd cups"), "1 1/2 cups")
        self.assertEqual(normalize_text("\u2153 cup"), "1/3 cup")

    def test_degrees(self):
        self.assertEqual(normalize_text("375\u00b0F (190\u00b0C)"), "375 degrees F (190 degrees C)")
        self.assertEqual(normalize_text("reaches 160\u00b0."), "reaches 160 degrees.")

    def test_dashes_quotes_accents(self):
        self.assertEqual(normalize_text("2\u20133 minutes"), "2-3 minutes")
        self.assertEqual(normalize_text("Shepherd\u2019s Pie"), "Shepherd's Pie")
        self.assertEqual(normalize_text("Beef Rag\u00f9 saut\u00e9"), "Beef Ragu saute")
        self.assertEqual(normalize_text("a \u2014 b"), "a - b")

    def test_keeps_newlines_and_collapses_spaces(self):
        self.assertEqual(normalize_text("a  b \n  c\t d"), "a b\nc d")
        self.assertEqual(non_ascii_count(normalize_text("\u2022 x \u00e9")), 0)


class SlugTests(unittest.TestCase):
    def test_slugify(self):
        self.assertEqual(slugify("Beef & Zucchini Baked Penne"), "beef-zucchini-baked-penne")
        self.assertEqual(slugify("Pub-Style Shepherd\u2019s Pie"), "pub-style-shepherd-s-pie")
        self.assertEqual(slugify("Cavatappi Beef Rag\u00f9"), "cavatappi-beef-ragu")


class ParseInstructionsTests(unittest.TestCase):
    def test_numbered_paragraphs(self):
        steps, notes = parse_instructions("1. Boil water.\n\n2. Add pasta. Stir.\n\n3. Serve.")
        self.assertEqual(notes, [])
        self.assertEqual([s["sourceStep"] for s in steps], [1, 2, 3])
        self.assertEqual(steps[1]["parts"], ["Add pasta. Stir."])
        self.assertIsNone(steps[0]["section"])

    def test_hellofresh_layout(self):
        text = (
            "1\n"
            "- Preheat oven to 450 degrees. Wash produce.\n"
            "- Slice onion.\n"
            "\n"
            "Roast Zucchini\n"
            "2\n"
            "- Toss zucchini with oil. - Roast until tender, 14-16 minutes.\n"
            "\n"
            "Finish & Serve\n"
            "3\n"
            "- Divide between bowls.\n"
            "\n"
            "Pork is fully cooked at 160 degrees.\n"
        )
        steps, notes = parse_instructions(text)
        self.assertEqual([s["sourceStep"] for s in steps], [1, 2, 3])
        self.assertEqual([s["section"] for s in steps], [None, "Roast Zucchini", "Finish & Serve"])
        self.assertEqual(steps[0]["parts"], ["Preheat oven to 450 degrees. Wash produce.", "Slice onion."])
        self.assertEqual(steps[1]["parts"], ["Toss zucchini with oil.", "Roast until tender, 14-16 minutes."])
        self.assertEqual(notes, ["Pork is fully cooked at 160 degrees."])

    def test_raw_hellofresh_bullets_before_normalization(self):
        raw = "1\n\u2022 Wash produce. \u2022 Slice onion.\n\nCook\n2\n\u2022 Cook it, 5 minutes."
        steps, _ = parse_instructions(normalize_source.normalize_instructions(raw))
        self.assertEqual(steps[0]["parts"], ["Wash produce.", "Slice onion."])
        self.assertEqual(steps[1]["section"], "Cook")

    def test_plain_paragraphs(self):
        steps, _ = parse_instructions("Mix everything.\n\nBake it.")
        self.assertEqual([s["parts"] for s in steps], [["Mix everything."], ["Bake it."]])

    def test_empty(self):
        self.assertEqual(parse_instructions(""), ([], []))


class AnnotationTests(unittest.TestCase):
    def test_timer_hints(self):
        hints = timer_hints("Roast, tossing halfway, 14-16 minutes. Microwave 30 seconds. Rest 1 hour.")
        self.assertEqual([h["seconds"] for h in hints], [16 * 60, 30, 3600])
        self.assertEqual(hints[0]["text"], "14-16 minutes")
        self.assertEqual(timer_hints("Add 2 cups water"), [])

    def test_ingredient_refs(self):
        ingredients = [
            {"id": "zucchini", "canonicalName": "zucchini"},
            {"id": "italian-seasoning", "canonicalName": "italian seasoning"},
            {"id": "eggs", "canonicalName": "eggs"},
            {"id": "sour-cream", "canonicalName": "sour cream"},
        ]
        refs = ingredient_refs("Toss zucchini with half the Italian Seasoning and one egg.", ingredients)
        self.assertEqual(refs, ["zucchini", "italian-seasoning", "eggs"])

    def test_ingredient_refs_use_the_word_recipes_actually_write(self):
        ingredients = [
            {"id": "penne-pasta", "canonicalName": "penne pasta"},
            {"id": "mozzarella-cheese", "canonicalName": "mozzarella cheese"},
            {"id": "cream-cheese", "canonicalName": "cream cheese"},
            {"id": "ground-beef", "canonicalName": "ground beef"},
            {"id": "pepper", "canonicalName": "pepper"},
            {"id": "green-bell-pepper", "canonicalName": "green bell pepper"},
            {"id": "hot-sauce", "canonicalName": "hot sauce"},
        ]
        refs = ingredient_refs("Add beef and penne, then the cream cheese. Dice bell pepper.", ingredients)
        self.assertEqual(refs, ["ground-beef", "penne-pasta", "cream-cheese", "green-bell-pepper"])
        refs = ingredient_refs("Tear mozzarella. Season with salt and pepper until the sauce thickens.", ingredients)
        self.assertEqual(refs, ["mozzarella-cheese", "pepper"])

    def test_timer_labels_name_what_is_cooking(self):
        ingredients = [
            {"id": "rigatoni-pasta", "canonicalName": "rigatoni pasta"},
            {"id": "spinach", "canonicalName": "spinach"},
            {"id": "salt", "canonicalName": "salt"},
        ]
        text = ("Season with salt. Cook until rigatoni is tender, 5-6 minutes. "
                "Add spinach. Stir until wilted, 1-2 minutes.")
        self.assertEqual([h["label"] for h in timer_hints(text, ingredients)], ["rigatoni pasta", "spinach"])
        self.assertNotIn("label", timer_hints(text)[0])
        self.assertEqual(timer_hints("Bake 10 minutes.", ingredients)[0]["label"], "bake")
        self.assertEqual(timer_hints("Cover and bake 20 min.", ingredients)[0]["label"], "bake")
        self.assertNotIn("label", timer_hints("Stir until thick, 5 minutes.", ingredients)[0])


class BuildTests(unittest.TestCase):
    def test_runtime_recipe_shape(self):
        recipe = build.build_runtime_recipe(
            {
                "id": 7,
                "name": "Test Pasta",
                "image": "",
                "instructions": "1. Boil pasta, 9-11 minutes.\n\n2. Serve with parmesan cheese.",
                "ingredients": [
                    {"name": "pasta", "amount": "8 ounce"},
                    {"name": "parmesan cheese", "amount": "to taste"},
                    {"name": "zucchini", "amount": "2 unit"},
                ],
                "pinkStar": 2,
                "blueStar": 3,
            }
        )
        self.assertEqual(recipe["slug"], "test-pasta")
        self.assertEqual(recipe["pageUrl"], build.SITE_BASE + "recipes/test-pasta.html")
        self.assertEqual([i["text"] for i in recipe["ingredients"]], ["8 ounce pasta", "parmesan cheese, to taste", "2 zucchini"])
        self.assertEqual(recipe["steps"][0]["timerHints"], [{"text": "9-11 minutes", "seconds": 660, "label": "pasta"}])
        self.assertEqual(recipe["steps"][0]["ingredientRefs"], ["pasta"])
        self.assertEqual(recipe["steps"][1]["ingredientRefs"], ["parmesan-cheese"])

    def test_page_has_recipe_json_ld(self):
        recipe = build.build_runtime_recipe(
            {
                "id": 1,
                "name": "Carbonara </script>",
                "image": "https://example.com/x.jpg",
                "instructions": "1\n- Boil.\n\nFinish\n2\n- Serve.\n\nNote here.",
                "ingredients": [{"name": "spaghetti", "amount": "400g"}],
            }
        )
        page = build.render_recipe_page(recipe)
        self.assertIn('type="application/ld+json"', page)
        self.assertNotIn("</script>\n  </script>", page)
        start = page.index('<script type="application/ld+json">') + len('<script type="application/ld+json">')
        end = page.index("</script>", start)
        data = json.loads(page[start:end].replace("<\\/", "</"))
        self.assertEqual(data["@type"], "Recipe")
        self.assertEqual(data["recipeIngredient"], ["400g spaghetti"])
        self.assertEqual(data["recipeInstructions"][1]["@type"], "HowToSection")
        self.assertEqual(data["recipeInstructions"][1]["name"], "Finish")
        self.assertEqual(data["image"], ["https://example.com/x.jpg"])
        self.assertIn("Note here.", page)
        self.assertEqual(non_ascii_count(page), 0)

    def test_committed_outputs_are_current(self):
        outputs = build.build_outputs(build.load_source())
        stale = build.stale_outputs(outputs)
        self.assertEqual([p.relative_to(ROOT).as_posix() for p in stale], [], "run python scripts/build_runtime_data.py")

    def test_source_is_ascii(self):
        text = build.SOURCE_PATH.read_text(encoding="utf-8")
        self.assertEqual(non_ascii_count(text), 0, "run python scripts/normalize_source.py")

    def test_outputs_are_ascii(self):
        for path, text in build.build_outputs(build.load_source()).items():
            self.assertEqual(non_ascii_count(text), 0, path.name)


if __name__ == "__main__":
    unittest.main()
