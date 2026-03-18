# 09 Alexa Platform Constraints and Product Decisions

## Why this document exists

The rest of this doc set already describes the product vision well.
What it needed was one place that turns that vision into **platform-aware decisions**.

This file is the bridge between:
- the calm, hands-free cooking experience you want
- the current Alexa custom-skill platform realities
- the practical product decisions that should follow from those realities

If another human or LLM reads only one file before making Alexa-specific decisions, this should be the one.

## Product thesis in one sentence

Build a **deterministic, recipe-aware Alexa custom skill** that feels conversational because the recipe data and session state are explicit, not because the runtime improvises.

## The big design decision

This project should optimize for **confident kitchen control**, not maximum conversational range.

That means the assistant should be:
- flexible in phrasing
- narrow in domain
- explicit in state
- short in speech
- forgiving in recovery

It should not try to impersonate a general-purpose cooking chatbot.

## Platform-grounded assumptions

These assumptions should be treated as part of the design contract.

### 1. Custom skill + APL is the correct product shape
The experience described in this repo is a custom Alexa skill with Echo Show support, not a website with voice bolted on and not a phone-orchestrated sidecar.

Implication:
- interaction design must fit the custom-skill request/response model
- APL should be treated as a view layer for the same cooking session state
- anything that requires a permanently open rich client should be considered out of scope for v1

### 2. Built-in intents are part of the UX surface
Help, stop, cancel, yes, no, and fallback are not implementation details.
They are part of the product.

Implication:
- every major interaction should have a graceful path through built-ins
- docs and test plans should specify what help/fallback say in each major state
- no flow should require memorizing only custom command wording

### 3. Session state is the center of truth
Alexa interactions are turn-based.
The product therefore lives or dies on how well session context is modeled.

Implication:
- the session object is not just a convenience; it is the runtime product model
- references like "that one" and "start that timer" should be resolved only from explicit, recent state
- if the state does not support a safe interpretation, the skill should clarify instead of guessing

### 4. Persistence should be selective
A cooking assistant benefits from some memory, but not all memory is equally valuable.

Implication:
- persist only household-useful state
- keep turn-by-turn ephemeral state in session
- do not build a complex backend just to preserve information that is only useful for a few seconds

### 5. Timer support is valuable enough to warrant first-class design
For cooking, timers are not a side quest.
They are one of the main reasons voice is better than touch.

Implication:
- timer references, labels, and follow-up prompts deserve explicit schema and test coverage
- timer behavior should be documented as carefully as recipe selection behavior
- normalization should identify timer opportunities ahead of runtime

## Current platform notes that should affect planning

These notes are worth treating as near-constraints unless the platform changes.

### Invocation naming should be decided carefully
The invocation name is part product design and part certification surface.
Practical implications:
- keep it easy to pronounce and easy to remember
- keep it phonetically distinct from common Alexa commands
- prefer plain lower-case words and a short phrase structure
- assume changing it later will be painful, especially once a skill is published and household habit has formed

### Alexa lists are not a v1 dependency
Alexa's list-management path is no longer something this project should build around.
Practical implication:
- do not make shopping-list integration a foundational part of the architecture
- if shopping support ever returns as a priority, treat it as a separate product thread rather than an assumption hidden inside the cooking loop

### Timer APIs have real constraints
Alexa timer behavior is useful, but not unlimited.
Practical implications for this project:
- keep timer durations within Alexa timer limits
- assume a household can already have personal timers running, so your skill cannot behave as if it owns the whole timer universe
- expect failures when timer limits are exceeded and design recovery copy now
- keep timer labels unique and context-rich within a cooking session

### Hosted persistence is enough for v1 memory
Alexa-hosted skills already provide a practical persistence path.
Practical implication:
- resume/history/favorites do not justify a custom backend by themselves
- use hosted persistence first, and revisit only if the actual product requirements outgrow it

### Manual dialog control is the right fit for this product
Alexa supports dialog delegation, but this cooking assistant needs tight control over prompts, state, and screen rendering.
Practical implication:
- prefer manual state-driven dialog management for recipe selection, disambiguation, timers, and recovery
- use the interaction model to help recognition, but keep the product logic in your own explicit session model

## Product decisions that fall out of those assumptions

## Decision 1: the runtime model must be richer than the source recipe format
Your current source recipes include long human-facing instruction blobs.
That is acceptable for authoring, but not sufficient for a great voice product.

Therefore:
- source recipe format may stay fairly forgiving
- runtime recipe format should be stricter and richer
- the docs should continue to privilege runtime shape over source convenience

This is the single most important design choice in the whole repo.

## Decision 2: every recipe needs a spoken identity strategy
A recipe is not just a title.
For Alexa, it also needs:
- a primary spoken title
- household-usable aliases
- distinguishing phrases for disambiguation
- optional browse/search metadata that helps Alexa describe it concisely

A recipe title that looks good on a web card is not automatically a good voice identity.

## Decision 3: disambiguation is a product feature, not an edge case
As the library grows, ambiguity is normal.
The system should therefore be designed to clarify gracefully rather than trying to avoid ambiguity entirely.

That means:
- candidate lists should be ranked and preserved in session state
- recipes should carry the metadata needed to distinguish them in speech
- the docs should assume common follow-ups such as "the shrimp one" or "the baked one"

## Decision 4: screen design should reduce spoken burden
APL should not simply mirror paragraphs from the recipe source.
Its job is to reduce what must be spoken repeatedly.

Therefore the screen should mainly carry:
- current step text
- step number progress
- active timers
- candidate lists
- result lists for browse/search

If the screen tries to become a full recipe article, it will harm the hands-free experience instead of helping it.

