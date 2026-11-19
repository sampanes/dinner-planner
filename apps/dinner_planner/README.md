# Dinner Planner, the phone app

The recipe site shows recipes to anyone. This Android app holds the part that is yours: which
dinner is on which night, who cooks it, and reminders on the nights you cook. Two phones can share
all of that, and none of it is written to the repository.

- **Tonight**: what is for dinner, who is cooking, one button to open the recipe in the site's
  kitchen page, and "What it needs" to check the fridge.
- **Week**: the next fourteen days. Tap a day to pick dinner, tap a name to say who cooks. The
  playlist button adds the dinners from the site's weekly plan to the empty days.
- **Reminders** on your nights: the evening before (check the fridge, start thawing), that morning,
  and when to start cooking. Times are in Settings. A night the other phone hands you gets its
  reminders without you opening the app.
- **Sharing**: one phone taps "Start sharing" and shows a code, the other taps "Join with a code".

## What is stored where

| What | Where |
|---|---|
| Recipes, photos, the kitchen page | the recipe site (public; set its address in Settings) |
| Dinners by day, who cooks, the two names | each phone, and the relay messages between them |
| Which person this phone belongs to, reminder times | this phone only |

## How two phones stay the same

The shared state is a flat map (`cook/2026-11-19` -> `blue`), newest write wins
(`lib/core/sync_core.dart`). Phones exchange writes as messages on an [ntfy](https://ntfy.sh) topic
with a random 128-bit name that only the sharing code carries. ntfy.sh keeps a message about twelve
hours, so every message also carries a digest of the sender's whole state; a phone that hears a
digest unlike its own re-sends what the other may be missing, every six hours until they match.
The open app checks every twenty seconds; a background task checks about hourly.

Messages are readable text on the relay ("Sam cooks tomorrow" plus one machine line). Anyone who
has the code can read and write the plan, so treat the code like a house key. For a relay nobody
else runs, start ntfy on a machine of your own and choose "Start on my own server":

```yaml
# docker-compose.yml
services:
  ntfy:
    image: binwiederhier/ntfy
    command: serve
    environment:
      NTFY_BASE_URL: http://your-machine:8080
      NTFY_CACHE_FILE: /var/lib/ntfy/cache.db
      NTFY_CACHE_DURATION: 720h   # a month, so a phone that was off catches up at once
    volumes: ["./ntfy:/var/lib/ntfy"]
    ports: ["8080:80"]
```

Both phones must be able to reach that address (the same Wi-Fi, or a private network such as
Tailscale on both). When the machine is off the phones keep working and catch up later.

## Build and test

The Flutter version is pinned in `.fvmrc`.

```bash
flutter pub get
flutter analyze
flutter test                      # sync rules, reminders, the screens
flutter build apk --release       # build/app/outputs/flutter-apk/app-release.apk
```

Screens as PNG files, for looking over a change without a phone:

```bash
SHOTS_DIR=/some/folder SHOTS_PHOTOS=1 flutter test test/shots_test.dart
```

A release build is signed with the key named in `android/key.properties` (never committed) and
falls back to the debug key without it. Android only installs an update signed with the same key
as the copy already on the phone, so use one key for every release.

## Not built yet

- Timers that keep running with the screen off (the kitchen page's timers stop when the phone sleeps).
- Showing tonight's dinner on the Echo Show when a phone starts cooking.
- A scan-able code for joining, a home-screen widget, sharing a recipe link into the app.
