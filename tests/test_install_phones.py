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


if __name__ == "__main__":
    unittest.main()
