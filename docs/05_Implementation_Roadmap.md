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
