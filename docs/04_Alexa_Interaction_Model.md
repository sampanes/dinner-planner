# 04 Alexa Interaction Model

## Skill type

Build this as a **custom Alexa skill** with Echo Show visual support through APL.

## Invocation name

Pick something short, normal, and easy to remember.
Examples worth testing:
- Dinner Helper
- Kitchen Helper
- Dinner Guide

The invocation name matters because the user will say it often.

## Core launch behavior

When the skill opens, the assistant should orient the user quickly.

Recommended welcome pattern:
- "Welcome back. You can start a recipe, browse favorites, or search by ingredients."

Do not dump a long tutorial on launch.

## Primary intents

The exact implementation can evolve, but the product needs these logical behaviors.

### Launch / help
- open the skill
- hear what it can do right now

### Start recipe
- by exact name
- by alias
- by selection after ambiguity

### Browse recipes
- favorites
- recent
- category
- maybe meal type later

### Search recipes
- by one or more ingredients
- possibly by category or tags later

### Session control
- next
- previous
- repeat
- resume
- restart recipe
- where am I

### Ingredient questions
- how much of a specific ingredient
- what ingredients do I need
- what goes in the sauce / topping / dough

### Timer actions
- create timer with label and duration
- accept an offered timer
- cancel / pause / resume timer
- ask for timer status
- ask what timers are running

## Disambiguation design

This project should embrace ambiguity instead of hiding it.

Example flow:
- User: "Start spaghetti"
- Skill finds multiple candidates
- Skill: "I found shrimp spaghetti, bacon spaghetti, and plain spaghetti. Which one do you want?"
- Session stores the candidate list
- User: "The bacon one"
- Skill resolves selection from that short list

Rules:
- keep disambiguation lists short
- prefer top matches first
- if too many matches exist, refine by category or read only the best few

## Yes/no follow-up behavior

The system must track when a yes/no follow-up is expected.
Common cases:
- offered timer
- confirmation of recipe selection
- resume current recipe

That allows natural replies such as:
- "yes"
- "no"
- "yeah, start that timer"
- "no, the other one"

## Timer conversation patterns

### Offered timer
- Skill: "Cook for 8 minutes. Want me to start a pasta timer?"
- User: "Yeah, start that timer."

### Direct timer request
- User: "Start an oven timer for 18 minutes."

### Timer status
- User: "How much time is left on the pasta timer?"
- User: "What timers are running?"

### Overlapping timers
The product should explicitly support multiple labeled timers at once, such as:
- oven timer
- pasta timer
- sauce timer

## Browse behavior

Do not read huge lists of recipe names in one shot.
Good browse slices include:
- favorites
- recent recipes
- desserts
- pasta
- chicken

If a screen is available, speak a short list and show a longer one visually.

## Ingredient search behavior

Example flows:
- "What can I make with shrimp and pasta?"
- "Find me recipes with bacon."

Search should use normalized ingredient aliases and rank results by quality of match.

## Visual behavior with APL

The screen should mirror the session state.
Useful views:
- welcome / browse choices
- disambiguation list
- current step screen
- timers panel
- ingredient recap

## Guardrails

Do not rely on:
- runtime LLM reasoning for intent resolution
- giant free-form conversational scope in v1
- the user remembering exact recipe titles

## Voice UX checklist

Every new interaction path should be tested against these questions:
- can a tired person say this naturally?
- can the skill recover after ambiguity?
- does yes/no work cleanly afterward?
- does the screen match the voice state?
- can another household member guess what to say next?

## Platform constraints that should shape the interaction model

These are practical design constraints, not implementation trivia.
They should actively influence the docs, data model, and authoring workflow.

### 1. Keep the custom skill narrow and explicit
This skill should behave like a guided cooking domain, not like an open-ended assistant.
That means:
- resolve against known recipes, known ingredients, known categories, and known timers
- keep the slot model and handler tree small enough to reason about
- prefer controlled prompts over open prompts whenever there is meaningful ambiguity

### 2. Build around built-in conversational primitives
The skill should plan to support Alexa built-ins such as:
- `AMAZON.HelpIntent`
- `AMAZON.CancelIntent`
- `AMAZON.StopIntent`
- `AMAZON.YesIntent`
- `AMAZON.NoIntent`
- `AMAZON.FallbackIntent`
- `AMAZON.NavigateHomeIntent` where useful on-screen

