"""apps/dinner_planner/tool/signing_setup.py and the workflow that uses its key."""

import base64
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "apps" / "dinner_planner" / "tool"))

import signing_setup  # noqa: E402

WORKFLOW = (ROOT / ".github" / "workflows" / "app.yml").read_text(encoding="utf-8")
PUBSPEC = (ROOT / "apps" / "dinner_planner" / "pubspec.yaml").read_text(encoding="utf-8")


class SigningSetupTests(unittest.TestCase):
    def test_the_repository_is_read_from_either_kind_of_remote(self):
        self.assertEqual(signing_setup.repo_of("https://github.com/someone/dinner-planner.git\n"), ("someone", "dinner-planner"))
        self.assertEqual(signing_setup.repo_of("git@github.com:someone/dinner-planner.git"), ("someone", "dinner-planner"))
        self.assertEqual(signing_setup.repo_of("https://github.com/someone/dinner-planner"), ("someone", "dinner-planner"))
        self.assertIsNone(signing_setup.repo_of("https://gitlab.com/someone/dinner-planner.git"))

    def test_the_version_is_the_part_before_the_build_number(self):
        self.assertEqual(signing_setup.app_version("name: x\nversion: 0.8.0+11\n"), "0.8.0")
        self.assertIsNone(signing_setup.app_version("name: x\n"))
        self.assertRegex(signing_setup.app_version(PUBSPEC) or "", r"^\d+\.\d+\.\d+$")

    def test_the_workflow_reads_the_version_the_same_way(self):
        pattern = re.search(r"sed -n 's/(\^version: \*\\\(\[0-9\]\[0-9\.\]\*\\\)\.\*)/\\1/p' pubspec\.yaml", WORKFLOW)
        self.assertIsNotNone(pattern, "the release job's sed line changed: keep it and app_version() in step")
        self.assertIn(f"version: {signing_setup.app_version(PUBSPEC)}+", PUBSPEC)

    def test_the_four_secrets_are_the_ones_the_workflow_asks_for(self):
        values = signing_setup.secret_values(b"\x00\x01key", "pw")
        self.assertEqual(sorted(values), sorted(signing_setup.SECRET_NAMES))
        for name in signing_setup.SECRET_NAMES:
            self.assertIn(f"secrets.{name}", WORKFLOW)
        self.assertEqual(base64.b64decode(values["ANDROID_KEYSTORE_BASE64"]), b"\x00\x01key")
        self.assertEqual(values["ANDROID_KEY_ALIAS"], signing_setup.ALIAS)

    def test_the_local_key_file_names_the_same_key(self):
        text = signing_setup.key_properties(Path("C:/somewhere/private/keys/dinner-planner.jks"), "pw")
        self.assertIn("storeFile=C:/somewhere/private/keys/dinner-planner.jks\n", text)
        self.assertNotIn("\\", text, "a backslash is an escape in a properties file")
        self.assertIn(f"keyAlias={signing_setup.ALIAS}\n", text)
        self.assertEqual(signing_setup.password_in("note\nalias: a\npassword: s3-cr_et\n"), "s3-cr_et")
        self.assertIsNone(signing_setup.password_in("nothing here"))

    def test_the_key_and_its_note_live_where_git_does_not_look(self):
        ignored = (ROOT / ".gitignore").read_text(encoding="utf-8").split()
        self.assertIn("private/", ignored)
        self.assertEqual(signing_setup.KEYSTORE.parent, ROOT / "private" / "keys")
        android_ignored = (ROOT / "apps" / "dinner_planner" / "android" / ".gitignore").read_text(encoding="utf-8").split()
        self.assertIn("key.properties", android_ignored)

    def test_a_release_is_only_skipped_never_failed_while_there_is_no_key(self):
        self.assertIn("if: github.event_name != 'pull_request'", WORKFLOW)
        self.assertIn('echo "go=false" >> "$GITHUB_OUTPUT"', WORKFLOW)
        self.assertNotIn("startsWith(github.ref, 'refs/tags/app-v')", WORKFLOW)


if __name__ == "__main__":
    unittest.main()
