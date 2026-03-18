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
