"""Offline tests for the HelloFresh import and the similarity ranking.

    python -m unittest discover -s tests -v

No test touches the network: the page fixtures are small inline strings.
"""

import json
import sys
import unittest
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import find_similar  # noqa: E402
import hellofresh as hf  # noqa: E402
import normalize_source  # noqa: E402
from recipe_text import parse_instructions  # noqa: E402

RECIPE_LD = {
    "@type": "Recipe",
    "@id": "https://www.hellofresh.com/recipes/chicken-sausage-cavatappi-bolognese-61f98622422b687c017a9408#recipe",
    "name": "Chicken Sausage Cavatappi Bolognese with Zucchini & Parmesan",
    "image": "https://img.hellofresh.com/f_auto,fl_lossy,h_640,q_auto,w_1200/hellofresh_s3/image/61f98622422b687c017a9408-0d509f38.jpg",
    "recipeYield": 2,
    "recipeCuisine": "Italian",
    "totalTime": "PT30M",
    "aggregateRating": {"ratingValue": "4.37", "ratingCount": "65755"},
    "recipeIngredient": [
        "1 unit Yellow Onion",
        "1 unit Zucchini",
        "6 ounce Cavatappi Pasta",
        "9 ounce Italian Chicken Sausage Mix",
        "1.5 ounce Tomato Paste",
        "¼ cup Parmesan Cheese",
        "2 teaspoon Cooking Oil",
        " Salt",
        " Pepper",
    ],
    "recipeInstructions": [
        {"@type": "HowToStep", "text": "• Adjust rack to top position and \npreheat oven to 450 degrees. \n• Trim and halve zucchini lengthwise; slice \ncrosswise into 1/2-inch-thick half-moons."},
        {"@type": "HowToStep", "text": "• Roast on top rack, tossing halfway \nthrough, until browned and tender, \n14-16 minutes."},
    ],
}

PAGE_HTML = (
    "<html><head><script type=\"application/ld+json\">"
    + json.dumps({"@type": "BreadcrumbList", "itemListElement": []})
    + "</script><script type=\"application/ld+json\">"
    + json.dumps(RECIPE_LD)
    + "</script></head><body></body></html>"
)


class SitemapTests(unittest.TestCase):
    def test_parse_sitemap(self):
        xml = (
            "<urlset><url><loc>https://www.hellofresh.com/recipes/cavatappi-beef-ragu-61e6fd4580a3915e2e354527</loc>"
            "<lastmod>2024-10-23</lastmod></url><url><loc>https://www.hellofresh.com/recipes/not-a-recipe</loc></url></urlset>"
        )
        entries = hf.parse_sitemap(xml)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["id"], "61e6fd4580a3915e2e354527")
        self.assertEqual(entries[0]["slug"], "cavatappi-beef-ragu")
        self.assertEqual(entries[0]["lastmod"], "2024-10-23")


class PageTests(unittest.TestCase):
    def test_extract_recipe_jsonld_skips_breadcrumbs(self):
        recipe = hf.extract_recipe_jsonld(PAGE_HTML)
        self.assertEqual(recipe["name"], RECIPE_LD["name"])
        self.assertIsNone(hf.extract_recipe_jsonld("<html><body>nothing</body></html>"))

    def test_recipe_id_from(self):
        self.assertEqual(hf.recipe_id_from(RECIPE_LD), "61f98622422b687c017a9408")
        self.assertEqual(hf.recipe_id_from({"image": "https://img.hellofresh.com/x/hellofresh_s3/image/624326ad6cfe6a76cd3ae4c6-b1c92148.jpg"}), "624326ad6cfe6a76cd3ae4c6")


