"""Give the phone app one signing key, kept by GitHub, so it stops mattering
which computer a build comes from.

Android only installs an update signed with the same key as the copy already
on the phone. A build made on a computer with no key of the app's own is
signed with that computer's debug key, which is different on every machine.
This script makes one key for the app and hands it to the repository as four
secrets; from then on GitHub builds and signs every version (the "Phone app"
workflow) and the phones install from the releases page.

Run it once, on a computer where `gh` is signed in as the repository's owner:

    python apps/dinner_planner/tool/signing_setup.py

It makes private/keys/dinner-planner.jks and a note of its password beside it
(private/ is ignored by git: keep that folder, it is the only other copy of
the key), sets the four ANDROID_* secrets, points this computer's own builds
at the same key (android/key.properties, also ignored), and starts the first
signed build. It never touches the computer's debug key.

    --check     say what is set up and change nothing
    --replace   make a new key even though one is set (every phone must then
                remove the app and install it again)
"""

from __future__ import annotations

import argparse
import base64
import os
import re
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
ROOT = APP.parent.parent
KEYS = ROOT / "private" / "keys"
KEYSTORE = KEYS / "dinner-planner.jks"
KEY_NOTE = KEYS / "dinner-planner-key.txt"
KEY_PROPERTIES = APP / "android" / "key.properties"
ALIAS = "dinner-planner"
SECRET_NAMES = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD"]


# ---------- pure helpers (tested offline) ----------
def repo_of(remote_url: str) -> tuple[str, str] | None:
    """("owner", "name") from a GitHub remote url, https or ssh."""
    m = re.search(r"github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", remote_url.strip())
    return (m.group(1), m.group(2)) if m else None


def app_version(pubspec_text: str) -> str | None:
    """"0.8.0" from the pubspec's "version: 0.8.0+11"."""
    m = re.search(r"^version:\s*([0-9]+(?:\.[0-9]+)*)", pubspec_text, re.M)
    return m.group(1) if m else None


def key_properties(keystore: Path, password: str) -> str:
    """What android/key.properties holds; the path uses forward slashes on every system."""
    return f"storeFile={keystore.as_posix()}\nstorePassword={password}\nkeyAlias={ALIAS}\nkeyPassword={password}\n"


def secret_values(keystore_bytes: bytes, password: str) -> dict[str, str]:
    return {
        "ANDROID_KEYSTORE_BASE64": base64.b64encode(keystore_bytes).decode("ascii"),
        "ANDROID_KEYSTORE_PASSWORD": password,
        "ANDROID_KEY_ALIAS": ALIAS,
        "ANDROID_KEY_PASSWORD": password,
    }


def password_in(note_text: str) -> str | None:
    m = re.search(r"^password: (\S+)$", note_text, re.M)
    return m.group(1) if m else None


