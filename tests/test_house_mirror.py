"""house.js mirrors the phone app's sync rules; these tests catch the two drifting apart."""

import json
import re
import shutil
import subprocess
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import house_notes  # noqa: E402

HOUSE_JS = (ROOT / "house.js").read_text(encoding="utf-8")
SYNC_CORE = (ROOT / "apps" / "dinner_planner" / "lib" / "core" / "sync_core.dart").read_text(encoding="utf-8")

# Entries and time fed to the Dart SyncCore on 2026-11-22; it answered with DART_DIGEST.
ENTRIES = {
    "meal/2026-11-22": ["garlicky-shrimp-couscous-bowls", "2026-11-20T01:02:03.004Z", "phoneA"],
    "cook/2026-11-22": ["blue", "2026-11-20T01:02:04.000Z", "phoneB"],
    "name/pink": ["Pi \"nk\"\nx", "2026-11-01T00:00:00.000Z", "phoneA"],
    "meal/2026-10-01": ["old-one", "2026-09-30T00:00:00.000Z", "phoneA"],
    "meal/2026-11-23": [None, "2026-11-21T00:00:00.000Z", "phoneB"],
}
NOW_MS = 1795370400000  # 2026-11-22T18:00:00Z
DART_DIGEST = "6153fe5b4764e408"

# What the Dart stepId (lib/core/plan.dart) answers for these step texts.
STEP_IDS = {
    "": "811c9dc5",
    "a": "e40c292c",
    "Brown the beef in a large pot, 5-7 minutes.": "8b807cd6",
    "Sauté the onion.": "9763783c",
}


def dart_const(pattern: str) -> str:
    match = re.search(pattern, SYNC_CORE)
    if not match:
        raise AssertionError(f"not found in sync_core.dart: {pattern}")
    return match.group(1)


class HouseMirrorTests(unittest.TestCase):
    def test_wire_mark_matches(self):
        self.assertEqual(dart_const(r"const String wireMark = '([^']*)';"), "dp2 ")
        self.assertIn("const WIRE = 'dp2 ';", HOUSE_JS)

    def test_day_windows_and_clock_slack_match(self):
        self.assertIn(f"const DIGEST_DAYS = {dart_const(r'const int digestDays = (\d+);')};", HOUSE_JS)
        self.assertIn(f"const KEEP_DAYS = {dart_const(r'const int keepDays = (\d+);')};", HOUSE_JS)
        minutes = dart_const(r"const Duration clockSlack = Duration\(minutes: (\d+)\);")
        self.assertIn(f"const CLOCK_SLACK_MS = {minutes} * 60e3;", HOUSE_JS)

    @unittest.skipUnless(shutil.which("node"), "node is not installed")
    def test_digest_matches_the_dart_one(self):
        script = (
            "global.localStorage = undefined;"
            "const vm = require('vm');"
            "vm.runInThisContext(require('fs').readFileSync(process.argv[1], 'utf8') + ';globalThis.House = House;');"
            f"House.digestOf({json.dumps(ENTRIES)}, {NOW_MS}).then(d => console.log(d));"
        )
        out = subprocess.run(["node", "-e", script, str(ROOT / "house.js")], capture_output=True, text=True, timeout=60)
        self.assertEqual(out.stdout.strip(), DART_DIGEST, out.stderr)

    @unittest.skipUnless(shutil.which("node"), "node is not installed")
    def test_step_notes_read_the_same_as_on_the_phones(self):
        step = "Brown the beef in a large pot, 5-7 minutes."
        entries = {
            "note/beef-chili": ["Double it", "2026-11-22T10:00:00.000Z", "a"],
            "note/beef-chili/deadbeef": ["Old words\nStill true", "2026-11-22T10:02:00.000Z", "b"],
            "note/beef-chili/8b807cd6": [step + "\nGarlic salt goes in here", "2026-11-22T10:01:00.000Z", "a"],
            "note/beef-chili/00000000": [None, "2026-11-22T10:03:00.000Z", "b"],
            "note/beef-chili-bar/8b807cd6": ["x\nNot this recipe", "2026-11-22T10:03:00.000Z", "b"],
        }
        saved = json.dumps({"house": {"s": "https://relay.example", "t": "dp-0123456789abcdef", "k": None}, "dev": "show-1", "entries": entries})
        script = (
            f"global.localStorage = {{ getItem: () => {json.dumps(saved)}, setItem() {{}}, removeItem() {{}} }};"
            "const vm = require('vm');"
            "vm.runInThisContext(require('fs').readFileSync(process.argv[1], 'utf8') + ';globalThis.House = House;');"
            f"console.log(JSON.stringify({{ ids: {json.dumps(list(STEP_IDS))}.map(House.stepId), notes: House.notes('beef-chili') }}));"
        )
        out = subprocess.run(["node", "-e", script, str(ROOT / "house.js")], capture_output=True, text=True, timeout=60, encoding="utf-8")
        got = json.loads(out.stdout or "null")
        self.assertIsNotNone(got, out.stderr)
        self.assertEqual(got["ids"], list(STEP_IDS.values()))
        self.assertEqual(got["notes"], {"whole": "Double it", "steps": [
            {"id": "8b807cd6", "anchor": step, "text": "Garlic salt goes in here"},
            {"id": "deadbeef", "anchor": "Old words", "text": "Still true"},
        ]})


