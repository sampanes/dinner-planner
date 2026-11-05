# Data Layout

This directory is the contract between authoring, build scripts, and clients.

- `source/recipes.json` is the human-edited recipe data. ASCII only; run
  `python scripts/normalize_source.py` after pasting anything in.
- `runtime/` holds generated files committed to Git for review and for any
  client (recipe pages today, a voice client if one ever exists).
- `reports/validation_report.md` is the generated list of build warnings.
- `handoff/next-hellofresh-recipes.md` is the last `scripts/find_similar.py`
  ranking, committed as the handoff for the next import
  (`scripts/import_hellofresh.py --from ...`). Nothing reads it at runtime.
- `cache/` (ignored) holds fetched HelloFresh pages and the ranking as JSON.

The web pages (`index.html`, `groupings.html`) read `source/recipes.json`
directly. The generated recipe pages under `/recipes` are built from the
runtime data.

## Runtime recipe shape

`runtime/recipes.runtime.json` is a list of recipes:

- `id`, `name`, `displayName`, `slug`, `pageUrl`, `image`, `aliases`,
  `searchTokens`, `sourceStars`
- `ingredients[]`: `id`, `displayName`, `canonicalName`, `aliases`,
  `amountText`, `text` ("400g spaghetti")
- `steps[]`: one entry per spoken chunk. `index` is the runtime position,
  `sourceStep` is the number on the card, `section` is the HelloFresh-style
  heading when there is one, `speakShort` and `displayText` are the text,
  `ingredientRefs` and `timerHints` are heuristics.
- `notes[]`: card text that is not a step (for example a doneness note).

`runtime/aliases.index.json` and `runtime/ingredients.index.json` map an
alias or canonical ingredient name to recipe ids.
