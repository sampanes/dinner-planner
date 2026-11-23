# Dinner Planner, the phone app

The recipe site shows recipes to anyone. This Android app holds the part that is yours: which
dinner is on which night, who cooks it, and reminders on the nights you cook. Two phones can share
all of that, and none of it is written to the repository.

- **Tonight**: what is for dinner, who is cooking, one button to open the recipe in the site's
  kitchen page, and "What it needs" to check the fridge. A new phone also gets a **Start here**
  card: five first steps that tick themselves off from what the phone already holds. Skip hides
  it; Settings brings it back.
- **Week**: the next fourteen days. Tap a day to pick dinner, tap a name to say who cooks. The
  playlist button adds the dinners from the site's weekly plan to the empty days.
- **Picking a dinner**: the list opens with three suggestions for the week as it stands, each
  with its reason: how the two of you rated it on the recipe site, what it shares with dinners
  already planned (so the other half of the sour cream gets used), and whether the week is short
  of that kind of dinner. One row of chips narrows by kind; the search looks at names and
  ingredients and forgives a typo (`lib/data/suggest.dart`).
- **Extras**: the plus button puts things no dinner asks for on the same list (milk, coffee,
  foil). They sort into sections, tick, and learn a store's order like everything else, and the
  ones bought before are offered again with a tap.
- **Reminders** on your nights: the evening before (check the fridge, start thawing), that morning,
  and when to start cooking. Times are in Settings. A night the other phone hands you gets its
  reminders without you opening the app.
  They are set as exact alarms (`USE_EXACT_ALARM`, granted at install with no prompt): Android
  delivers any other kind up to an hour late when it was set hours ahead. Google Play allows that
  permission only for alarm and calendar apps, so a Play listing would have to argue the case or
  switch to asking the owner.
- **Shop**: what the planned dinners need, added up into one list, by section. Tap a line when it
  is in the house; tap the tag to record what you actually buy for that ingredient: the brand or
  the name on the shelf, the packet size (the list then says how many packets), its section, and a
  note on where it is in each store. All of it is shared, so one of you can tick things off in the
  store while the other watches. The list copies as plain text.
- **Scan**: point the camera at a packet's barcode and the name, brand and size fill themselves in
  ("Scanning a packet" below). Say once which ingredient a packet is; after that scanning it
  ticks the line. The camera stays open for the next packet, so a full cart or a pantry shelf is
  one go, and a number the camera will not read can be typed.
- **Stores**: add the stores you use, and tap one when you walk in. The list switches to the order
  you walk that store, which it learns from the order you tick things in ("The order of a store"
  below).
- **Sharing**: one phone taps "Start sharing" and shows a code, the other taps "Join with a code".
- **Notes**: "Add a note" under tonight's dinner, or in "What it needs", keeps a line on that recipe
  ("add parmesan as a step"). The other phone, a linked kitchen screen and
  `scripts/house_notes.py` on a computer see it too.

## Linked kitchen screens and computers

The site's kitchen page (`house.js`) and `scripts/house_notes.py` can join the household's topic as
listeners, with the same code. Their device ids start with `show-`: the phones send them the plan
but never count them as "the other phone". The script keeps the code in `private/house.json`,
which git ignores.

## What is stored where

| What | Where |
|---|---|
| Recipes, photos, the kitchen page | the recipe site (public; set its address in Settings) |
| Dinners by day, who cooks, the two names, notes on recipes | each phone, and the relay messages between them |
| What is in the house for which dinner; what you buy for each ingredient, its packet size and section; the stores, and where things are in each | each phone, and the relay messages between them |
| Which barcode is which ingredient | each phone, and the relay messages between them |
| The extras the household buys, and which are on the list | each phone, and the relay messages between them |
| Which person this phone belongs to, reminder times, which store it is in right now, a USDA key | this phone only |

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

## The order of a store

Nobody types a store's layout (`lib/core/store_order.dart`). Each ingredient gets a section from
its name, which the tag sheet can correct. While a phone is "in" a store, every line ticked there
is recorded as coming after the line ticked before it (`pos/<store>/<ingredient>`, a number;
smaller is met sooner). A line that is already further along stays put; otherwise it moves to just
after the one before it, so where two trips disagree the latest wins. Sections are shown in the
order the walk has met them, the rest after in a usual supermarket order. A phone stops counting
as in the store two hours after its last tick, so ticks made at home teach nothing.

## Scanning a packet

The camera reads the barcode on the phone (`mobile_scanner`, with Google's ML Kit model inside
the app, so it works with no signal). The number is then looked up in two free lists
(`lib/data/products.dart`), and only the number is sent:

- [Open Food Facts](https://world.openfoodfacts.org), no key. Names are good; sizes are sometimes
  a serving rather than the packet.
- The USDA's [FoodData Central](https://fdc.nal.usda.gov) branded foods, which US makers file
  themselves, so brand and packet size are reliable. Without a key the app uses the public
  `DEMO_KEY`, good for ten lookups an hour; a free key from api.data.gov goes in Settings.

Where both answer, the name comes from the first and the brand and size from the second. A packet
neither knows is still remembered once you name it: the household keeps its own
`code/<barcode>` -> ingredient map, so the second scan of anything needs no network. A barcode a
store printed on something it weighed (meat, deli) starts with 2 and ends in the price; the price
part is dropped so the next pack of the same thing is recognized.

The scan button on the list keeps the camera open (`lib/ui/scan.dart`). Each barcode is dealt
with and the result shown under the picture with an Undo; the same packet counts again only after
four seconds out of view. "Type the number" takes the digits under the bars instead.

A packet that is not for any recipe becomes an extra: name it once ("Coffee") and choose whether
it goes on the list or is only remembered. From then on its barcode means that extra on both
phones. Scanned in a store, a listed extra is ticked; scanned at home when it is not on the list,
it is put on the list, which is how an empty carton gets itself bought again.

The lookups, the scanning session and the extras are checked against stand-ins in the tests; the
camera itself can only be tried on a phone.

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

The icons (launcher, and the white shape Android shows in the status bar) are generated from
`art/icon.png`; after changing the art run `python tool/make_icons.py` (Pillow and numpy), and
`--check` says whether the committed files are current.

A release build is signed with the key named in `android/key.properties` (never committed) and
falls back to the debug key without it. Android only installs an update signed with the same key
as the copy already on the phone, so use one key for every release.

## Not built yet

- Timers that keep running with the screen off (the kitchen page's timers stop when the phone sleeps).
- A scan-able code for joining, a home-screen widget, sharing a recipe link into the app.
- Reading the words on a label or shelf tag when a barcode is on no list; turning cups and
  spoonfuls into packets sold by weight; choosing the store by where the phone is.