That does not remove the need for custom intents.
It means the custom intents should cooperate with built-in recovery language instead of fighting it.

### 3. Session context is cheap; long-term memory should be deliberate
Use in-session state for fast conversational context:
- current recipe
- current step
- active disambiguation list
- pending yes/no purpose
- last offered timer
- last question type

Use persistent attributes only for a few household-value items such as:
- last active recipe
- last completed step index for resume
- recent recipes
- favorites if you keep them
- opt-in voice/UI preferences later

Do not make persistence the answer to every interaction problem.
Most cooking turns are short and should be understandable from current session state alone.

### 4. Timer support should feel native, but remain honest about ownership
The system should treat timers as first-class, but the docs and runtime must stay clear about scope:
- use Alexa timer APIs only for timers this skill intentionally creates
- maintain a session-side mapping from recipe context to timer identifiers
- never assume a vague reference like "that one" is safe unless the last timer offer is still active in context
- if the reference is not safe, ask a short clarification question

### 5. Screen and voice must be generated from the same state transition
A voice reply that says "Step 4" while the screen still shows step 3 is a product failure.
All handler docs should assume this rule:
- intent resolves
- session state mutates exactly once
- both speech and APL are rendered from the updated state

## Recommended intent map for v1

This section turns the product vision into a more implementation-ready contract.
The names can change, but the responsibilities should stay stable.

### Launch and orientation
- `LaunchRequest`
  - enter the skill
  - decide whether to offer resume, start, browse, or search
- `HelpIntent`
  - context-aware help, not generic policy text

### Recipe selection
- `StartRecipeIntent`
  - direct name or alias start
- `ChooseRecipeIntent`
  - resolve from the current candidate list
- `BrowseRecipesIntent`
  - favorites / recent / category / meal type later
- `SearchByIngredientIntent`
  - one or more ingredients

### Cooking session control
- `NextStepIntent`
- `PreviousStepIntent`
- `RepeatStepIntent`
- `ResumeCookingIntent`
- `RestartRecipeIntent`
- `WhereAmIIntent`
- `WhatIsLeftIntent`

### Ingredient and recipe questions
- `IngredientAmountIntent`
- `ListIngredientsIntent`
- `ListSectionIngredientsIntent`
  - for sections such as sauce, topping, dough, filling

### Timer intents
- `CreateRecipeTimerIntent`
- `ConfirmOfferedTimerIntent`
- `TimerStatusIntent`
- `PauseRecipeTimerIntent`
- `ResumeRecipeTimerIntent`
- `CancelRecipeTimerIntent`

### Recovery intents
- `FallbackIntent`
  - explain what the user can say next based on context
- `CancelIntent`
  - cancel the current sub-flow, not necessarily the whole cooking session unless that is what the user means
- `StopIntent`
  - leave the session cleanly

## Slot strategy

The slot strategy should match the normalized runtime model.
If the data pipeline is explicit, the interaction model can stay flexible without becoming fuzzy.

### Recipe slots
Use a recipe-name slot that can capture:
- full titles
- generated aliases
- curated household nicknames

But do not rely only on slot resolution.
The runtime should still do its own deterministic alias matching against normalized data.

### Ingredient slots
Ingredient search and ingredient amount questions should use normalized ingredient aliases.
For example, all of these may need to resolve to the same ingredient record:
- parmesan
- parm
- parmesan cheese

### Category slots
Keep category vocabularies small and household-usable.
Examples:
- pasta
- chicken
- beef
- dessert
- soup
- quick dinner

### Ordinal and selection slots
Disambiguation should support compact follow-ups such as:
- the first one
- the second one
- the shrimp one
- the beef one
- the last one

This means the session should preserve enough metadata about the current candidate list to resolve:
- ordinal position
- distinguishing ingredient or protein phrase
- exact displayed title

## Disambiguation policy

To keep the experience calm, disambiguation needs hard rules.

### Spoken list length
Default spoken candidate count should usually be:
- 2 or 3 items

If there are more than 3 plausible candidates:
- read the top 3 aloud
- show more on screen if available
- ask a narrowing question if the match set is still too broad

### Ranking criteria
When ranking ambiguous matches, prefer:
1. exact alias match
2. strong title token match
3. favorites or recent household history
4. shorter, more distinct names
5. recipes with clearer differentiators for spoken follow-up

### Clarification wording
Good clarifications sound like:
- "I found shrimp spaghetti and bacon spaghetti. Which one do you want?"
- "I found three chicken pasta recipes. Do you want the creamy one, the baked one, or the spicy one?"