## Decision 5: prompt wording must constrain the next turn usefully
In a cooking skill, prompts are part UI and part parser contract.
A prompt that invites unsupported behavior is a broken UI.

Therefore prompts should:
- make the next likely actions obvious
- avoid overly open questions unless you truly support wide answers
- mention only the options that the current state can actually handle

Example:
- good: "You can say next, repeat, or ask how much garlic you need."
- bad: "What would you like to do?"

## Recommended voice UX rules

These should be treated as hard defaults until there is evidence they are wrong.

### Rule 1: speak in kitchen-sized chunks
One turn should rarely contain more than:
- one answer or action confirmation
- one step
- one short next-action hint

### Rule 2: never read an entire long recipe step by default
If a step is large, the runtime should have:
- `speakShort`
- optional `speakLong`
- screen text that can carry more detail

### Rule 3: prefer action-first phrasing
The user usually wants to know what to do now, not hear a paragraph of context.

Better:
- "Add the onions and cook until soft, about 8 minutes. Want me to start a timer?"

Worse:
- "At this point in the recipe, now that your ingredients are prepared, you'll want to begin by adding the onions..."

### Rule 4: acknowledge uncertainty early
When the skill is unsure between a few known options, say so plainly.
That builds trust.

### Rule 5: avoid silent interpretation leaps
If the user says something that could refer to multiple recipes, ingredients, or timers, clarify.
A wrong guess while cooking costs more than one short follow-up question.

## Recommended timer product rules

Timers are important enough to deserve their own compact policy.

### Rule 1: every offered timer needs a label
Good labels are contextual and easy to say:
- pasta timer
- oven timer
- sauce timer
- cookies timer

Bad labels are generic:
- timer one
- cook timer
- step timer

### Rule 2: offered timers should come from recipe data, not live inference
If timer offers are pre-modeled, the voice flow becomes consistent and testable.

### Rule 3: the system must remember the last offered timer explicitly
This is what makes all of these natural:
- yes
- start it
- start that timer
- make it 8 minutes

### Rule 4: overlapping timers are normal
The docs, schema, and handlers should assume more than one timer can be active.
Do not design around a single-timer worldview.

### Rule 5: timer status answers should be compact and sorted
When multiple timers are running, Alexa should give a useful short summary first, then more detail if asked.

Good pattern:
- "You have two timers running: pasta, 3 minutes left, and oven, 11 minutes left."

## Recommended persistence policy

Persistence should support household value without becoming a backend obsession.

### Persist
- last active recipe id
- last active step index
- last-updated timestamp for the cooking session
- recent recipes
- favorites if you keep them

### Do not persist unless necessary
- transient candidate lists from an old clarification
- stale yes/no expectation
- ephemeral phrasing hints
- low-value screen-only state

### Resume policy
When the user reopens the skill and a resumable cooking session exists, the first prompt should usually be something like:
- "You were making shrimp spaghetti and were on step 4. Do you want to resume?"

That is much better than:
- always resuming automatically
- making the user rediscover the recipe manually
- keeping stale sessions alive forever

## Recommended recipe-authoring implications

If this voice product is the priority, recipe authoring should evolve in that direction.

### Each recipe should ideally gain
- a canonical title
- spoken aliases
- short description or differentiator
- normalized ingredient names
- step chunks that sound natural aloud
- timer suggestions where appropriate
- optional ingredient grouping

### The authoring workflow should allow overrides for
- awkward auto-generated aliases
- bad step chunking
- timer labels
- timer durations when the source is vague
- grouped ingredient names

That balance keeps authoring practical while still respecting the voice product.

## Concrete guidance for messy imported recipes

Many recipe sources will not be ready for voice use.
That is expected.

Typical problems:
- multiple actions embedded in one long paragraph
- ingredient mentions that do not line up cleanly with the ingredient list
- vague time ranges with no natural timer offer point
- titles that are too long or too generic for speech
- section structure implied visually but missing in plain text

Recommended response:
- normalize automatically where confidence is high
- surface warnings where confidence is low
- make manual overrides easy
- never rely on runtime improvisation to patch bad source data

## Concrete guidance for search and browse

Search and browse are useful, but they should not overtake the cooking loop.

### Browse should answer
- what should I make tonight?
- show me favorites
- show me pasta
- show me recent dinners

### Ingredient search should answer
- what can I make with sausage and pasta?
- find recipes with bacon
- what can I make with chicken and rice later

### Browse/search should not try to answer in v1
- broad nutritional reasoning
- pantry optimization across many constraints
- open-ended lifestyle coaching

## Decision summary by area

### Identity
- recipes need spoken aliases and differentiators
- invocation name must be household-friendly

### State
- session state is the runtime source of truth
- persistent state should be selective and intentional

### Voice
- default to concise speech
- clarify instead of guessing
- built-in intents must have contextual behavior

### Screen
- APL is a glanceable companion, not a full document reader
- voice and screen must render from the same state transition

### Timers
- first-class feature
- labeled, explicit, and session-mapped
- tested heavily with overlapping cases

### Data pipeline
- stronger normalization beats runtime cleverness
- manual overrides are expected, not a failure

## What another implementer should take away

If you are building this from the docs, the product is **not**:
- a generic chat assistant about cooking
- a phone app hidden behind Alexa
- a recipe website with incidental voice control

It **is**:
- a kitchen-first Alexa skill
- driven by normalized recipe runtime data
- stateful in the places that matter
- heavily optimized for short, natural, interruptible voice turns
- designed for a real household rather than a demo

## Final heuristic

Whenever a design choice is unclear, ask:

**Will this make it easier for a distracted person with messy hands to keep cooking confidently?**

If yes, it probably belongs.
If no, it probably belongs later.