class HouseNotesScriptTests(unittest.TestCase):
    """scripts/house_notes.py: the same rules, in Python."""

    def test_digest_matches_the_dart_one(self):
        self.assertEqual(house_notes.digest_of(ENTRIES, NOW_MS), DART_DIGEST)

    def test_constants_match(self):
        self.assertEqual(house_notes.WIRE, dart_const(r"const String wireMark = '([^']*)';"))
        self.assertEqual(house_notes.DIGEST_DAYS, int(dart_const(r"const int digestDays = (\d+);")))
        self.assertEqual(house_notes.KEEP_DAYS, int(dart_const(r"const int keepDays = (\d+);")))
        minutes = int(dart_const(r"const Duration clockSlack = Duration\(minutes: (\d+)\);"))
        self.assertEqual(house_notes.CLOCK_SLACK.total_seconds(), minutes * 60)

    def test_listens_under_the_listener_prefix(self):
        prefix = dart_const(r"const String listenerPrefix = '([^']*)';")
        self.assertIn(f'"dev": f"{prefix}', (ROOT / "scripts" / "house_notes.py").read_text(encoding="utf-8"))

    def test_newest_write_wins_and_notes_are_listed(self):
        state = {"dev": "show-pc-1", "entries": {}}
        now = datetime(2026, 11, 22, 18, tzinfo=timezone.utc)

        def line(dev, *entries):
            return "dp2 " + json.dumps({"d": dev, "g": "x", "s": [list(e) for e in entries]})

        self.assertTrue(house_notes.receive(state, line("a", ("note/beef-chili", "Add cheese", "2026-11-22T10:00:00.000Z", "a")), now))
        self.assertFalse(house_notes.receive(state, line("b", ("note/beef-chili", "older", "2026-11-22T09:00:00.000Z", "b")), now))
        self.assertFalse(house_notes.receive(state, line("b", ("note/beef-chili", "from the future", "2026-11-23T10:00:00.000Z", "b")), now))
        self.assertFalse(house_notes.receive(state, line("show-pc-1", ("note/x", "mine", "2026-11-22T10:00:00.000Z", "show-pc-1")), now))
        house_notes.receive(state, line("b", ("note/tacos", None, "2026-11-22T11:00:00.000Z", "b")), now)
        self.assertEqual(house_notes.notes(state), {"beef-chili": "Add cheese"})

    def test_a_step_is_named_the_same_way_everywhere(self):
        # The same four as apps/dinner_planner/test/session_test.dart.
        for text, expected in STEP_IDS.items():
            self.assertEqual(house_notes.step_id(text), expected)

    def test_notes_are_listed_with_the_step_they_are_on(self):
        step = "Brown the beef in a large pot, 5-7 minutes."
        recipes = {"beef-chili": {"slug": "beef-chili", "displayName": "Beef Chili", "steps": [
            {"sourceStep": 1, "displayText": "Dice the onion."},
            {"sourceStep": 2, "displayText": step}]}}
        state = {"dev": "show-pc-1", "entries": {
            "note/beef-chili": ["Double it", "2026-11-22T10:00:00.000Z", "a"],
            "note/beef-chili/8b807cd6": [step + "\nGarlic salt goes in here", "2026-11-22T10:01:00.000Z", "a"],
            "note/beef-chili/deadbeef": ["Old words\nStill true", "2026-11-22T10:02:00.000Z", "b"],
            "note/beef-chili/00000000": [None, "2026-11-22T10:03:00.000Z", "b"],
            "note/tacos": ["More lime", "2026-11-22T10:04:00.000Z", "b"],
            "meal/2026-11-22": ["beef-chili", "2026-11-22T10:00:00.000Z", "a"],
        }}
        rows = house_notes.note_rows(state, recipes)
        self.assertEqual([(r["slug"], r["step"], r["loose"], r["note"]) for r in rows], [
            ("beef-chili", None, False, "Double it"),
            ("beef-chili", 2, False, "Garlic salt goes in here"),
            ("beef-chili", None, True, "Still true"),
            ("tacos", None, False, "More lime"),
        ])
        self.assertEqual((rows[1]["of"], rows[1]["cardStep"], rows[1]["stepText"]), (2, 2, step))
        self.assertEqual(rows[2]["anchor"], "Old words")
        self.assertEqual(house_notes.notes(state), {"beef-chili": "Double it", "tacos": "More lime"})
        self.assertIn("step 2 of 2 (card step 2)", house_notes.describe(rows[1]))

    def test_done_clears_a_note_so_that_the_phones_take_it(self):
        state = {"dev": "show-pc-1", "entries": {
            "note/beef-chili": ["Double it", "2026-11-22T10:00:00.000Z", "a"],
            "note/beef-chili/8b807cd6": ["Brown\nGarlic salt", "2026-11-23T09:00:00.000Z", "a"],
            "note/tacos": ["More lime", "2026-11-22T10:04:00.000Z", "b"],
            "note/tacos/11111111": ["x\nLess salt", "2026-11-22T10:05:00.000Z", "b"],
        }}
        # This computer's clock is behind the phone that wrote the newest note.
        now = datetime(2026, 11, 23, 8, tzinfo=timezone.utc)
        cleared = house_notes.mark_done(state, ["beef-chili", "note/tacos/11111111"], now)
        self.assertEqual(cleared, ["note/beef-chili", "note/beef-chili/8b807cd6", "note/tacos/11111111"])
        self.assertEqual(state["entries"]["note/beef-chili"], [None, "2026-11-23T08:00:00.000Z", "show-pc-1"])
        self.assertEqual(state["entries"]["note/beef-chili/8b807cd6"], [None, "2026-11-23T09:00:00.001Z", "show-pc-1"],
                         "dated after the note it clears, or newest-wins would keep the note")
        self.assertEqual(state["entries"]["note/tacos"][0], "More lime")
        self.assertEqual(house_notes.mark_done(state, ["beef-chili"], now), [], "already cleared")
        # What it wrote goes out again with each check-in, for two weeks.
        sent = house_notes.own_writes(state, now)
        self.assertEqual([e[0] for e in sent], cleared)
        self.assertTrue(all(house_notes.entry_from_wire(e) for e in sent), "in the form the phones accept")
        self.assertEqual(house_notes.own_writes(state, datetime(2026, 12, 20, tzinfo=timezone.utc)), [])
        self.assertEqual(house_notes.note_rows(state, {})[0]["slug"], "tacos")

    def test_recipes_asked_for_from_a_phone_are_listed_and_cleared_by_their_own_key(self):
        state = {"dev": "show-pc-1", "entries": {
            "ask/2222bbbb": ["https://example.com/second", "2026-11-23T09:00:00.000Z", "a"],
            "ask/1111aaaa": ["https://example.com/first", "2026-11-22T09:00:00.000Z", "b"],
            "ask/3333cccc": [None, "2026-11-22T09:00:00.000Z", "b"],
            "note/1111aaaa": ["A note on a recipe that happens to share the id", "2026-11-22T10:00:00.000Z", "a"],
        }}
        self.assertEqual([(a["key"], a["link"]) for a in house_notes.asked_for(state)],
                         [("ask/1111aaaa", "https://example.com/first"), ("ask/2222bbbb", "https://example.com/second")])
        now = datetime(2026, 11, 24, 8, tzinfo=timezone.utc)
        self.assertEqual(house_notes.mark_done(state, ["1111aaaa"], now), ["note/1111aaaa"], "a bare id is a recipe's notes, never a request")
        self.assertEqual(house_notes.mark_done(state, ["ask/1111aaaa"], now), ["ask/1111aaaa"])
        self.assertEqual([a["key"] for a in house_notes.asked_for(state)], ["ask/2222bbbb"])
        # The phone app keeps them under the same key.
        self.assertIn("String askKey(String id) => 'ask/$id';", (ROOT / "apps" / "dinner_planner" / "lib" / "core" / "glance.dart").read_text(encoding="utf-8"))

    def test_household_codes_round_trip_and_junk_is_refused(self):
        import base64
        code = base64.urlsafe_b64encode(json.dumps({"s": "https://relay.example/", "t": "dp-0123456789abcdef"}).encode()).decode().rstrip("=")
        self.assertEqual(house_notes.house_from_code(code), {"s": "https://relay.example", "t": "dp-0123456789abcdef", "k": None})
        self.assertIsNone(house_notes.house_from_code("hello there"))
        bad = base64.urlsafe_b64encode(json.dumps({"s": "ftp://x", "t": "dp-0123456789abcdef"}).encode()).decode()
        self.assertIsNone(house_notes.house_from_code(bad))


if __name__ == "__main__":
    unittest.main()
