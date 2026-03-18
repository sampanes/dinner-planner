# 08 Backlog and Open Questions

## Current open questions

### Invocation name
Pick a short final name and test it out loud.
Candidates should sound natural after "Alexa, open ..."

### Source schema
Decide whether the source format remains one big `instructions` field or whether the source format itself should become more structured over time.

### Generated files strategy
Decide whether generated runtime files live in the main branch, a build artifact path, or both.

### Alias authoring
Decide how much alias generation is automatic vs manually curated.

### Validation severity
Decide which issues are warnings and which should fail the build.

## Recommended answers unless new information appears

These are the current best-fit answers based on the rest of the doc set.
Treat them as defaults, not eternal law.

### Invocation name default
Prefer a short two-word invocation with strong household clarity.
Current best candidate shape:
- a simple noun + helper/guide pattern

Recommendation:
- pick the top 2 or 3 names
- say them out loud repeatedly in realistic phrases
- reject any name that feels awkward after "Alexa, open ..."
- favor memorability over cleverness

### Source schema default
Keep authoring flexible, but move toward more structure over time.
Recommendation:
- keep a forgiving source format for now
- allow one large instruction field if needed
- generate a stricter runtime model from it
- add manual overrides for steps, aliases, and timers before forcing source authors into a rigid schema

### Generated-files default
Commit generated runtime files in the repo.
Recommendation:
- keep source and generated files side by side in version control
- treat generated files as reviewable artifacts
- rebuild them locally during authoring
- revisit this only if build outputs become too large or noisy

### Alias-authoring default
Use hybrid alias management.
Recommendation:
- generate obvious aliases automatically
- preserve a manual override file for household language and edge cases
- fail builds on exact collisions that would cause unreliable starts
- explain in validation output which alias won and why

### Validation-severity default
Bias toward stronger failures than a normal content pipeline would.
Recommendation:
- fail on issues that would create incorrect or unsafe voice behavior
- warn on issues that reduce polish but still allow understandable cooking

Likely build failures:
- duplicate recipe aliases
- missing `speakShort`
- empty or unusable step list
- ambiguous timer labels in one recipe
- step references to missing ingredients where lookup is expected

Likely warnings:
- long spoken text
- weak alias quality
- sparse metadata for browse/search
- missing image or optional display detail

## Near-term backlog

### Documentation
- add concrete schemas and examples later
- add voice copy guidelines
- add APL screen sketches
- document timer naming conventions
- document resume-policy edge cases

### Recipe pipeline
- manual alias override file
- ingredient alias normalization rules
- timer suggestion extraction helpers
- validation report formatter
- grouped-ingredient support such as sauce / topping / filling

### Skill behavior
- browse favorites
- browse recent recipes
- ingredient search ranking
- resume previous recipe
- ingredient amount questions
- contextual fallback wording

### Timer UX
- consistent timer naming rules
- mapping offered timers to user follow-ups
- handling multiple timers with similar labels
- allowing user-modified durations when accepting an offered timer

### Visuals
- welcome screen
- disambiguation screen
- current-step view
- active-timers panel
- ingredient list view
- browse/search results screen

## Important unresolved design edges

These are the questions most likely to create downstream rework if ignored.

### How much recipe detail should be spoken by default?
Recommendation:
- default to concise `speakShort`
- expose `speakLong` only on demand or for dense steps

### How should grouped ingredients work?
Recommendation:
- support optional ingredient groups in runtime data
- let users ask for "the sauce" or "the topping"
- avoid making grouped sections mandatory for every recipe

### How aggressive should search ranking be?
Recommendation:
- heavily favor exact ingredient overlap and exact aliases first
- keep spoken result counts short
- use the screen for longer ranked lists

### What counts as a resumable session?
Recommendation:
- an interrupted in-progress recipe is resumable
- a clearly finished recipe is not auto-resumed as active
- the resume offer should mention recipe name and step number when known

### How opinionated should timer offers be?
Recommendation:
- auto-offer only when the recipe strongly implies a useful timer
- default label should come from recipe context
- let the user accept, decline, or adjust the duration

## Later ideas

These are explicitly later ideas, not current commitments:
- pantry integration
- shopping list mode
- per-user favorites
- account linking
- recipe import assistants
- nutrition overlays
- household ratings and feedback loops

## Guardrail reminder

The project should not grow faster than the normalized recipe/session model can support.
Whenever a new feature is proposed, ask whether it strengthens the kitchen experience or merely makes the architecture look more interesting.
