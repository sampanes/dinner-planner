# Dinner Planner

## Owed: one step on the owner's computer

*Delete this section in the commit that reports the step done.*

**What changed.** The phones no longer take the app from a build made on a computer. GitHub builds
and signs every version with one key, and the phones install it from this repository's releases page.

**Why.** Android only installs an update signed with the same key as the copy already on the phone,
and a build made on a computer is signed with that computer's own debug key. Copies from two
computers cannot update each other: the install is refused, and the only way past that is removing
the app, which clears everything it kept.

**What is owed.** The app's key does not exist yet, so the "Phone app" workflow tests each push and
publishes nothing (0.8.0 is waiting). The key can only be set up where `gh` is signed in as this
repository's owner; the script refuses anywhere else and changes nothing.

1. `python apps/dinner_planner/tool/signing_setup.py --check` says what is set up and changes nothing.
2. Settle on the key. It is chosen once and kept for good, so it is the owner's call:
   - `python apps/dinner_planner/tool/signing_setup.py --adopt-debug-key` makes this computer's
     debug key the app's key. A phone whose copy was installed from this computer then takes the
     signed releases as plain updates and loses nothing. Pick this when a phone holds a copy from
     this computer and its data matters, above all when only one phone uses the app.
   - `python apps/dinner_planner/tool/signing_setup.py` makes a new key, the tidier choice if the app
     is ever published in a store. Every phone that has the app must then remove it once.
   - If this computer's release builds already use a key (`android/key.properties`), the script
     hands that one to GitHub and there is nothing to choose.
3. The script starts the "Phone app" run; a few minutes later release `app-v0.8.0` is at
   `/releases/latest`.
4. On each phone, open that page and install the APK over the copy it has. If Android refuses,
   nothing is lost: that copy was signed on another computer, and "Moving a phone to the signed
   app" in `apps/dinner_planner/README.md` moves it without losing the shared plan.
5. Keep `private/keys/` (git ignores it; it is the only copy of the key outside GitHub), then delete
   this section and push.

**From then on, for anyone working here, person or agent:**

- Do not put a build made on a computer onto a phone (`adb install`, `flutter install`,
  `flutter run` at a phone). Builds on a computer are for tests and screenshots.
- To ship the app: raise `version:` in `apps/dinner_planner/pubspec.yaml`, push to `main`, then check
  that the "Phone app" run passed and release `app-v<version>` appeared.
- Notes typed on the phones wait for a recipe fix at a computer: "Recipe notes waiting on the
  phones" below.

