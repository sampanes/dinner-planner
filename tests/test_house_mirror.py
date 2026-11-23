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

    def test_household_codes_round_trip_and_junk_is_refused(self):
        import base64
        code = base64.urlsafe_b64encode(json.dumps({"s": "https://relay.example/", "t": "dp-0123456789abcdef"}).encode()).decode().rstrip("=")
        self.assertEqual(house_notes.house_from_code(code), {"s": "https://relay.example", "t": "dp-0123456789abcdef", "k": None})
        self.assertIsNone(house_notes.house_from_code("hello there"))
        bad = base64.urlsafe_b64encode(json.dumps({"s": "ftp://x", "t": "dp-0123456789abcdef"}).encode()).decode()
        self.assertIsNone(house_notes.house_from_code(bad))


if __name__ == "__main__":
    unittest.main()
