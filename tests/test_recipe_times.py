"""Recipe times: reading them from a page, and carrying them into the runtime data."""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_runtime_data as build  # noqa: E402
import recipe_times as rt  # noqa: E402


class ReadTimeTests(unittest.TestCase):
    def test_a_duration_is_read_as_minutes(self):
        self.assertEqual(rt.minutes_from_iso("PT35M"), 35)
        self.assertEqual(rt.minutes_from_iso("PT1H10M"), 70)
        self.assertEqual(rt.minutes_from_iso("PT2H"), 120)
        self.assertEqual(rt.minutes_from_iso(" PT20M "), 20)

    def test_anything_that_is_not_a_dinner_length_is_refused(self):
        for bad in ("", "35", "PT", "P", "PT0M", "PT2M", "PT9H", "P3D", None, 35):
            self.assertIsNone(rt.minutes_from_iso(bad), bad)

    def test_the_total_is_used_and_the_parts_only_when_there_is_no_total(self):
        self.assertEqual(rt.minutes_from_recipe({"totalTime": "PT40M", "prepTime": "PT10M"}), 40)
        self.assertEqual(rt.minutes_from_recipe({"prepTime": "PT10M", "cookTime": "PT25M"}), 35)
        self.assertIsNone(rt.minutes_from_recipe({"name": "no times"}))
        self.assertIsNone(rt.minutes_from_recipe(None))

    def test_only_whole_minutes_in_range_are_kept_from_the_file(self):
        raw = {"a": 30, "b": "30", "c": 0, "d": 999, "e": True, "f": 12.5, 7: 30}
        self.assertEqual(rt.valid_times(raw), {"a": 30})
        self.assertEqual(rt.valid_times([1, 2]), {})


class BuildTests(unittest.TestCase):
    def test_the_build_copies_a_time_into_the_runtime_recipe(self):
        source = build.load_source()[:2]
        slugs = [build.build_runtime_recipe(recipe)["slug"] for recipe in source]
        outputs = build.build_outputs(source, {}, {slugs[0]: 35, slugs[1]: "soon"})
        runtime = json.loads(outputs[build.RUNTIME_DIR / "recipes.runtime.json"])
        self.assertEqual(runtime[0]["minutes"], 35)
        self.assertNotIn("minutes", runtime[1], "a time that is not a number is left out")

    def test_every_recipe_has_a_time_and_none_is_for_a_recipe_that_is_gone(self):
        slugs = {build.build_runtime_recipe(recipe)["slug"] for recipe in build.load_source()}
        times = build.load_recipe_times()
        self.assertEqual(rt.valid_times(times), times, "data/source/recipe_times.json holds only whole minutes")
        self.assertEqual(set(times) - slugs, set(), "times for recipes that no longer exist")
        self.assertEqual(slugs - set(times), set(), "run python scripts/recipe_times.py, or type the minutes in")


if __name__ == "__main__":
    unittest.main()
