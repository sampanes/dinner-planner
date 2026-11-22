"""Step photos: reading them from a page, matching pages, and attaching them in the build."""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_runtime_data as build  # noqa: E402
import step_photos as sp  # noqa: E402


def page_with(steps):
    data = {"props": {"pageProps": {"recipe": {"steps": steps}}}}
    return f'<html><script id="__NEXT_DATA__" type="application/json">{json.dumps(data)}</script></html>'


class ReadPageTests(unittest.TestCase):
    def test_photos_come_out_in_step_order_with_gaps_kept(self):
        page = page_with([
            {"index": 2, "images": []},
            {"index": 1, "images": [{"path": "/abc/step-1.jpeg"}]},
            {"index": 3, "images": [{"path": "/abc/step-3.jpeg"}]},
        ])
        photos = sp.step_photos_from_html(page)
        self.assertEqual(len(photos), 3)
        self.assertTrue(photos[0].endswith("/hellofresh_s3/abc/step-1.jpeg"))
        self.assertEqual(photos[1], "")
        self.assertTrue(photos[2].startswith("https://img.hellofresh.com/c_fill,"))

    def test_page_without_steps_gives_none(self):
        self.assertIsNone(sp.step_photos_from_html("<html><p>no data</p></html>"))


class MatchTests(unittest.TestCase):
    sitemap = [
        {"url": "u-old", "id": "a" * 24, "slug": "zucchini-and-tomato-calzones", "lastmod": "2024-01-01"},
        {"url": "u-new", "id": "b" * 24, "slug": "zucchini-and-tomato-calzones", "lastmod": "2026-01-01"},
        {"url": "u-photo", "id": "c" * 24, "slug": "something-else", "lastmod": "2025-01-01"},
    ]

    def test_ampersand_matches_and_newest_first(self):
        found = sp.candidates_for({"name": "Zucchini & Tomato Calzones", "image": ""}, self.sitemap)
        self.assertEqual([c["url"] for c in found], ["u-new", "u-old"])

    def test_photo_id_beats_name(self):
        recipe = {"name": "Zucchini & Tomato Calzones", "image": f"https://img.hellofresh.com/x/{'c' * 24}-1.jpg"}
        self.assertEqual(sp.candidates_for(recipe, self.sitemap)[0]["url"], "u-photo")


class AttachTests(unittest.TestCase):
    def recipe(self, source_steps):
        return {"steps": [{"sourceStep": n} for n in source_steps]}

    def test_photo_lands_on_every_part_of_its_step(self):
        recipe = self.recipe([1, 1, 2])
        build.attach_step_photos(recipe, ["p1", "p2"])
        self.assertEqual([s.get("photo") for s in recipe["steps"]], ["p1", "p1", "p2"])

    def test_count_mismatch_attaches_nothing(self):
        recipe = self.recipe([1, 2, 3])
        build.attach_step_photos(recipe, ["p1", "p2"])
        self.assertFalse(any("photo" in s for s in recipe["steps"]))

    def test_blank_photo_leaves_the_step_bare(self):
        recipe = self.recipe([1, 2])
        build.attach_step_photos(recipe, ["", "p2"])
        self.assertNotIn("photo", recipe["steps"][0])

    def test_committed_photo_file_is_https_only(self):
        for slug, entry in build.load_step_photos().items():
            for url in entry["photos"]:
                self.assertTrue(url == "" or url.startswith("https://img.hellofresh.com/"), slug)


if __name__ == "__main__":
    unittest.main()
