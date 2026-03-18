# 00 Project Direction

## Purpose

Dinner Planner is being redesigned as a **kitchen-first Alexa cooking system**, not as a general recipe website with voice bolted on later.

The system should help one or two people cook real meals with messy hands, fragmented attention, and minimal patience for fiddly UI.

## Core outcome

A user should be able to say:
- "Alexa, open Dinner Helper"
- "start spaghetti"
- "the shrimp one"
- "next"
- "repeat that"
- "how much garlic"
- "yeah, start that timer"
- "what timers are running"
- "what can I make with sausage and pasta"

…and have the system respond in a calm, obvious, household-usable way.

## Product principles

### 1. Voice is primary in the kitchen
Echo Show is the main kitchen interaction surface.

### 2. The cooking session is the source of truth
The active session owns current recipe, current step, offered timer context, timer mapping, pending disambiguation, and recent conversation context.

### 3. Normalization beats runtime cleverness
Do as much work as possible before runtime.
- clean ingredients
- split steps
- create aliases
- mark timer opportunities
- assign categories and tags
- create recipe-level browse/search metadata

### 4. Cheap and durable wins over fancy
Prefer static data, deterministic handlers, and Alexa-hosted infrastructure over custom paid services.

### 5. Shared-household usability matters
The system should be understandable by another adult without needing a special training manual.

## Non-goals

The following are not part of the current mainline architecture:
- phone-hidden orchestration
- deep mobile app coupling
- real-time sync between multiple rich clients from day one
- paid AI interpretation of recipes at runtime
- public multi-tenant SaaS scale design

## What the system is

This is best thought of as a **precompiled cooking assistant**:
- you author recipes in your repo
- local scripts normalize them into a runtime-friendly representation
- Alexa skill logic consumes that runtime representation
- Echo Show speaks and displays the cooking session

## What success looks like

A new recipe can be added with a predictable author workflow:
1. add or edit source recipe content
2. run normalization/build scripts locally
3. validate any warnings
4. commit the generated runtime files
5. use the recipe by name or alias on Alexa the same day

## High-confidence v1 feature set

- launch the skill naturally
- start a recipe by exact name or alias
- disambiguate between similar names
- advance, repeat, go back, resume
- hear ingredient amounts during cooking
- create and manage labeled overlapping timers
- browse favorites, recent recipes, and categories
- search recipes by one or more ingredients
- show readable current-step visuals on Echo Show

## Features intentionally deferred

- personal accounts and account linking
- pantry inventory tracking
- shopping list sync
- phone companion app beyond debugging/admin use
- fully automatic import of arbitrary web recipes
- free-form conversational kitchen QA beyond the known recipe model
