# Dinner Planner

Live site: [sampanes.github.io/dinner-planner](https://sampanes.github.io/dinner-planner/index.html)

- `index.html` - the recipe vault (browse, search by ingredient, edit in the browser)
- `groupings.html` - the meal shuffler (seeded weekly plan plus grocery list)
- `kitchen.html` - kitchen mode for the Echo Show 10 (Silk browser) and phones, all by tapping: big photo
  picker with "Can't decide?", "What do we have?" (pick ingredients, recipes sort by how many they use),
  who-likes-it and mood/protein chips; one step per screen in large type, Back/Next or swipe, per-step
  timers with an alarm, resume where you left off; rate it when you finish; this week's plan and a
  tap-off grocery list. Open it on the Show with "Alexa, open Silk" and bookmark
  `https://sampanes.github.io/dinner-planner/kitchen.html`; on a phone, "Add to Home screen".
- `recipes/` - one static page per recipe with schema.org Recipe data, generated

## Repo layout

- `docs/` product and architecture docs (start at `docs/README.md`)
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
