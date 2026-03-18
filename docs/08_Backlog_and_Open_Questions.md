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

## Near-term backlog

### Documentation
- add concrete schemas and examples later
- add voice copy guidelines
- add APL screen sketches

### Recipe pipeline
- manual alias override file
- ingredient alias normalization rules
- timer suggestion extraction helpers
- validation report formatter

### Skill behavior
- browse favorites
- browse recent recipes
- ingredient search ranking
- resume previous recipe
- ingredient amount questions

### Timer UX
- consistent timer naming rules
- mapping offered timers to user follow-ups
- handling multiple timers with similar labels

### Visuals
- welcome screen
- disambiguation screen
- current-step view
- active-timers panel
- ingredient list view

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
