# 02 System Architecture

## Recommended architecture

The current recommended architecture is intentionally simple:

1. **Source recipe data in repo**
   - human-authored recipe source files
   - committed to Git

2. **Local normalization/build pipeline**
   - Python scripts transform source recipes into runtime data
   - build scripts validate aliases, timers, and step structure

3. **Generated runtime data**
   - canonical machine-friendly recipe files
   - optimized for Alexa skill use, not for human editing

4. **Alexa custom skill**
   - hosted as an Alexa-hosted skill
   - handles launch, browse, start, step control, search, and timers

5. **Echo Show visual layer**
   - APL templates render the current cooking session
   - visuals are derived from the same session state the voice logic uses

6. **Session persistence**
   - current recipe
   - current step
   - current candidate recipes during disambiguation
   - last offered timer
   - active named timer references
   - last intent context when a yes/no answer is expected

## What is deliberately absent

This architecture does **not** assume:
- Android as orchestration brain
- FCM relay hops
- Alexa-for-Apps bridge behavior for core runtime control
- a custom multi-service cloud backend on day one

## Runtime flow

### Recipe start flow
1. user launches skill
2. user asks to start a recipe by name or alias
3. skill resolves exact match or disambiguates
4. session state is created
5. step 1 is spoken and displayed

### Step progression flow
1. user says next / back / repeat
2. skill updates current step index
3. skill returns speech + APL response from the new current state

### Timer-offer flow
1. recipe step includes a timer suggestion
2. Alexa asks whether to start it
3. session stores last offered timer context
4. user says yes / no / start that timer
5. skill resolves the reference and creates or skips timer

### Ingredient-search flow
1. user requests recipes using one or more ingredients
2. skill matches normalized ingredient index
3. skill returns a short ranked list
4. user selects a recipe
5. cooking session starts

## Key architectural rule

**There must be exactly one canonical representation of session state at runtime.**

The voice reply and the visual reply should both be generated from that same state.
This prevents voice/screen drift.

## Why normalization matters so much

If recipes remain as large instruction blobs, the runtime skill has to do interpretation on the fly.
That makes behavior harder to test and more expensive to maintain.

If recipes are pre-normalized, runtime logic can stay straightforward:
- read step object
- speak short text
- optionally offer timer
- expose ingredient references
- answer known questions from known fields

## Suggested repo structure

```text
/docs/
/scripts/
  normalize_recipes.py
  validate_runtime_data.py
  generate_aliases.py
  build_runtime_data.py
/data/
  recipes.source.json
  recipes.runtime.json
  ingredients.index.json
  aliases.index.json
/alexa/
  skill-package/
  lambda/
  apl/
```

## Session object sketch

This is conceptual only.
The active cooking session should be able to represent:
- recipe id
- recipe name
- current step index
- total steps
- candidate recipe ids for disambiguation
- last offered timer label and duration
- active timer labels known to the session
- whether a yes/no answer is currently expected
- last topic for follow-up references like "that" or "the other one"

## Future extensibility

This architecture can later support:
- account linking
- favorites per user
- household history
- pantry-aware filtering
- richer visual browse experiences

The important part is that none of those features should force a redesign of the core normalized recipe/session model.