# ---------- the outside world ----------
def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def find_keytool() -> str | None:
    """keytool comes with any Java, including the one inside Android Studio."""
    found = shutil.which("keytool")
    if found:
        return found
    exe = "keytool.exe" if os.name == "nt" else "keytool"
    places = [Path(os.environ[v]) / "bin" / exe for v in ("JAVA_HOME", "JDK_HOME") if os.environ.get(v)]
    places += [
        Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Android" / "Android Studio" / "jbr" / "bin" / exe,
        Path("/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin") / exe,
        Path("/opt/android-studio/jbr/bin") / exe,
        Path.home() / "android-studio" / "jbr" / "bin" / exe,
    ]
    return next((str(p) for p in places if p.is_file()), None)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="One signing key for the phone app, kept by GitHub.")
    ap.add_argument("--check", action="store_true", help="say what is set up and change nothing")
    ap.add_argument("--replace", action="store_true", help="make a new key even though one is set")
    args = ap.parse_args(argv)

    if not shutil.which("gh"):
        print("[X] The GitHub command line tool (gh) is not installed: https://cli.github.com")
        return 1
    remote = run(["git", "-C", str(ROOT), "remote", "get-url", "origin"]).stdout
    repo = repo_of(remote)
    if not repo:
        print("[X] This clone's origin is not a GitHub repository.")
        return 1
    owner, name = repo
    slug = f"{owner}/{name}"
    who = run(["gh", "api", "user", "--jq", ".login"], stdin=subprocess.DEVNULL)
    login = who.stdout.strip()
    if who.returncode != 0 or not login:
        print("[X] gh is not signed in on this computer. Run  gh auth login  as the repository's owner, then this again.")
        return 1
    if login.lower() != owner.lower():
        print(f"[X] gh on this computer is signed in as someone other than {owner}, who owns {slug}.")
        print("    Nothing was changed. Run this on the computer where gh is signed in as the owner.")
        return 1

    listed = run(["gh", "secret", "list", "--repo", slug, "--json", "name", "--jq", ".[].name"], stdin=subprocess.DEVNULL)
    have = set(listed.stdout.split())
    missing = [n for n in SECRET_NAMES if n not in have]
    print(f"Repository {slug}: " + ("all four signing secrets are set." if not missing else "missing " + ", ".join(missing) + "."))
    print(f"This computer: {'has' if KEYSTORE.is_file() else 'does not have'} the key file (private/keys/{KEYSTORE.name}); "
          f"its own builds {'use' if KEY_PROPERTIES.is_file() else 'do not use'} it.")
    if args.check:
        return 0
    if not missing and not args.replace:
        print("[OK] Nothing to do. (--replace makes a new key; every phone would then have to remove the app and install it again.)")
        return 0

    password = None
    if KEYSTORE.is_file() and KEY_NOTE.is_file() and not args.replace:
        # The key was made here before and only the secrets are missing: hand over the same key.
        password = password_in(KEY_NOTE.read_text(encoding="utf-8"))
    if password is None:
        keytool = find_keytool()
        if not keytool:
            print("[X] keytool was not found. It comes with Java; set JAVA_HOME, or install Android Studio.")
            return 1
        KEYS.mkdir(parents=True, exist_ok=True)
        if KEYSTORE.exists():
            KEYSTORE.rename(KEYSTORE.with_suffix(f".old-{secrets.token_hex(3)}.jks"))
        password = secrets.token_urlsafe(24)
        made = run([keytool, "-genkeypair", "-keystore", str(KEYSTORE), "-storetype", "PKCS12", "-alias", ALIAS,
                    "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Dinner Planner",
                    "-storepass:env", "DP_KEY_PASSWORD", "-keypass:env", "DP_KEY_PASSWORD"],
                   env={**os.environ, "DP_KEY_PASSWORD": password}, stdin=subprocess.DEVNULL)
        if made.returncode != 0 or not KEYSTORE.is_file():
            print("[X] keytool could not make the key:\n" + (made.stderr or made.stdout).strip())
            return 1
        KEY_NOTE.write_text(f"The signing key of the phone app. Keep this folder; never commit it.\nalias: {ALIAS}\npassword: {password}\n", encoding="utf-8")
        print(f"[OK] Made the key: private/keys/{KEYSTORE.name} (its password is in {KEY_NOTE.name} beside it).")

    for secret, value in secret_values(KEYSTORE.read_bytes(), password).items():
        done = subprocess.run(["gh", "secret", "set", secret, "--repo", slug], input=value, text=True, capture_output=True)
        if done.returncode != 0:
            print(f"[X] Could not set {secret}:\n{done.stderr.strip()}")
            return 1
    print("[OK] Set the four ANDROID_* secrets.")

    KEY_PROPERTIES.write_text(key_properties(KEYSTORE, password), encoding="utf-8")
    print("[OK] Builds on this computer now use the same key (android/key.properties).")

    started = run(["gh", "workflow", "run", "app.yml", "--repo", slug, "--ref", "main"], stdin=subprocess.DEVNULL)
    version = app_version((APP / "pubspec.yaml").read_text(encoding="utf-8")) or "?"
    if started.returncode == 0:
        print(f"[OK] Started the first signed build ({version}). In a few minutes the APK is at:")
    else:
        print("[!] Could not start the build; the next push that changes the app will make it. The APK will be at:")
    print(f"     https://github.com/{slug}/releases/latest")
    print("\nA phone that has a copy installed by hand: see \"Moving a phone to the signed app\" in apps/dinner_planner/README.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
