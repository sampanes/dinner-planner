# Data Layout

This directory is the contract between authoring, build scripts, and clients.

- `source/` contains human-edited recipe data.
- `runtime/` contains generated files committed to Git for review and Alexa use.
- `reports/` contains generated validation output and other build artifacts worth reviewing.

The current web app reads from `data/source/recipes.json`.
The Alexa path should read from `data/runtime/` once the runtime model grows into the full documented schema.