class ConversionTests(unittest.TestCase):
    def test_uniform_image_url(self):
        crop = f"https://img.hellofresh.com/{hf.IMAGE_TRANSFORM}/"
        self.assertEqual(
            hf.uniform_image_url("https://img.hellofresh.com/c_fit,f_auto,fl_lossy,h_1100,q_50,w_2600/hellofresh_s3/image/66707be398f15bd5272cfb67-0b9ef7d4.jpeg"),
            crop + "hellofresh_s3/image/66707be398f15bd5272cfb67-0b9ef7d4.jpeg",
        )
        self.assertEqual(
            hf.uniform_image_url("https://media.hellofresh.com/q_100,w_1920,f_auto,c_limit,fl_lossy/recipes/image/5db88f3a508f707ab355cde4-5ce05c01.jpg"),
            crop + "recipes/image/5db88f3a508f707ab355cde4-5ce05c01.jpg",
        )
        self.assertEqual(
            hf.uniform_image_url("https://images.unsplash.com/photo-1589227365533-cee630bd59bd?ixlib=rb-4.0&q=80&w=1080"),
            "https://images.unsplash.com/photo-1589227365533-cee630bd59bd?auto=format&fit=crop&w=1200&h=800&q=80",
        )
        other = "https://marleyspoon.com/media/recipes/132054/main_photos/large/cheesy.jpg"
        self.assertEqual(hf.uniform_image_url(other), other)
        self.assertEqual(hf.uniform_image_url(""), "")
        once = hf.uniform_image_url(RECIPE_LD["image"])
        self.assertEqual(hf.uniform_image_url(once), once, "idempotent")

    def test_short_name(self):
        self.assertEqual(hf.short_name("Chicken Sausage Cavatappi Bolognese with Zucchini & Parmesan"), "Chicken Sausage Cavatappi Bolognese")
        self.assertEqual(hf.short_name("Chicken Thyme with Zucchini Couscous"), "Chicken Thyme with Zucchini Couscous")
        self.assertEqual(hf.short_name("Pub-Style Shepherd’s Pie"), "Pub-Style Shepherd's Pie")
        self.assertEqual(hf.short_name("Italian Beef Stuffed Peppers 2x the delicious servings!"), "Italian Beef Stuffed Peppers")
        self.assertEqual(hf.short_name("Italian Cheese-Stuffed Burgers Just for the burger lovers"), "Italian Cheese-Stuffed Burgers")
        self.assertEqual(hf.short_name("XL 2x Beef & Zucchini Baked Penne 2x the portions for family dinner or leftovers"), "Beef & Zucchini Baked Penne")
        self.assertEqual(hf.short_name("Zucchini Pomodoro & 2x Beef Penne Bake"), "Zucchini Pomodoro & Beef Penne Bake")
        self.assertEqual(hf.short_name("Beef & Mushroom Shepherd's Pie topped"), "Beef & Mushroom Shepherd's Pie")
        self.assertEqual(hf.short_name("Penne with Beef & Zucchini Ragu plus Parmesan Cheese"), "Penne with Beef & Zucchini Ragu")
        self.assertEqual(hf.short_name("Hidden Veggie Beef Bolognese Note: Blender required"), "Hidden Veggie Beef Bolognese")
        self.assertEqual(hf.short_name("Zucchini Pomodoro & 2x Beef Penne Bake Zucchini Pomodoro with Ricotta & Mozzarella"), "Zucchini Pomodoro & Beef Penne Bake")
        self.assertEqual(hf.short_name("White Cheddar Crunch Beef Burgers Now get 50% more protein"), "White Cheddar Crunch Beef Burgers")
        self.assertEqual(hf.short_name("Beef & Cheese Tostadas"), "Beef & Cheese Tostadas")
        self.assertEqual(hf.short_name("Italian Chicken Sausage Stuffed Peppers Gluten-free friendly or classic-the choice is yours!"), "Italian Chicken Sausage Stuffed Peppers")
        self.assertEqual(hf.short_name("Cheesy Pork Sausage Marinara Includes recyclable aluminum tray"), "Cheesy Pork Sausage Marinara")
        self.assertEqual(hf.short_name("Juicy Cheddar Cheeseburger Fixin's (Ground Beef, Cheddar, Brioche Buns) Great for grilling!"), "Juicy Cheddar Cheeseburger Fixin's")
        for untouched in ("Salmon in a Creamy Dijon Chive Sauce", "Pork Chili 'n' Cheese Stuffed Poblanos", "Lone Star Poblano Mac & Cheese", "Chicken Thyme with Zucchini Couscous", "One-Pan Italian Chicken Orzotto"):
            self.assertEqual(hf.short_name(untouched), untouched)

    def test_parse_hf_ingredient(self):
        self.assertEqual(hf.parse_hf_ingredient("1 unit Yellow Onion"), ("1 unit", "yellow onion"))
        self.assertEqual(hf.parse_hf_ingredient("6 ounce Cavatappi Pasta"), ("6 ounce", "cavatappi pasta"))
        self.assertEqual(hf.parse_hf_ingredient("¼ cup Parmesan Cheese"), ("1/4 cup", "parmesan cheese"))
        self.assertEqual(hf.parse_hf_ingredient("1.5 ounce Tomato Paste"), ("1.5 ounce", "tomato paste"))
        self.assertEqual(hf.parse_hf_ingredient(" Salt"), ("to taste", "salt"))
        self.assertEqual(hf.parse_hf_ingredient("2 teaspoon Cooking Oil"), ("2 teaspoon", "oil"), "vault alias applied")
        self.assertEqual(hf.parse_hf_ingredient("2 Limes"), ("2", "limes"), "number without a unit word")

    def test_scale_amount(self):
        two = Fraction(2)
        self.assertEqual(hf.scale_amount("1 unit", two), "2 unit")
        self.assertEqual(hf.scale_amount("1.5 ounce", two), "3 ounce")
        self.assertEqual(hf.scale_amount("1/4 cup", two), "1/2 cup")
        self.assertEqual(hf.scale_amount("3/4 cup", two), "1 1/2 cup")
        self.assertEqual(hf.scale_amount("1 1/2 cup", two), "3 cup")
        self.assertEqual(hf.scale_amount("to taste", two), "to taste")
        self.assertEqual(hf.scale_amount("1 unit", Fraction(1)), "1 unit")
        self.assertEqual(hf.scale_amount("1 unit", Fraction(3, 2)), "1 1/2 unit")

    def test_steps_to_instructions_round_trip(self):
        text = hf.steps_to_instructions(RECIPE_LD["recipeInstructions"])
        self.assertEqual(
            text,
            "1\n- Adjust rack to top position and preheat oven to 450 degrees.\n"
            "- Trim and halve zucchini lengthwise; slice crosswise into 1/2-inch-thick half-moons.\n\n"
            "2\n- Roast on top rack, tossing halfway through, until browned and tender, 14-16 minutes.",
        )
        steps, notes = parse_instructions(text)
        self.assertEqual([len(step["parts"]) for step in steps], [2, 1])
        self.assertEqual(notes, [])
        self.assertTrue(text.isascii())

    def test_parse_hf_ingredient_newer_card_forms(self):
        self.assertEqual(hf.parse_hf_ingredient("teaspoon (tsp) Salt"), ("to taste", "salt"))
        self.assertEqual(hf.parse_hf_ingredient("teaspoon (tsp) Black Pepper"), ("to taste", "pepper"))
        self.assertEqual(hf.parse_hf_ingredient("1 teaspoon (tsp) Cooking Oil"), ("1 teaspoon", "oil"))
        self.assertEqual(hf.parse_hf_ingredient("½ teaspoon (tsp) Sugar"), ("1/2 teaspoon", "sugar"))
        self.assertEqual(hf.parse_hf_ingredient("1 tablespoon (tbsp) Butter"), ("1 tablespoon", "butter"))
        self.assertEqual(hf.parse_hf_ingredient("4 tablespoon PHILADELPHIA® Cream Cheese"), ("4 tablespoon", "cream cheese"))
        self.assertEqual(hf.parse_hf_ingredient("1 unit Beef Stock Concentrate"), ("1 unit", "stock concentrate"))

    def test_step_bullets_three_card_formats(self):
        wrapped = "• Bring a large pot of salted water to a boil. Once boiling, add\npenne to pot. Cook until al dente,\n9-11 minutes.\n• Meanwhile, wash and dry produce."
        self.assertEqual(
            hf.step_bullets(wrapped),
            ["Bring a large pot of salted water to a boil. Once boiling, add penne to pot. Cook until al dente, 9-11 minutes.", "Meanwhile, wash and dry produce."],
        )
        lines = "Wash and dry produce. \nHalve, peel, and thinly slice onion. \nHeat a drizzle of oil in a large pan. TIP: Lower heat if needed."
        self.assertEqual(
            hf.step_bullets(lines),
            ["Wash and dry produce.", "Halve, peel, and thinly slice onion.", "Heat a drizzle of oil in a large pan. TIP: Lower heat if needed."],
        )
        markup = (
            '<ul><li><p><strong>Wash and dry produce.\n</strong></p></li><li><p>Halve, core, and thinly slice<strong> </strong>'
            '<span><strong><span style="color: rgb(242, 0, 13)">green pepper</span> </strong></span>into strips.</p></li>'
            '<li><p>Reserve<strong> 1 cup pasta cooking water </strong><span style="color: rgb(0, 86, 44)">(1½ cups for 4 servings)</span>, then drain &amp; set aside.</p></li></ul>'
        )
        self.assertEqual(
            hf.step_bullets(markup),
            ["Wash and dry produce.", "Halve, core, and thinly slice green pepper into strips.", "Reserve 1 cup pasta cooking water (1 1/2 cups for 4 servings), then drain & set aside."],
        )
        text = hf.steps_to_instructions([{"@type": "HowToStep", "text": markup}, {"@type": "HowToStep", "text": lines}])
        steps, _notes = parse_instructions(text)
        self.assertEqual([len(step["parts"]) for step in steps], [3, 3])
        self.assertTrue(text.isascii())

    def test_image_at(self):
        full = f"https://img.hellofresh.com/{hf.IMAGE_TRANSFORM}/hellofresh_s3/image/61f98622422b687c017a9408-0d509f38.jpg"
        self.assertEqual(hf.image_at(full, 240, 160), "https://img.hellofresh.com/c_fill,w_240,h_160,f_auto,q_auto/hellofresh_s3/image/61f98622422b687c017a9408-0d509f38.jpg")
        unsplash = "https://images.unsplash.com/photo-1589227365533-cee630bd59bd?auto=format&fit=crop&w=1200&h=800&q=80"
        self.assertEqual(hf.image_at(unsplash, 240, 160), "https://images.unsplash.com/photo-1589227365533-cee630bd59bd?auto=format&fit=crop&w=240&h=160&q=80")
        other = "https://marleyspoon.com/media/recipes/132054/main_photos/large/cheesy.jpg"
        self.assertEqual(hf.image_at(other, 240, 160), other)

    def test_to_source_recipe_scales_to_four(self):
        recipe = hf.to_source_recipe(RECIPE_LD, 99)
        self.assertEqual(recipe["id"], 99)
        self.assertEqual(recipe["name"], "Chicken Sausage Cavatappi Bolognese")
        self.assertEqual(recipe["pinkStar"], 0)
        self.assertEqual(recipe["blueStar"], 0)
        self.assertEqual(list(recipe.keys()), ["id", "name", "image", "instructions", "pinkStar", "blueStar", "ingredients"])
        self.assertEqual(recipe["image"], f"https://img.hellofresh.com/{hf.IMAGE_TRANSFORM}/hellofresh_s3/image/61f98622422b687c017a9408-0d509f38.jpg")
        by_name = {ingredient["name"]: ingredient["amount"] for ingredient in recipe["ingredients"]}
        self.assertEqual(by_name["zucchini"], "2 unit")
        self.assertEqual(by_name["cavatappi pasta"], "12 ounce")
        self.assertEqual(by_name["parmesan cheese"], "1/2 cup")
        self.assertEqual(by_name["salt"], "to taste")
        self.assertTrue(json.dumps(recipe).isascii())


