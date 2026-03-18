# 01 Kitchen Product Vision

## The feeling to aim for

The assistant should feel like a calm sous-chef.
It should not feel like a chatbot, a smart-home demo, or a command-line interface wearing an apron.

## Real-world usage target

The user is:
- cooking with wet or messy hands
- not looking at the screen all the time
- likely to interrupt themselves
- likely to forget what step they are on
- likely to speak in short fragments

That means the product must tolerate:
- "next"
- "what?"
- "say that again"
- "how much butter"
- "wait, go back"
- "start that timer"
- "what am I waiting on"
- "spaghetti"
- "the bacon one"

## Launch experience

The first interaction should be simple and easy to remember.

Example:
- User: "Alexa, open Dinner Helper"
- Alexa: "Welcome back. You can start a recipe, browse favorites, or search by ingredients."

The user should not need to remember ten startup commands.

## Starting a recipe

### Direct start
- User: "Start chocolate chip cookies"
- Alexa confirms and begins.

### Alias disambiguation
- User: "Start spaghetti"
- Alexa: "I found shrimp spaghetti, bacon spaghetti, and plain spaghetti. Which one do you want?"
- User: "The shrimp one"
- Alexa begins the selected recipe.

### Ingredient-based discovery
- User: "What can I make with sausage and pasta?"
- Alexa surfaces a short ranked list.

## Step delivery style

The assistant should speak briefly by default.
Each step should have at least:
- a short spoken form
- an optional expanded form
- a visible form for Echo Show

Default voice style should be concise and useful.
A short step should sound like:
- "Step 4. Add the onions and cook until soft, about 8 minutes. Want me to start a timer?"

Not like:
- a long paragraph that tries to read the entire recipe card

## Timer behavior

Timers are a core kitchen feature, not a side feature.
The system should support:
- multiple labeled overlapping timers
- references to the most recently offered timer
- timer status questions
- timer cancellation, pausing, and resuming

Examples:
- "Start an oven timer for 18 minutes"
- "Also start a pasta timer for 9 minutes"
- "Yeah, start that timer"
- "How much time is left on the pasta timer?"

## Recovery behavior

A cooking assistant must recover gracefully from interruptions.

Required recovery flows:
- resume current recipe
- restate current step
- restate previous step
- summarize what is left
- answer ingredient quantity questions
- identify active timers

## Echo Show screen behavior

The screen should be glanceable, not busy.
Recommended visual elements:
- recipe title
- current step number and total
- current short step text
- optional detail text on demand
- active timers with names
- simple choice UI during disambiguation

Avoid dense, paragraph-heavy layouts.

## Household usability

The system should work for a second user with minimal coaching.
That means:
- obvious invocation name
- obvious next actions after launch
- forgiving recipe aliases
- common-sense confirmations
- no required login in v1

## A bad experience to avoid

Do not create a flow where the user needs to:
- know exact recipe titles
- memorize many rigid phrases
- recover from ambiguous questions manually
- rely on a phone screen to understand what Alexa is doing
- sit through long readouts of recipes they did not ask for
