"""Puts the newest phone app from GitHub on every phone adb can reach.

    install-phones.bat                  (repo root; same as the line below)
    python apps/dinner_planner/tool/install_phones.py
    python apps/dinner_planner/tool/install_phones.py --list      which version each phone has
    python apps/dinner_planner/tool/install_phones.py --version 0.10.0   that release, not the newest
    python apps/dinner_planner/tool/install_phones.py --build     build here instead of downloading

On each phone: Settings > Developer options > Wireless debugging, on, same Wi-Fi as this computer.
Phones paired with this computer before are found and connected by themselves; a USB cable works too.

GitHub's "Phone app" workflow builds and signs every version (raise `version:`
in pubspec.yaml and push) and attaches it to a release named app-v<version>.
This downloads the newest one, keeps it in build/releases/, and installs it
over adb, which keeps everything the app holds. The APK is signed by GitHub, so
this works from any computer. adb installs are also the route Android's
developer verification leaves open.

--build signs with this computer's key instead, which only matches the phones'
copy on the computer that set up the app's key (android/key.properties).
An install Android refuses is reported and left alone; this never uninstalls.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
ROOT = APP.parent.parent
KEY_PROPERTIES = APP / "android" / "key.properties"
BUILT_APK = APP / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
DOWNLOADS = APP / "build" / "releases"
PACKAGE = "dev.dinnerplanner.dinner_planner"
TAG_PREFIX = "app-v"


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


def repo_slug() -> str | None:
    url = run(["git", "-C", str(ROOT), "remote", "get-url", "origin"]).stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$", url)
    return f"{m.group(1)}/{m.group(2)}" if m else None


def version_of(tag: str) -> tuple[int, ...]:
    """app-v0.10.0 -> (0, 10, 0), so that 0.10 counts as newer than 0.9."""
    return tuple(int(n) for n in re.findall(r"\d+", tag[len(TAG_PREFIX):]))


def newest_app_release(releases: list[dict]) -> tuple[str, dict] | None:
    """(tag, apk asset) of the published app release with the highest version
    that has an APK. The order GitHub lists them in is not by version: it put
    app-v0.9.0 ahead of app-v0.10.0."""
    best = None
    for rel in releases:
        tag = rel.get("tag_name") or ""
        if not tag.startswith(TAG_PREFIX) or rel.get("draft") or rel.get("prerelease"):
            continue
        for asset in rel.get("assets") or []:
            if str(asset.get("name", "")).endswith(".apk"):
                if best is None or version_of(tag) > version_of(best[0]):
                    best = (tag, asset)
                break
    return best


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "install-phones"})
    with urllib.request.urlopen(req, timeout=30) as res:
        return json.load(res)


def download(url: str, dest: Path, size: int) -> None:
    part = dest.with_suffix(".part")
    curl = shutil.which("curl")
    if curl:
        # curl (part of Windows 10) keeps a steady pace where urllib has stalled,
        # and its bar shows how far along it is.
        done = subprocess.run([curl, "-L", "--fail", "--retry", "3", "-#", "-o", str(part), url], stdin=subprocess.DEVNULL)
        if done.returncode != 0:
            part.unlink(missing_ok=True)
            raise OSError(f"curl exited with {done.returncode}")
        if size and part.stat().st_size != size:
            part.unlink()
            raise OSError("the download was cut short")
        part.replace(dest)
        return
    req = urllib.request.Request(url, headers={"User-Agent": "install-phones"})
    with urllib.request.urlopen(req, timeout=60) as res, open(part, "wb") as out:
        got, shown = 0, -1
        while chunk := res.read(1 << 20):
            out.write(chunk)
            got += len(chunk)
            pct = got * 100 // size if size else 0
            if pct // 10 != shown:
                shown = pct // 10
                print(f"    {got >> 20} of {size >> 20} MB", flush=True)
    if size and part.stat().st_size != size:
        part.unlink()
        raise OSError("the download was cut short")
    part.replace(dest)


def latest_apk(version: str | None = None) -> Path | None:
    slug = repo_slug()
    if not slug:
        print("[X] This clone's origin is not a GitHub repository.")
        return None
    try:
        releases = fetch_json(f"https://api.github.com/repos/{slug}/releases?per_page=30")
        # One named version, or the newest there is.
        found = newest_app_release([r for r in releases if version is None or r.get("tag_name") == TAG_PREFIX + version])
    except OSError as e:
        print(f"[X] Could not ask GitHub for the releases ({e}).")
        return None
    if not found:
        print(f"[X] {slug} has no app release with an APK yet. Raise version: in pubspec.yaml and push.")
        return None
    tag, asset = found
    dest = DOWNLOADS / asset["name"]
    if dest.is_file() and dest.stat().st_size == asset.get("size"):
        print(f"[OK] {tag}: already downloaded.")
        return dest
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    print(f"... downloading {tag} ({asset.get('size', 0) >> 20} MB)", flush=True)
    try:
        download(asset["browser_download_url"], dest, int(asset.get("size") or 0))
    except OSError as e:
        print(f"[X] The download failed ({e}).")
        return None
    return dest


def build_here() -> Path | None:
    if not KEY_PROPERTIES.is_file():
        print("[X] This computer's builds are not signed with the app's key (no android/key.properties),")
        print("    so the phones would refuse them. Leave out --build to install GitHub's signed copy.")
        return None
    flutter = shutil.which("flutter")
    if not flutter:
        print("[X] flutter was not found.")
        return None
    print("... building the app (a minute or three)", flush=True)
    if subprocess.run([flutter, "build", "apk", "--release"], cwd=APP, stdin=subprocess.DEVNULL).returncode != 0:
        print("[X] The build failed; nothing was installed.")
        return None
    return BUILT_APK


def installed_version(adb: str, serial: str) -> str | None:
    m = re.search(r"versionName=(\S+)", run([adb, "-s", serial, "shell", "dumpsys", "package", PACKAGE]).stdout)
    return m.group(1) if m else None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Install the newest phone app from GitHub on every reachable phone.")
    ap.add_argument("--list", action="store_true", help="only list the phones found, with the version each has")
    ap.add_argument("--build", action="store_true", help="build here instead of downloading GitHub's copy")
    ap.add_argument("--version", metavar="X.Y.Z", help="install that release instead of the newest (Android refuses to go back to an older one)")
    args = ap.parse_args(argv)

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
    models = {s: run([adb, "-s", s, "shell", "getprop", "ro.product.model"]).stdout.strip() or s for s in serials}
    print(f"[OK] Found {len(serials)} phone(s): " + ", ".join(f"{models[s]} ({installed_version(adb, s) or 'no app'})" for s in serials))
    if args.list:
        return 0

    apk = build_here() if args.build else latest_apk(args.version)
    if not apk:
        return 1

    failed = 0
    for serial in serials:
        done = run([adb, "-s", serial, "install", "-r", str(apk)], timeout=600)
        text = (done.stdout + done.stderr).strip()
        if done.returncode == 0 and "Success" in text:
            print(f"[OK] {models[serial]}: now {installed_version(adb, serial) or 'installed'}")
            continue
        failed += 1
        if "UPDATE_INCOMPATIBLE" in text:
            print(f"[X] {models[serial]}: Android refused, because the copy on it was signed with another key. Nothing")
            print("    was changed. To move it, see \"Moving a phone to the signed app\" in apps/dinner_planner/README.md.")
        elif "VERSION_DOWNGRADE" in text:
            print(f"[X] {models[serial]}: it already has a newer version than this one. Nothing was changed.")
        else:
            print(f"[X] {models[serial]}: {text.splitlines()[-1] if text else 'install failed'}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
