# 05 Implementation Roadmap

## Recommended stack

### Languages
- Python for normalization, validation, and build scripts
- TypeScript or JavaScript for the Alexa skill
- JSON for runtime recipe data, interaction model, and APL documents
- Markdown for design docs and validation output

### IDE
- VS Code as the main editor
- ASK Toolkit for VS Code for skill creation, testing, simulator access, and APL preview

## Phase 0: foundation cleanup

Goal: clean repo structure and project direction.

Deliverables:
- replace old docs with the current kitchen-first docs
- choose invocation-name candidates
- pick source and generated data file locations
- decide whether runtime files are committed or generated only in local builds

## Phase 1: recipe normalization pipeline

Goal: make runtime data dependable.

Deliverables:
- source recipe schema
- runtime recipe schema
- step chunking logic
- ingredient normalization logic
- alias generation and manual override support
- timer suggestion support
- validation report output

Success criteria:
- a raw recipe can be turned into a clean runtime recipe
- validation catches obvious ambiguity and speech problems

## Phase 2: minimum skill shell

Goal: launch, help, and recipe start by name.

Deliverables:
- custom skill project
- launch flow
- help flow
- start recipe by exact match
- current-step speech response
- current-step APL screen

Success criteria:
- you can launch the skill and cook through one clean recipe manually

## Phase 3: disambiguation and aliases

Goal: natural recipe selection.

Deliverables:
- recipe alias resolution
- ambiguous-match handling
- candidate-list session state
- selection resolution such as "the shrimp one"

Success criteria:
- "start spaghetti" can branch into a clean clarification flow

## Phase 4: step control and recovery

Goal: survive real kitchen behavior.

Deliverables:
- next
- previous
- repeat
- resume
- where am I
- ingredient quantity questions

Success criteria:
- the system is usable even when the user gets interrupted or distracted

## Phase 5: timer system

Goal: make timers feel first-class.

Deliverables:
- offered timer flow
- labeled overlapping timers
- timer status questions
- timer pause/resume/cancel
- timer names mirrored in session state

Success criteria:
- a recipe can drive multiple overlapping labeled timers cleanly

## Phase 6: browse and ingredient search

Goal: make the assistant useful before a specific recipe is chosen.

Deliverables:
- favorites
- recent recipes
- category browse
- ingredient search
- result ranking and short spoken lists

Success criteria:
- user can find a recipe without already knowing its exact name

## Phase 7: polish and household usability

Goal: make it pleasant for a second user.

Deliverables:
- cleaner wording
- better confirmation prompts
- more forgiving aliases
- visual polish on Echo Show
- household smoke tests

## Later phases

Possible later additions:
- account linking
- favorites per person
- pantry-aware suggestions
- shopping list export
- guided import pipeline for web recipes

## Build philosophy

At every phase, prefer:
- one small reliable loop
- strong validation
- explicit state
- real-device testing

over:
- clever architecture
- many partially-finished flows
- runtime guesswork

## Recommended execution order inside each phase

Each phase should be delivered in this order whenever possible:
1. update docs/spec for the behavior
2. update source/runtime schema if needed
3. add or adjust validation rules
4. build the smallest handler or pipeline slice
5. test with one golden recipe
6. test the exact same flow on at least one messy real recipe
7. only then expand coverage

This prevents building handlers on top of vague assumptions.

## Definition of done for every phase

A phase is not done just because the happy path works once.
A phase is done when all of the following are true:
- the behavior is documented clearly enough that another person could continue it
- the runtime data required by the behavior is explicit and validated
- the handler output is understandable by voice alone
- the screen mirrors the same state correctly
- at least one interruption or ambiguity path has been tested
- there is a known regression recipe or scenario for the feature

## Recommended golden-recipe set

Use a stable set of recipes to keep the roadmap honest.
Each phase should prove itself against at least part of this set.

### Golden recipe A: very short recipe
Use for:
- launch/start flow
- step progression
- repeat and previous

### Golden recipe B: one timer recipe
Use for:
- timer suggestion
- yes/no resolution
- timer status

### Golden recipe C: multi-timer recipe
Use for:
- overlapping timer management
- timer name collisions
- summary of active timers

### Golden recipe D: ambiguous-name family
Use for:
- alias ranking
- candidate list handling
- "the shrimp one" / "the baked one" style selection

### Golden recipe E: dense or messy source recipe
Use for:
- normalization resilience
- long-step chunking
- ingredient alias cleanup

## Roadmap risks worth planning for now

### Risk: source recipes are too messy for good spoken steps
Mitigation:
- fail or warn early in normalization
- allow manual step overrides
- keep authoring notes separate from spoken text

### Risk: aliases become unmanageable as the library grows
Mitigation:
- maintain generated aliases and curated overrides separately
- add duplicate-alias reporting early
- preserve a per-recipe explanation for why an alias exists

### Risk: timer UX becomes confusing before it becomes useful
Mitigation:
- standardize timer labels now
- define which timers can be auto-offered
- reject ambiguous timer labels in validation

### Risk: browse/search becomes verbose
Mitigation:
- cap spoken result counts
- rank aggressively
- push longer lists to screen rather than voice

## Explicit v1 exit criteria

The project should not claim a usable v1 until a real household can do all of the following without coaching:
- open the skill naturally
- start a recipe by common name or alias
- recover after ambiguity
- move forward, backward, and repeat steps
- ask for ingredient amounts mid-session
- accept and manage at least one timer cleanly
- recover after an interruption and resume cooking
- understand what the screen means from across the kitchen

## What not to do during the roadmap

Do not let these postpone the core product loop:
- account systems before shared-household flow works
- free-form AI conversation before normalized Q&A works
- broad import automation before one manual authoring pipeline feels solid
- visual polish before state correctness is reliable
- backend expansion before the Alexa-hosted path is actually limiting you
