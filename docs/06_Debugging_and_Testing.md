# 06 Debugging and Testing

## Development environment

Recommended setup:
- VS Code
- ASK Toolkit for VS Code
- local Python environment for normalization scripts
- Alexa Developer Console for model and hosted-skill management
- at least one real Echo device, ideally Echo Show

## Day-to-day workflow

### Data-side work
1. edit source recipe data
2. run normalization/build script
3. inspect validation output
4. fix aliases, timers, or speech text as needed
5. regenerate runtime files

### Skill-side work
1. update handler logic or interaction model
2. test locally in VS Code simulator when possible
3. test in Alexa developer console simulator
4. test on real Echo Show for final behavior

## What usually breaks

Most bugs will not be syntax bugs.
They will be state and UX bugs, such as:
- wrong recipe matched
- disambiguation list lost from session
- yes/no attached to the wrong question
- timer label mismatch
- screen showing the wrong step
- ingredient lookup returning the wrong item
- step wording being too long or awkward when spoken

## Logging strategy

Create logs for:
- incoming intent
- active recipe id
- current step index
- candidate recipe ids
- pending confirmation state
- last offered timer
- timer operations requested
- rendered APL view name

Logs should make it easy to reconstruct the conversation state after a bad interaction.

## Testing layers

### 1. Normalization tests
Focus on deterministic script behavior.

Examples:
- step chunking from long instruction blobs
- ingredient alias generation
- timer extraction and normalization
- duplicate alias detection
- validation failure cases

### 2. Skill logic tests
Focus on handler behavior.

Examples:
- launch response
- exact recipe start
- ambiguous recipe start
- selection after disambiguation
- next/back/repeat behavior
- ingredient quantity answer
- timer-offer follow-up resolution

### 3. Conversation scenario tests
Focus on realistic multi-turn flows.

Examples:
- open skill -> start recipe -> next -> repeat -> timer offer -> yes
- start spaghetti -> disambiguate -> begin recipe
- search by ingredients -> choose result -> cook
- ask ingredient amount in the middle of a step

### 4. Visual tests
Focus on Echo Show readability and state consistency.

Examples:
- long recipe title wrapping
- current-step readability from kitchen distance
- timer list display
- browse list display
- disambiguation choice screen

## Real-device testing matters

The simulator is useful but not enough.
Kitchen behavior must be tested on real hardware because the real problems are:
- speech cadence
- interruptions
- noisy environment
- discoverability of phrasing
- whether the screen is actually glanceable

## Test checklist for every new recipe

Before a recipe is considered ready:
- can it be started by exact name?
- does it have good aliases?
- does the step structure sound natural?
- do ingredient questions work?
- do timer offers make sense?
- are there any ambiguous timer labels?
- does the recipe remain understandable after interruptions?

## Regression mindset

As the recipe library grows, test for:
- alias collisions between recipes
- ingredient alias collisions
- browse lists becoming too large to speak well
- overuse of identical timer labels across confusing contexts

## Practical recommendation

Keep a small stable set of "golden recipes" used for regression testing:
- one very short recipe
- one medium recipe with a single timer
- one long recipe with multiple timers
- one ambiguous-name recipe family like multiple spaghetti dishes
- one dessert or bake recipe

## Conversational test matrix

For every feature, test more than the ideal utterance.
A hands-free kitchen product needs synonym and interruption coverage.

### Recipe start variants
Test all of these patterns:
- "start spaghetti"
- "make spaghetti"
- "cook spaghetti"
- "open shrimp spaghetti"
- "the shrimp one"
- "the first one"

### Step control variants
Test:
- next
- go on
- continue
- back
- previous
- say that again
- repeat that
- where am I

### Ingredient question variants
Test:
- how much garlic
- how much garlic do I need
- what's the garlic amount
- what goes in the sauce
- read the ingredients

### Timer variants
Test:
- start that timer
- yes
- no
- make it 8 minutes
- what timers are running
- how much time is left on the pasta timer
- cancel the oven timer

## Prompt-review discipline

When a turn fails in testing, do not just fix the intent matcher.
Review the prompt that led to the failure.
Often the real bug is one of these:
- the prompt was too long
- the prompt invited language the handler could not support
- the prompt did not narrow the user well enough
- the prompt assumed the user was looking at the screen

## APL-specific testing checklist

For each important screen, verify:
- title fits on smaller Echo Show viewports
- current-step text still works with longer recipe names
- candidate lists remain readable with 3 items
- timers do not visually crowd out the current step
- hint text is present but not noisy
- the visual state updates on every step transition

## Resume and persistence testing

Test both warm-session and cold-session recovery.

### Warm-session cases
- skill remains open and user says resume
- user answers a timer question after a short pause
- user asks for ingredient amount after several step changes

### Cold-session cases
- skill is reopened later the same day
- device stopped listening between turns
- a partial cooking session should offer resume
- a completed recipe should not accidentally resume as active

## Failure-mode tests worth automating later

Once the code exists, prioritize tests for:
- missing session state with an active-looking screen
- stale candidate list after a new search
- stale yes/no state after user changes topic
- stale timer reference after another timer was created
- step index out of bounds after restart/back behavior
- ingredient alias matching the wrong grouped ingredient

## Manual certification-oriented smoke pass

Before treating a build as reviewable, manually verify:
- launch copy is short and clear
- help is contextual
- fallback is contextual
- stop and cancel behave predictably
- the skill never traps the user in a narrow flow
- ambiguity is surfaced clearly instead of guessed silently

## Suggested artifacts to keep from testing

Store lightweight artifacts that future you can compare against:
- sample normalized runtime JSON for golden recipes
- validation reports
- notable simulator transcripts
- a short list of approved spoken prompts for key flows
- screenshots of stable APL states once the UI exists
