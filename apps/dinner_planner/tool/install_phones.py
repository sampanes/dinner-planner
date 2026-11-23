"""Builds the phone app here and installs it on every phone adb can reach.

    install-phones.bat                 (repo root; same as the line below)
    python apps/dinner_planner/tool/install_phones.py
    python apps/dinner_planner/tool/install_phones.py --no-build    install the last build again

On each phone: Settings > Developer options > Wireless debugging, on, same Wi-Fi as this computer.
Phones paired with this computer before are found and connected by themselves; a USB cable works too.

It only runs on a computer whose release builds are signed with the app's key
(android/key.properties, written by signing_setup.py): a build signed with any
other key would not install over the phones' copy. An install Android refuses
is reported and left alone; this never uninstalls anything.

adb installs are the way in that Android's developer verification leaves open,
so this is the main way the phones get the app. GitHub's "Phone app" workflow
signs the same version with the same key and keeps it as a release, as a
spare copy.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
KEY_PROPERTIES = APP / "android" / "key.properties"
APK = APP / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
PACKAGE = "dev.dinnerplanner.dinner_planner"


def run(cmd: list[str], timeout: float = 60) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(cmd, 124, "", "timed out")


def find_adb() -> str | None:
    found = shutil.which("adb")
    if found:
        return found
    for base in (os.environ.get("ANDROID_HOME"), os.environ.get("ANDROID_SDK_ROOT"),
                 os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk")):
        if base:
            exe = Path(base) / "platform-tools" / ("adb.exe" if os.name == "nt" else "adb")
            if exe.is_file():
                return str(exe)
    return None


def wireless_addresses(mdns_output: str) -> list[str]:
    """ip:port of each phone offering a wireless debugging connection."""
    return sorted(set(re.findall(r"_adb-tls-connect\._tcp\.?\s+(\d+\.\d+\.\d+\.\d+:\d+)", mdns_output)))


def ready_devices(devices_output: str) -> list[str]:
    rows = [line.split() for line in devices_output.splitlines()[1:]]
    return [row[0] for row in rows if len(row) >= 2 and row[1] == "device"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Build the phone app and install it on every reachable phone.")
    ap.add_argument("--no-build", action="store_true", help="install the APK already built")
    ap.add_argument("--list", action="store_true", help="only list the phones found, with the version each has")
    args = ap.parse_args(argv)

    if not KEY_PROPERTIES.is_file():
        print("[X] This computer's builds are not signed with the app's key (no android/key.properties),")
        print("    so they would not install over the phones' copy. Build and install from the computer that")
        print("    has it, or see \"Installing and updating\" in apps/dinner_planner/README.md.")
        return 1
    adb = find_adb()
    if not adb:
        print("[X] adb was not found. It comes with the Android SDK (platform-tools).")
        return 1

    for address in wireless_addresses(run([adb, "mdns", "services"]).stdout):
        run([adb, "connect", address], timeout=15)
    serials, seen = [], set()
    for serial in ready_devices(run([adb, "devices"]).stdout):
        # A phone on both a cable and Wi-Fi is listed twice; install once.
        hw = run([adb, "-s", serial, "shell", "getprop", "ro.serialno"]).stdout.strip() or serial
        if hw not in seen:
            seen.add(hw)
            serials.append(serial)
    if not serials:
        print("[X] No phone found. On each phone: Settings > Developer options > Wireless debugging, on,")
        print("    on the same Wi-Fi as this computer (a phone never paired here needs \"Pair device with")
        print("    pairing code\" once, then  adb pair IP:PORT ). Or plug it in with a USB cable.")
        return 1
    print(f"[OK] Found {len(serials)} phone(s).")
    if args.list:
        for serial in serials:
            model = run([adb, "-s", serial, "shell", "getprop", "ro.product.model"]).stdout.strip() or serial
            version = re.search(r"versionName=(\S+)", run([adb, "-s", serial, "shell", "dumpsys", "package", PACKAGE]).stdout)
            print(f"     {model}: {version.group(1) if version else 'app not installed'}")
        return 0

    if not args.no_build:
        flutter = shutil.which("flutter")
        if not flutter:
            print("[X] flutter was not found.")
            return 1
        print("... building the app (a minute or three)", flush=True)
        built = subprocess.run([flutter, "build", "apk", "--release"], cwd=APP, stdin=subprocess.DEVNULL)
        if built.returncode != 0:
            print("[X] The build failed; nothing was installed.")
            return 1
    if not APK.is_file():
        print(f"[X] No APK at {APK}. Run without --no-build.")
        return 1

    failed = 0
    for serial in serials:
        model = run([adb, "-s", serial, "shell", "getprop", "ro.product.model"]).stdout.strip() or serial
        done = run([adb, "-s", serial, "install", "-r", str(APK)], timeout=600)
        text = (done.stdout + done.stderr).strip()
        if done.returncode == 0 and "Success" in text:
            info = run([adb, "-s", serial, "shell", "dumpsys", "package", PACKAGE]).stdout
            version = re.search(r"versionName=(\S+)", info)
            print(f"[OK] {model}: installed {version.group(1) if version else ''}")
            continue
        failed += 1
        if "UPDATE_INCOMPATIBLE" in text:
            print(f"[X] {model}: Android refused, because the copy on it was signed with another key. Nothing was")
            print("    changed. To move it, see \"Moving a phone to the signed app\" in apps/dinner_planner/README.md.")
        else:
            print(f"[X] {model}: {text.splitlines()[-1] if text else 'install failed'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