Bad clarifications sound like:
- long IDs
- internal category names
- too many descriptors at once
- a six-item readout

## Conversation policy by context

### At launch
Prioritize one of these actions:
- resume
- start
- browse
- search

Do not start with a giant menu.
If there is a recent unfinished session, the first prompt should usually acknowledge it.

### During an active cooking step
The most likely user goals are:
- next
- repeat
- go back
- ingredient amount
- timer action
- summary of what is left

The prompt after a step should bias toward those actions.

### During disambiguation
The skill should temporarily narrow the valid language space.
For example:
- "Which one do you want: shrimp spaghetti or bacon spaghetti?"

After that prompt, expect and optimize for:
- ordinal choice
- distinguishing phrase
- yes/no only if a confirmation was explicitly asked

### During a timer offer
The system should privilege fast acceptance.
The user should be able to say:
- yes
- start it
- start that timer
- no
- not now

If the user instead says a different duration, the timer flow should pivot rather than fail.
Example:
- Alexa: "Want me to start a pasta timer for 10 minutes?"
- User: "Make it 8 minutes."

## Response style guide

### Default speech length
Default to one short spoken chunk per turn.
A turn should usually contain:
- the action outcome
- the current step or answer
- one useful next-action hint at most

### When to offer detail
Offer optional expansion for:
- long or dense steps
- ingredient recaps
- section-specific ingredient lists
- recipe summaries before starting

Examples:
- "Step 3: simmer the sauce for 8 minutes. Want the full details?"
- "You need garlic, butter, and parmesan for the sauce. Want the full ingredient list?"

### Confirmation policy
Confirm only when useful.
Always confirm:
- recipe starts after ambiguity was present
- destructive timer actions if the reference is not obvious
- recipe restarts
- exits that would discard current context

Do not over-confirm:
- next
- repeat
- straightforward ingredient amount questions

## Fallback policy

Fallback should be context-sensitive, not generic.

### Good fallback inside an active recipe
- "I didn't catch that. You can say next, repeat, go back, or ask how much of an ingredient you need."

### Good fallback during browse/search
- "You can say start this one, show more pasta recipes, or search by ingredients."

### Good fallback during a timer offer
- "You can say yes, no, or tell me a different timer length."

### Bad fallback
- generic help text that ignores the current screen and current state

## Error and recovery copy

The docs should define the tone of failure cases now so handlers stay consistent later.

### No recipe match
- "I couldn't find a recipe for that. Try a recipe name, browse a category, or search by ingredients."

### Too many weak matches
- "I found too many possibilities for that. Try saying the main ingredient, like shrimp pasta or beef pasta."

### Missing active session
- "There's no recipe in progress. You can start a recipe, browse favorites, or search by ingredients."

### Missing ingredient in current recipe
- "I couldn't find that ingredient in this recipe. You can ask for the full ingredient list if you want."

### Unsafe timer reference
- "I have more than one timer that could match that. Do you mean the pasta timer or the oven timer?"

## APL screen rules for this product

The visual layer is secondary to voice, but still important.
It should carry its weight in a real kitchen.

### Current step screen should show
- recipe title
- current step number and total
- short readable step text
- timer suggestion if one is active or being offered
- active timer chips or compact list
- optional footer hint with one or two likely commands

### Disambiguation screen should show
- short candidate list
- a visible ranking order
- one line of distinguishing metadata when helpful
  - protein
  - style
  - bake vs stovetop
  - prep time band later if available

### Browse/search result screen should show
- compact list of top results
- enough metadata to speak and select naturally
- no clutter that creates extra reading burden

### Layout rule
Optimize for glance distance and short dwell time.
If text would require standing still and reading for several seconds, it is too dense.

## Certification-minded design decisions

Even before implementation, the docs should assume behaviors that are easier to test and explain.

Prefer:
- clear invocation behavior
- clear help text
- short recoverable prompts
- explicit support for built-in cancel/stop/help paths
- predictable timer and resume behavior

Avoid:
- surprise side effects
- overly broad promises about what the skill understands
- prompts that require visual context to answer correctly
- vague references when multiple recipes or timers are in play

## What this interaction model is trying to achieve

The target outcome is not "conversational richness."
It is **fast, forgiving, hands-free cooking control**.

If a future idea makes the interaction model more impressive but less predictable in a noisy kitchen, it should lose.
