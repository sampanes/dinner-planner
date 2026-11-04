# Dinner Planner

Live site: [sampanes.github.io/dinner-planner](https://sampanes.github.io/dinner-planner/index.html)

- `index.html` - the recipe vault (browse, search by ingredient, edit in the browser)
- `groupings.html` - the meal shuffler (seeded weekly plan plus grocery list)
- `recipes/` - one static page per recipe with schema.org Recipe data, generated

## Repo layout

- `docs/` product and architecture docs (start at `docs/README.md`)
- `data/source/recipes.json` the human-edited recipe data (ASCII only)
- `data/runtime/` generated runtime data, committed
- `data/reports/validation_report.md` generated build warnings, committed
- `recipes/` generated recipe pages, committed
- `scripts/` build and normalization scripts
- `tests/` pipeline tests
- `clients/alexa/` reserved for a custom Alexa skill (shelved, see `docs/11_Alexa_Platform_Recheck_2026-11.md`)

## Editing recipes

1. Edit `data/source/recipes.json` (or use the form on `index.html` and download the JSON).
2. Normalize the text and rebuild everything:

   ```bash
   python scripts/normalize_source.py
   python scripts/build_runtime_data.py
   python -m unittest discover -s tests
   ```

3. Read `data/reports/validation_report.md`. A step over 200 characters is too
   long for one spoken turn; split it in the source.
4. Commit the source, the runtime data, the report and the pages together.

`python scripts/build_runtime_data.py --check` exits non-zero when any
generated file is stale; the tests run the same check.

Instruction layouts the build understands:

- `1. text` paragraphs separated by blank lines
- HelloFresh cards: a number alone on a line starts a step, the short line
  above it is the section name, `- ` lines are the sub-steps, and a trailing
  paragraph is a recipe note

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
