"""The phone app's Android side, where a slip would only show on a phone:
the link the kitchen page opens, the reminder buttons, and the backup."""

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps" / "dinner_planner"
MAIN = APP / "android" / "app" / "src" / "main"
ANDROID = "{http://schemas.android.com/apk/res/android}"

MANIFEST = ET.parse(MAIN / "AndroidManifest.xml").getroot()
KITCHEN_JS = (ROOT / "kitchen.js").read_text(encoding="utf-8")


def read(path: str) -> str:
    return (APP / path).read_text(encoding="utf-8")


class NoteLinkTests(unittest.TestCase):
    """kitchen.js writes the link, Android routes it, the app reads it."""

    def test_the_page_opens_a_link_the_app_is_registered_for(self):
        link = re.search(r"`(\w+)://(\w+)/(\w+)\?slug=\$\{encodeURIComponent\(slug\)\}&step=\$\{House\.stepId\(stepText\)\}`", KITCHEN_JS)
        self.assertIsNotNone(link, "kitchen.js noteLink changed: keep it and the manifest in step")
        scheme, host, path = link.groups()
        filters = [d.attrib for f in MANIFEST.iter("intent-filter") for d in f.iter("data")]
        self.assertIn({f"{ANDROID}scheme": scheme, f"{ANDROID}host": host}, filters)
        self.assertEqual(path, "note")
        self.assertIn("link.path.endsWith('/note')", read("lib/app_model.dart"))
        self.assertIn("queryParameters['slug']", read("lib/app_model.dart"))
        self.assertIn("queryParameters['step']", read("lib/app_model.dart"))

    def test_a_browser_may_follow_that_link(self):
        for f in MANIFEST.iter("intent-filter"):
            if any(d.get(f"{ANDROID}scheme") == "dinnerplanner" for d in f.iter("data")):
                names = {c.get(f"{ANDROID}name") for c in f.iter("category")}
                self.assertEqual(names, {"android.intent.category.DEFAULT", "android.intent.category.BROWSABLE"})
                self.assertEqual([a.get(f"{ANDROID}name") for a in f.iter("action")], ["android.intent.action.VIEW"])
                return
        self.fail("no intent filter for the note link")

    def test_the_page_only_offers_the_link_when_the_app_opened_it(self):
        self.assertIn("kitchen.html?app=1#/r/", read("lib/data/recipes.dart"))
        self.assertRegex(KITCHEN_JS, r"/\[\?&\]app=1\(&\|\$\)/\.test\(location\.search\)")
        self.assertIn("fromApp ? h('a', { class: 'note-link'", KITCHEN_JS)


class ReminderTests(unittest.TestCase):
    def test_reminder_buttons_have_the_receiver_that_carries_their_taps(self):
        receivers = {r.get(f"{ANDROID}name"): r for r in MANIFEST.iter("receiver")}
        action = receivers.get("com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver")
        self.assertIsNotNone(action)
        self.assertEqual(action.get(f"{ANDROID}exported"), "false")


class BackupTests(unittest.TestCase):
    def test_android_backs_up_what_the_app_remembers(self):
        app = MANIFEST.find("application")
        self.assertEqual(app.get(f"{ANDROID}allowBackup"), "true")
        self.assertEqual(app.get(f"{ANDROID}fullBackupContent"), "@xml/backup_rules")
        self.assertEqual(app.get(f"{ANDROID}dataExtractionRules"), "@xml/data_extraction_rules")

    def test_both_rule_files_take_the_file_the_app_keeps_everything_in(self):
        # lib/data/store.dart uses SharedPreferencesAsync, which keeps a
        # DataStore file under files/datastore/.
        self.assertIn("SharedPreferencesAsync", read("lib/data/store.dart"))
        old = ET.parse(MAIN / "res" / "xml" / "backup_rules.xml").getroot()
        self.assertEqual(old.tag, "full-backup-content")
        self.assertIn({"domain": "file", "path": "datastore/"}, [i.attrib for i in old.iter("include")])
        self.assertEqual(list(old.iter("exclude")), [])
        new = ET.parse(MAIN / "res" / "xml" / "data_extraction_rules.xml").getroot()
        self.assertEqual(new.tag, "data-extraction-rules")
        for part in ("cloud-backup", "device-transfer"):
            self.assertIn({"domain": "file", "path": "datastore/"}, [i.attrib for i in new.find(part).iter("include")], part)


if __name__ == "__main__":
    unittest.main()