class SimilarityTests(unittest.TestCase):
    VAULT = [
        {"id": 1, "name": "Cheesy Baked Pasta with Meat Sauce", "image": "", "instructions": "1. Bake.", "pinkStar": 5, "blueStar": 5,
         "ingredients": [{"name": n, "amount": "1"} for n in ["rigatoni pasta", "ground beef", "marinara sauce", "mozzarella cheese", "parmesan cheese", "garlic", "salt", "pepper"]]},
        {"id": 2, "name": "Lemony Chicken Grains Salad", "image": "", "instructions": "1. Toss.", "pinkStar": 0, "blueStar": 1,
         "ingredients": [{"name": n, "amount": "1"} for n in ["chicken breast", "spinach", "lemon", "farro", "feta cheese", "salt", "pepper"]]},
    ]

    @staticmethod
    def hf_recipe(name, ingredients, rid="a" * 24):
        return {"@type": "Recipe", "@id": f"https://www.hellofresh.com/recipes/x-{rid}", "name": name,
                "image": f"https://img.hellofresh.com/x/hellofresh_s3/image/{rid}-ff.jpg",
                "recipeIngredient": [f"1 unit {i}" for i in ingredients],
                "aggregateRating": {"ratingValue": "4.5", "ratingCount": "100"}}

    def test_rating_weight(self):
        self.assertEqual(find_similar.rating_weight({"pinkStar": 5, "blueStar": 5}), 1.0)
        self.assertEqual(find_similar.rating_weight({"pinkStar": 0, "blueStar": 0}), 0.0, "freshly imported, not rated yet")
        self.assertAlmostEqual(find_similar.rating_weight({"pinkStar": 0, "blueStar": 1}), -0.8)
        self.assertAlmostEqual(find_similar.rating_weight({"pinkStar": 2, "blueStar": 3}), 0.0)

    def test_ranking_prefers_the_liked_dish_and_drops_what_you_have(self):
        fetched = [
            ({"id": "1" * 24, "url": "u1", "lastmod": "2025"}, self.hf_recipe("Baked Penne with Sausage & Mozzarella", ["penne pasta", "italian pork sausage", "marinara sauce", "mozzarella cheese", "parmesan cheese", "garlic", "salt", "pepper"], "1" * 24)),
            ({"id": "2" * 24, "url": "u2", "lastmod": "2025"}, self.hf_recipe("Citrus Chicken Salad with Farro", ["chicken breast", "spinach", "lemon", "farro", "feta cheese", "cucumber", "salt", "pepper"], "2" * 24)),
            ({"id": "3" * 24, "url": "u3", "lastmod": "2025"}, self.hf_recipe("Cheesy Baked Pasta with Meat Sauce and Spinach", ["rigatoni pasta", "ground beef", "marinara sauce", "mozzarella cheese", "parmesan cheese", "garlic", "salt", "pepper"], "3" * 24)),
            ({"id": "4" * 24, "url": "u4", "lastmod": "2025"}, self.hf_recipe("Baked Penne with Chicken Sausage & Mozzarella", ["penne pasta", "italian chicken sausage", "marinara sauce", "mozzarella cheese", "parmesan cheese", "garlic", "salt", "pepper"], "4" * 24)),
        ]
        candidates, stats = find_similar.score_candidates(self.VAULT, fetched, top=10)
        names = [candidate["name"] for candidate in candidates]
        self.assertEqual(names[0], "Baked Penne with Sausage & Mozzarella")
        self.assertNotIn("Cheesy Baked Pasta with Meat Sauce and Spinach", names, "same dish as the vault's")
        self.assertEqual(stats["already_have"], 1)
        self.assertEqual(stats["variants"], 1, "the chicken-sausage penne folds into the pork one")
        self.assertEqual(len(candidates[0]["variants"]), 1)
        self.assertLess(candidates[-1]["score"], 0, "the salad is pushed away by the 0/1 rating")
        self.assertEqual(candidates[0]["n"], 1)
        self.assertNotIn("_vector", candidates[0])
        self.assertIn("Cheesy Baked Pasta with Meat Sauce (5/5)", candidates[0]["drivers"])
        self.assertTrue(set(candidates[0]["shared"]) & {"marinara sauce", "mozzarella cheese", "parmesan cheese"}, candidates[0]["shared"])
        self.assertNotIn("salt", candidates[0]["shared"][:2], "the why-line leads with the distinctive ingredients")

    def test_internal_variants_and_unrated_recipes_are_dropped(self):
        for name in (
            "[SWAP PORK SAUSAGE TO CHICKEN SAUSAGE] Rigatoni", "20MM Cheesy Beef Tortilla Melt", "BYOP Southwest Beef Nacho Bar",
            "Family 4p/8p Baked Tortelloni", "MA only Compliant Beef Chili-Stuffed Poblanos", "Beef And Pepper Tostadas (D2V)",
            "[PROTEIN DOUBLE CHICKEN SAUSAGE] Penne", "swap-pork-sausage-to-chicken-sausage-rigatoni",
        ):
            self.assertTrue(find_similar.is_internal(name), name)
        for name in ("Pork Sausage & Roasted Pepper Pasta", "one-pan-cheesy-beef-tortilla-melts", "Double Cheddar Burgers", "Family-Style Lasagna"):
            self.assertFalse(find_similar.is_internal(name), name)
        unrated = self.hf_recipe("Creamy Chicken Penne", ["penne pasta", "chicken breast", "parmesan cheese", "marinara sauce"], "5" * 24)
        unrated.pop("aggregateRating")
        fetched = [
            ({"id": "1" * 24, "url": "u1", "lastmod": "2025", "slug": "swap-pork-to-chicken-penne"}, self.hf_recipe("Baked Penne with Sausage", ["penne pasta", "italian pork sausage", "marinara sauce", "mozzarella cheese"], "1" * 24)),
            ({"id": "5" * 24, "url": "u5", "lastmod": "2025", "slug": "creamy-chicken-penne"}, unrated),
            ({"id": "6" * 24, "url": "u6", "lastmod": "2025", "slug": "garlic-penne"}, self.hf_recipe("Garlic Penne with Sausage", ["penne pasta", "italian pork sausage", "garlic", "parmesan cheese"], "6" * 24)),
        ]
        candidates, stats = find_similar.score_candidates(self.VAULT, fetched, top=10)
        self.assertEqual([candidate["name"] for candidate in candidates], ["Garlic Penne with Sausage"])
        self.assertEqual((stats["internal"], stats["unrated"]), (1, 1))
        candidates, _stats = find_similar.score_candidates(self.VAULT, fetched, top=10, include_unrated=True)
        self.assertEqual(len(candidates), 2)

    def test_same_dish_by_name_prefix(self):
        vault_names = ["garlic butter shrimp scampi", "beef bulgogi meatballs"]
        self.assertTrue(find_similar.same_dish("Garlic Butter Shrimp Scampi over Spaghetti", vault_names))
        self.assertTrue(find_similar.same_dish("Beef Bulgogi", vault_names))
        self.assertFalse(find_similar.same_dish("Garlic Butter Steak", vault_names))
        self.assertFalse(find_similar.same_dish("Shrimp Scampi", vault_names))

    def test_prefilter_uses_slug_words_and_year(self):
        vocabulary = find_similar.slug_vocabulary(self.VAULT)
        self.assertGreater(vocabulary["rigatoni"], 0)
        self.assertLess(vocabulary["farro"], 0)
        self.assertNotIn("pepper", vocabulary, "the seasoning on every card is not a preference")
        self.assertNotIn("salt", vocabulary)
        entries = [
            {"id": "a" * 24, "url": "u", "slug": "cheesy-rigatoni-bake", "lastmod": "2025-01-01"},
            {"id": "b" * 24, "url": "u", "slug": "cheesy-rigatoni-bake", "lastmod": "2015-01-01"},
            {"id": "c" * 24, "url": "u", "slug": "farro-salad", "lastmod": "2025-01-01"},
            {"id": "d" * 24, "url": "u", "slug": "mozzarella-penne", "lastmod": "2025-01-01"},
        ]
        chosen = find_similar.prefilter(entries, vocabulary, {"d" * 24}, min_year=2021, limit=10)
        self.assertEqual([entry["id"] for entry in chosen], ["a" * 24])

    def test_render_page_is_self_contained_html(self):
        fetched = [({"id": "1" * 24, "url": "https://www.hellofresh.com/recipes/x", "lastmod": "2025"},
                    self.hf_recipe("Baked Penne with Sausage & Mozzarella", ["penne pasta", "italian pork sausage", "marinara sauce", "mozzarella cheese"], "1" * 24))]
        candidates, stats = find_similar.score_candidates(self.VAULT, fetched, top=5)
        page = find_similar.render_page(self.VAULT, candidates, stats, "2026-11-04 12:00")
        self.assertIn("<!DOCTYPE html>", page)
        self.assertIn("Baked Penne with Sausage", page)
        self.assertIn(find_similar.PAGE_IMAGE_TRANSFORM, page)
        self.assertIn("import_hellofresh.py 1", page)
        self.assertIn("Cheesy Baked Pasta with Meat Sauce <span>5/5</span>", page)


class SourceInvariantTests(unittest.TestCase):
    def test_source_is_normalized(self):
        recipes = json.loads(normalize_source.SOURCE_PATH.read_text(encoding="utf-8"))
        for recipe in recipes:
            self.assertEqual(normalize_source.normalize_recipe(recipe), recipe, recipe["name"])

    def test_source_photos_use_one_crop(self):
        recipes = json.loads(normalize_source.SOURCE_PATH.read_text(encoding="utf-8"))
        hellofresh = [recipe["image"] for recipe in recipes if "hellofresh.com" in recipe["image"]]
        self.assertTrue(hellofresh)
        for url in hellofresh:
            self.assertTrue(url.startswith(f"https://img.hellofresh.com/{hf.IMAGE_TRANSFORM}/"), url)


if __name__ == "__main__":
    unittest.main()