Live site: [sampanes.github.io/dinner-planner](https://sampanes.github.io/dinner-planner/index.html)

- `index.html` - the recipe vault (browse, search by ingredient, edit in the browser). On a phone a
  tapped recipe opens full screen with a way back; "Cook this" opens it in kitchen mode.
- `groupings.html` - the meal shuffler (seeded weekly plan plus grocery list). Locking a meal keeps it
  in its slot and through every reshuffle; "Send to kitchen" makes the plan this week's row.
- `kitchen.html` - kitchen mode for the Echo Show 10 (Silk browser) and phones, all by tapping: big photo
  picker with "Can't decide?", "What do we have?" (pick ingredients, recipes sort by how many they use),
  who-likes-it and mood/protein chips; one step per screen in large type, Previous/Next or swipe, per-step
  timers with an alarm, resume where you left off; rate it when you finish; this week's plan and a
  tap-off grocery list. Open it on the Show with "Alexa, open Silk" and bookmark
  `https://sampanes.github.io/dinner-planner/kitchen.html`; on a phone, "Add to Home screen".
- `recipes/` - one static page per recipe with schema.org Recipe data, generated
- `apps/dinner_planner/` - the Android app: who cooks which night, reminders on your nights, and a
  plan two phones share. Nothing it holds is written to this repository (`apps/dinner_planner/README.md`).
  The phones install it from this repository's releases, never from a build made on a computer.

## Recipe notes waiting on the phones

Notes written in the phone app ("garlic salt goes in here", on a step or on the whole recipe) are
requests to change a recipe. They wait on the phones until someone at a computer works them in:

    python scripts/house_notes.py --wait 60       # list them, each with the step it is on
    # edit data/source/recipes.json, keeping the recipe's number of card steps
    python scripts/build_runtime_data.py && python -m unittest discover -s tests
    python scripts/house_notes.py --done <slug>   # after the push: clear them on both phones

The first run needs `--link` and the household code from the app's Settings; it is kept in
`private/`, which git ignores. Details: `apps/dinner_planner/README.md`, "Notes that wait for a fix".

## Repo layout

- `docs/` product and architecture docs (start at `docs/README.md`)
- `docs/cooking-with-kids.md` which recipes suit picky eaters, split into a plain and a full-flavor half, or make good first recipes to cook with a child
- `data/source/recipes.json` the human-edited recipe data (ASCII only)
- `data/runtime/` generated runtime data, committed
- `data/reports/validation_report.md` generated build warnings, committed
- `data/cache/` fetched HelloFresh pages and the last ranking, ignored by git
- `data/handoff/next-hellofresh-recipes.md` the next candidates to import, committed, read by nothing live
- `recipes/` generated recipe pages, committed
- `scripts/` build and normalization scripts
- `tests/` pipeline tests
- `clients/alexa/` reserved for a custom Alexa skill (shelved, see `docs/11_Alexa_Platform_Recheck_2026-11.md`)

## Kitchen sync (ratings, "we cooked this", the week's plan)

The site is static, so nothing a device does can write to the repo directly. Instead:

1. A device queues the change in its own storage and shows it at once.
2. It sends the change as a push message to the ntfy.sh topic in `data/source/kitchen.json`
   (install the ntfy app and subscribe to that topic to get a notification for every rating).
3. `.github/workflows/sync.yml` runs `scripts/pull_changes.py` every hour: it reads the topic, writes
   ratings into `data/source/recipes.json` and cooked dinners and the plan into `data/source/log.json`,
   rebuilds and commits. Pages redeploys and every device sees it.
4. ntfy.sh keeps messages about 12 hours; a device re-sends anything not yet committed every few hours.

Sync by hand: `python scripts/pull_changes.py` (or "Run workflow" on the Actions tab). The names on the
pink and blue stars live in `data/source/kitchen.json` under `people`.

## Editing recipes

1. Edit `data/source/recipes.json` (or use the form on `index.html` and download the JSON).
2. Normalize the text and rebuild everything:

   ```bash
   python scripts/normalize_source.py
   python scripts/build_runtime_data.py
   python -m unittest discover -s tests
   ```

3. Read `data/reports/validation_report.md`. A step over 200 characters is too
   long for one spoken turn. `normalize_source.py` already splits a long `- `
   bullet at sentence ends; what remains is a single long sentence, so
   rephrase it in the source.
4. Commit the source, the runtime data, the report and the pages together.

`python scripts/build_runtime_data.py --check` exits non-zero when any
generated file is stale; the tests run the same check.

Instruction layouts the build understands:

- `1. text` paragraphs separated by blank lines
- HelloFresh cards: a number alone on a line starts a step, the short line
  above it is the section name, `- ` lines are the sub-steps, and a trailing
  paragraph is a recipe note

## Finding more recipes like the ones you liked

Most of the recipes are HelloFresh cards, and HelloFresh publishes every
recipe it has ever shipped (about 17,000) with the same studio photo, the
ingredients and the steps. `find_similar.py` ranks that pool against your
star ratings:

```bash
python scripts/find_similar.py             # ~/Downloads/dinner-planner-similar-recipes.html
python scripts/import_hellofresh.py 3 7 12 # the card numbers you want
python scripts/build_runtime_data.py
python -m unittest discover -s tests
```

Each vault recipe pulls toward itself in proportion to its stars (5/5 hard,
2.5 neutral, 0/1 pushes away). A candidate is scored by the three liked vault
recipes it most resembles (whole ingredient names, ingredient words and dish
words, idf-weighted cosine) minus the two disliked ones it most resembles.
HelloFresh's internal menu variants ("[SWAP ...]", "BYOP ...", "W36 R58 ..."),
pages with no customer rating (`--include-unrated` keeps them), dishes you
already have, and near-identical variants of a better candidate are folded
away. The page shows the photo, a "why" line naming the vault recipes that
drove the match and the ingredients they share, and the HelloFresh link; the
importer adds a card unrated, scaled from 2 to 4 servings, in the bare-number
bullet layout the build parses. Fetched pages are cached, so after rating the
new recipes `python scripts/find_similar.py --offline` re-ranks in a second.

The same ranking is also written to `data/handoff/next-hellofresh-recipes.md`,
a committed markdown table that nothing on the site reads. It is the handoff
for the next batch: on any clone, with no cache at all,

```bash
python scripts/import_hellofresh.py --from data/handoff/next-hellofresh-recipes.md 3 7 12
```

fetches those pages and adds them. Without `--from`, card numbers resolve
against this machine's last ranking when there is one, else the handoff.

Every photo url in the source is rewritten by `normalize_source.py` to one
1200x800 crop (`hellofresh.uniform_image_url`), so the vault, the recipe
pages and the Alexa card all show the same shape.

## Recipes on Alexa+

Alexa+ has a personal recipe library that imports from a link. Each generated
page under `recipes/` carries schema.org Recipe JSON-LD for that purpose:
open a recipe in the vault, click "Page", and share that URL with Alexa+ from
the Alexa app share sheet or Alexa.com. Then on the Echo Show: "Alexa, walk me
through <recipe>".

## Browser copy vs repo copy

`index.html` loads `data/source/recipes.json` on every visit. Edits made with
the in-page form live only in that browser's localStorage; a banner appears
when they differ from the repo copy, with "Reload from repo" (discard) and the
download button (keep) as the two ways out.
