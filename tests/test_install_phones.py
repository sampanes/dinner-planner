"""apps/dinner_planner/tool/install_phones.py: reading what adb says."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "apps" / "dinner_planner" / "tool"))

import install_phones as ip  # noqa: E402


class AdbOutputTests(unittest.TestCase):
    def test_wireless_addresses_take_only_the_connect_service(self):
        mdns = (
            "List of discovered mdns services\n"
            "adb-AAAA-x1\t_adb._tcp.\t10.0.0.5:5555\n"
            "adb-AAAA-x1\t_adb-tls-connect._tcp.\t10.0.0.5:37001\n"
            "adb-BBBB-y2\t_adb-tls-pairing._tcp.\t10.0.0.6:41000\n"
            "adb-BBBB-y2 (2)\t_adb-tls-connect._tcp.\t10.0.0.6:40002\n"
        )
        self.assertEqual(ip.wireless_addresses(mdns), ["10.0.0.5:37001", "10.0.0.6:40002"])

    def test_only_ready_devices_are_used(self):
        devices = (
            "List of devices attached\n"
            "SERIAL1\tdevice\n"
            "10.0.0.6:40002\tdevice\n"
            "SERIAL3\tunauthorized\n"
            "SERIAL4\toffline\n"
            "\n"
        )
        self.assertEqual(ip.ready_devices(devices), ["SERIAL1", "10.0.0.6:40002"])


class ReleaseTests(unittest.TestCase):
    def test_newest_app_release_with_an_apk_is_picked(self):
        releases = [
            {"tag_name": "app-v0.9.0", "draft": True, "assets": [{"name": "a.apk"}]},
            {"tag_name": "site-2026", "assets": [{"name": "b.apk"}]},
            {"tag_name": "app-v0.8.1", "assets": [{"name": "notes.txt"}]},
            {"tag_name": "app-v0.8.0", "assets": [{"name": "x.txt"}, {"name": "dinner-planner-0.8.0.apk", "size": 5}]},
            {"tag_name": "app-v0.7.0", "assets": [{"name": "dinner-planner-0.7.0.apk"}]},
        ]
        tag, asset = ip.newest_app_release(releases)
        self.assertEqual((tag, asset["name"]), ("app-v0.8.0", "dinner-planner-0.8.0.apk"))

    def test_ten_is_newer_than_nine_whatever_order_github_lists_them_in(self):
        releases = [
            {"tag_name": "app-v0.9.0", "assets": [{"name": "dinner-planner-0.9.0.apk"}]},
            {"tag_name": "app-v0.10.0", "assets": [{"name": "dinner-planner-0.10.0.apk"}]},
            {"tag_name": "app-v0.8.0", "assets": [{"name": "dinner-planner-0.8.0.apk"}]},
        ]
        self.assertEqual(ip.newest_app_release(releases)[0], "app-v0.10.0")

    def test_no_release_gives_none(self):
        self.assertIsNone(ip.newest_app_release([]))


if __name__ == "__main__":
    unittest.main()
