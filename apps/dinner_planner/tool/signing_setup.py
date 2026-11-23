"""Give the phone app one signing key, kept by GitHub, so it stops mattering
which computer a build comes from.

Android only installs an update signed with the same key as the copy already
on the phone. A build made on a computer with no key of the app's own is
signed with that computer's debug key, which is different on every machine.
This script settles on one key for the app and hands it to the repository as
four secrets; from then on GitHub builds and signs every version (the "Phone
app" workflow) and the phones install from the releases page.

Run it once, on a computer where `gh` is signed in as the repository's owner:

    python apps/dinner_planner/tool/signing_setup.py

Which key becomes the app's key, first match wins:

1. private/keys/dinner-planner.jks, when an earlier run made it here.
2. The key android/key.properties already names, when this computer's release
   builds use one: copies installed from here carry it, so they keep updating.
3. With --adopt-debug-key, a copy of this computer's debug key: every copy
   installed from this computer so far carries that one, so those phones take
   the signed releases as plain updates and lose nothing.
4. Otherwise a new key. Every phone that already has the app must then remove
   it once and install the signed one ("Moving a phone to the signed app" in
   the app's README).

The key and a note of its password live in private/keys/ (ignored by git: keep
that folder, it is the only other copy). The script sets the four ANDROID_*
secrets, points this computer's own release builds at the same key
(android/key.properties, also ignored) and starts the first signed build. It
never changes or deletes a debug key.

    --check             say what is set up and change nothing
    --adopt-debug-key   see 3 above
    --replace           settle on a key again even though one is set (every
                        phone must then remove the app and install it again)
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
from dataclasses import dataclass
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
ROOT = APP.parent.parent
KEYS = ROOT / "private" / "keys"
KEYSTORE = KEYS / "dinner-planner.jks"
KEY_NOTE = KEYS / "dinner-planner-key.txt"
KEY_PROPERTIES = APP / "android" / "key.properties"
ALIAS = "dinner-planner"
SECRET_NAMES = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD"]

# What the Android tools give every computer's debug key.
DEBUG_KEYSTORE = Path.home() / ".android" / "debug.keystore"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASSWORD = "android"


@dataclass
class Key:
    store: Path
    alias: str
    store_password: str
    key_password: str


# ---------- pure helpers (tested offline) ----------
def repo_of(remote_url: str) -> tuple[str, str] | None:
    """("owner", "name") from a GitHub remote url, https or ssh."""
    m = re.search(r"github\.com[:/]([^/\s]+)/([^/\s]+?)(?:\.git)?/?$", remote_url.strip())
    return (m.group(1), m.group(2)) if m else None


def app_version(pubspec_text: str) -> str | None:
    """"0.8.0" from the pubspec's "version: 0.8.0+11"."""
    m = re.search(r"^version:\s*([0-9]+(?:\.[0-9]+)*)", pubspec_text, re.M)
    return m.group(1) if m else None


def key_properties(keystore: Path, password: str, alias: str = ALIAS) -> str:
    """What android/key.properties holds; the path uses forward slashes on every system."""
    return f"storeFile={keystore.as_posix()}\nstorePassword={password}\nkeyAlias={alias}\nkeyPassword={password}\n"


def properties_in(text: str) -> dict[str, str]:
    """The name=value lines of a properties file as plain as this script writes them."""
    found = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith(("#", "!")) and "=" in line:
            name, value = line.split("=", 1)
            found[name.strip()] = value.strip()
    return found


def key_named_by(properties_text: str, app_folder: Path) -> Key | None:
    """The key a key.properties names; its storeFile is relative to android/app, as Gradle reads it."""
    p = properties_in(properties_text)
    if not all(p.get(n) for n in ("storeFile", "storePassword", "keyAlias", "keyPassword")):
        return None
    return Key(app_folder / "android" / "app" / p["storeFile"], p["keyAlias"], p["storePassword"], p["keyPassword"])


def secret_values(keystore_bytes: bytes, password: str, alias: str = ALIAS, key_password: str | None = None) -> dict[str, str]:
    return {
        "ANDROID_KEYSTORE_BASE64": base64.b64encode(keystore_bytes).decode("ascii"),
        "ANDROID_KEYSTORE_PASSWORD": password,
        "ANDROID_KEY_ALIAS": alias,
        "ANDROID_KEY_PASSWORD": password if key_password is None else key_password,
    }


def key_note(alias: str, password: str) -> str:
    return f"The signing key of the phone app. Keep this folder; never commit it.\nalias: {alias}\npassword: {password}\n"


def password_in(note_text: str) -> str | None:
    m = re.search(r"^password: (\S+)$", note_text, re.M)
    return m.group(1) if m else None


def alias_in(note_text: str) -> str:
    m = re.search(r"^alias: (\S+)$", note_text, re.M)
    return m.group(1) if m else ALIAS


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


def make_key(keytool: str, keystore: Path, alias: str, password: str) -> str | None:
    """Make a new key; the error text when it could not be made."""
    made = run([keytool, "-genkeypair", "-keystore", str(keystore), "-storetype", "PKCS12", "-alias", alias,
                "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Dinner Planner",
                "-storepass:env", "DP_KEY_PASSWORD", "-keypass:env", "DP_KEY_PASSWORD"],
               env={**os.environ, "DP_KEY_PASSWORD": password}, stdin=subprocess.DEVNULL)
    if made.returncode != 0 or not keystore.is_file():
        return (made.stderr or made.stdout).strip() or "keytool made no file"
    return None


def opens(keytool: str, keystore: Path, alias: str, password: str) -> bool:
    """Whether the password opens the keystore and the alias is in it."""
    listed = run([keytool, "-list", "-keystore", str(keystore), "-alias", alias, "-storepass:env", "DP_KEY_PASSWORD"],
                 env={**os.environ, "DP_KEY_PASSWORD": password}, stdin=subprocess.DEVNULL)
    return listed.returncode == 0


