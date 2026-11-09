"""Tests for the kitchen picker tags and for folding device changes into the repo.

    python -m unittest discover -s tests -v
"""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import pull_changes as pull  # noqa: E402
from recipe_tags import haves, haves_catalog, moods, proteins  # noqa: E402


def ing(*names):
    return [{"canonicalName": n} for n in names]


class TagTests(unittest.TestCase):
    def test_stock_concentrate_is_not_a_protein(self):
        self.assertEqual(proteins("Mushroom Ravioli", ing("ravioli", "chicken stock concentrate")), ["Veggie"])
        self.assertEqual(proteins("Beef Chili Bar", ing("ground beef", "beef stock concentrate")), ["Beef"])

    def test_moods_come_in_a_fixed_order(self):
        self.assertEqual(moods("Spicy Beef Taco Rigatoni", ing("ground beef", "rigatoni pasta", "hot sauce")),
                         ["Tex-Mex", "Pasta", "Spicy"])
        self.assertEqual(moods("Beef & Mushroom Shepherd's Pie", ing("ground beef", "potatoes")), [])

    def test_three_cheeses_make_it_cheesy(self):
        self.assertIn("Cheesy", moods("Beef Bake", ing("mozzarella cheese", "parmesan cheese", "ricotta cheese")))
        self.assertNotIn("Cheesy", moods("Beef Bake", ing("mozzarella cheese", "parmesan cheese")))

    def test_haves_skip_lookalikes(self):
        self.assertEqual(haves(ing("garlic powder", "tomato paste", "roma tomato", "flour tortillas", "tortilla chips")),
                         ["tomatoes", "tortillas", "tortilla chips"])

    def test_catalog_drops_one_off_items(self):
        recipes = [{"haves": ["zucchini", "salmon"]}, {"haves": ["zucchini"]}]
        self.assertEqual(haves_catalog(recipes), [{"label": "zucchini", "group": "Produce", "count": 2}])


def message(event, extra=""):
    return json.dumps({"event": "message", "message": f"Pink gave it 4 stars{extra}\n\n{pull.MARK}{json.dumps(event)}"})


class PullTests(unittest.TestCase):
    def setUp(self):
        self.recipes = [{"id": 1, "name": "Beef Chili Bar", "pinkStar": 0, "blueStar": 3},
                        {"id": 2, "name": "Italian Beef Melts", "pinkStar": 2, "blueStar": 2}]
        self.log = {"plan": None, "cooked": [], "rated": {}}

    def run_lines(self, lines):
        return pull.apply_events(pull.parse_events(lines), self.recipes, self.log)

    def test_rating_lands_once_and_newest_wins(self):
        new = {"k": "rate", "id": "a", "at": "2026-11-09T18:00:00Z", "slug": "beef-chili-bar", "who": "pink", "stars": 5}
        old = {"k": "rate", "id": "b", "at": "2026-11-09T17:00:00Z", "slug": "beef-chili-bar", "who": "pink", "stars": 1}
        changes = self.run_lines([message(new), message(old)])
        self.assertEqual(self.recipes[0]["pinkStar"], 5)
        self.assertEqual(changes[-1], "pink rated Beef Chili Bar: 1 -> 5")
        self.assertEqual(self.run_lines([message(new), message(old)]), [])
        self.assertEqual(self.recipes[0]["pinkStar"], 5)

    def test_cooked_dedupes_by_id_and_plan_keeps_newest(self):
        cooked = {"k": "cooked", "id": "c1", "at": "2026-11-09T19:00:00Z", "slug": "italian-beef-melts"}
        plan = {"k": "plan", "id": "p1", "at": "2026-11-09T10:00:00Z", "slugs": ["beef-chili-bar", "italian-beef-melts"]}
        self.run_lines([message(cooked), message(cooked), message(plan)])
        self.assertEqual([c["id"] for c in self.log["cooked"]], ["c1"])
        self.assertEqual(self.log["plan"]["slugs"], ["beef-chili-bar", "italian-beef-melts"])
        older = dict(plan, id="p0", at="2026-11-08T10:00:00Z", slugs=["beef-chili-bar"])
        self.run_lines([message(older)])
        self.assertEqual(self.log["plan"]["id"], "p1")

    def test_junk_is_skipped_not_applied(self):
        lines = ["not json", json.dumps({"event": "open"}),
                 message({"k": "rate", "id": "x", "at": "2026-11-09T18:00:00Z", "slug": "nope", "who": "pink", "stars": 4}),
                 message({"k": "rate", "id": "y", "at": "2026-11-09T18:00:00Z", "slug": "beef-chili-bar", "who": "mom", "stars": 4}),
                 message({"k": "rate", "id": "z", "at": "yesterday", "slug": "beef-chili-bar", "who": "pink", "stars": 4})]
        changes = self.run_lines(lines)
        self.assertEqual(len(changes), 3)
        self.assertTrue(all(c.startswith("skipped") for c in changes))
        self.assertEqual(self.recipes[0]["pinkStar"], 0)


class CommittedFilesTests(unittest.TestCase):
    def test_config_and_log_parse(self):
        config = json.loads(pull.CONFIG_PATH.read_text(encoding="utf-8"))
        self.assertTrue(config["ntfyTopic"].startswith("dinner-planner-"))
        self.assertEqual(set(config["people"]), {"pink", "blue"})
        log = json.loads(pull.LOG_PATH.read_text(encoding="utf-8"))
        self.assertEqual(set(log), {"plan", "cooked", "rated"})


if __name__ == "__main__":
    unittest.main()
