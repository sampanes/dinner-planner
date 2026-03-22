# Alexa Client

Phase 0 creates the permanent Alexa workspace without forcing implementation details too early.

- `skill-package/` will hold the interaction model and ASK metadata.
- `lambda/` will hold the request handlers and session-state logic.
- `apl/` will hold Alexa Presentation Language documents and assets.

This client should consume generated runtime data from `data/runtime/`, not raw source recipes.
