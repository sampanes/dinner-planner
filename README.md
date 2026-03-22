[sampanes.github.io/](https://sampanes.github.io/dinner-planner/index.html)

## Repo Layout

- `docs/` product and architecture docs
- `data/source/` human-edited recipe data
- `data/runtime/` generated runtime artifacts committed to Git
- `data/reports/` generated validation output
- `scripts/` normalization and build scripts
- `clients/alexa/` future Alexa skill workspace

## Phase 0 Notes

The current static site still runs from the repo root so the existing deployment does not break.

Build the first-pass runtime artifacts with:

```bash
python scripts/build_runtime_data.py
```