def set_aside(path: Path) -> None:
    """Keep an older file under another name instead of writing over it."""
    if path.exists():
        path.rename(path.with_suffix(f".old-{secrets.token_hex(3)}{path.suffix}"))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="One signing key for the phone app, kept by GitHub.")
    ap.add_argument("--check", action="store_true", help="say what is set up and change nothing")
    ap.add_argument("--adopt-debug-key", action="store_true",
                    help="make this computer's debug key the app's key, so copies installed from here keep updating")
    ap.add_argument("--replace", action="store_true", help="settle on a key again even though one is set")
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
    named = key_named_by(KEY_PROPERTIES.read_text(encoding="utf-8"), APP) if KEY_PROPERTIES.is_file() else None
    print(f"Repository {slug}: " + ("all four signing secrets are set." if not missing else "missing " + ", ".join(missing) + "."))
    print(f"This computer: {'has' if KEYSTORE.is_file() else 'does not have'} the key file (private/keys/{KEYSTORE.name}).")
    print("This computer's own release builds are signed with "
          + (f"the key android/key.properties names ({named.store.name})." if named else
             "its debug key, like every copy installed from it so far."))
    if args.check:
        return 0
    if not missing and not args.replace:
        print("[OK] Nothing to do. (--replace settles on a key again; every phone would then have to remove the app and install it again.)")
        return 0

    keytool = find_keytool()
    key = None
    write_properties = True
    if not args.replace:
        if KEYSTORE.is_file() and KEY_NOTE.is_file():
            # The key was made here before and only the secrets are missing: hand over the same key.
            note = KEY_NOTE.read_text(encoding="utf-8")
            password = password_in(note)
            if password:
                key = Key(KEYSTORE, alias_in(note), password, password)
        if key is None and named is not None:
            if not named.store.is_file():
                print(f"[X] android/key.properties names a key that is not there: {named.store}")
                print("    Nothing was changed. Put the file back, or delete key.properties if that key is gone for good.")
                return 1
            key = named
            write_properties = False
            print(f"[OK] This computer's builds already use a key of the app's own ({named.store.name}): GitHub gets the same one.")
            print(f"     Keep that file safe: {named.store}")

    if key is not None and args.adopt_debug_key:
        print("     (--adopt-debug-key was not used: this computer already has a key for the app.)")
    if key is None and args.adopt_debug_key:
        if not DEBUG_KEYSTORE.is_file():
            print(f"[X] This computer has no debug key ({DEBUG_KEYSTORE}). Nothing was changed. Run without --adopt-debug-key for a new key.")
            return 1
        if keytool and not opens(keytool, DEBUG_KEYSTORE, DEBUG_ALIAS, DEBUG_PASSWORD):
            print("[X] This computer's debug key does not open with the usual name and password. Nothing was changed.")
            return 1
        KEYS.mkdir(parents=True, exist_ok=True)
        set_aside(KEYSTORE)
        shutil.copyfile(DEBUG_KEYSTORE, KEYSTORE)
        KEY_NOTE.write_text(key_note(DEBUG_ALIAS, DEBUG_PASSWORD), encoding="utf-8")
        key = Key(KEYSTORE, DEBUG_ALIAS, DEBUG_PASSWORD, DEBUG_PASSWORD)
        print(f"[OK] The app's key is now a copy of this computer's debug key: private/keys/{KEYSTORE.name}.")
        print("     Copies installed from this computer take the signed releases as plain updates.")

    if key is None:
        if not keytool:
            print("[X] keytool was not found. It comes with Java; set JAVA_HOME, or install Android Studio.")
            return 1
        KEYS.mkdir(parents=True, exist_ok=True)
        set_aside(KEYSTORE)
        password = secrets.token_urlsafe(24)
        problem = make_key(keytool, KEYSTORE, ALIAS, password)
        if problem:
            print("[X] keytool could not make the key:\n" + problem)
            return 1
        KEY_NOTE.write_text(key_note(ALIAS, password), encoding="utf-8")
        key = Key(KEYSTORE, ALIAS, password, password)
        print(f"[OK] Made a new key: private/keys/{KEYSTORE.name} (its password is in {KEY_NOTE.name} beside it).")
        print("     A phone that already has the app must remove it once before the signed one installs.")

    values = secret_values(key.store.read_bytes(), key.store_password, key.alias, key.key_password)
    for secret, value in values.items():
        done = subprocess.run(["gh", "secret", "set", secret, "--repo", slug], input=value, text=True, capture_output=True)
        if done.returncode != 0:
            print(f"[X] Could not set {secret}:\n{done.stderr.strip()}")
            return 1
    print("[OK] Set the four ANDROID_* secrets.")

    if write_properties:
        KEY_PROPERTIES.write_text(key_properties(key.store, key.store_password, key.alias), encoding="utf-8")
        print("[OK] Release builds on this computer now use the same key (android/key.properties).")

    started = run(["gh", "workflow", "run", "app.yml", "--repo", slug, "--ref", "main"], stdin=subprocess.DEVNULL)
    version = app_version((APP / "pubspec.yaml").read_text(encoding="utf-8")) or "?"
    if started.returncode == 0:
        print(f"[OK] Started the first signed build ({version}). In a few minutes the APK is at:")
    else:
        print("[!] Could not start the build; the next push that changes the app will make it. The APK will be at:")
    print(f"     https://github.com/{slug}/releases/latest")
    print("\nOn a phone, open that page and install the APK over the copy it has. If Android refuses, nothing is lost:")
    print("that copy was signed elsewhere. See \"Moving a phone to the signed app\" in apps/dinner_planner/README.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
