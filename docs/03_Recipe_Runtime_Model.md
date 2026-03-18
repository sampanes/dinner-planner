# 03 Recipe Runtime Model

## Why a runtime model exists

Your current source recipes are human-friendly.
The kitchen assistant needs machine-friendly recipe data.

The runtime model is where you earn flexibility.
The more explicit the runtime data is, the less magic the Alexa skill has to invent.

## Source vs runtime

### Source recipe
The editable form in your repo.
Human-friendly, convenient, forgiving.

### Runtime recipe
The generated form used by the skill.
Strict, explicit, validated.
Not meant to be edited by hand except during debugging.

## Minimum recipe-level fields

Each runtime recipe should include at least:
- `id`
- `name`
- `displayName`
- `aliases[]`
- `categories[]`
- `tags[]`
- `servings` if known
- `ingredients[]`
- `steps[]`
- `searchTokens[]`
- `image` if available
- `difficulty` optional
- `totalTimeMinutes` optional
- `favorites` or ranking metadata if you still want that later

## Ingredient model

Each ingredient entry should be normalized enough to support kitchen lookup and recipe search.

Recommended fields:
- `id`
- `displayName`
- `canonicalName`
- `aliases[]`
- `amountText`
- `quantity` optional structured numeric value
- `unit` optional normalized unit
- `preparation` optional
- `group` optional such as dough, sauce, topping

Example goals:
- user asks "how much parmesan"
- skill maps "parmesan" to the correct ingredient record
- skill reads back the human-friendly `amountText`

## Step model

A step is the most important runtime unit.
Each step should ideally represent one meaningful cooking moment.

Recommended fields:
- `index`
- `title` optional short label
- `speakShort`
- `speakLong` optional
- `displayText`
- `ingredientRefs[]`
- `timerSuggestion` optional
- `stepType` optional, such as prep / cook / bake / rest / serve
- `temperature` optional
- `equipmentRefs[]` optional
- `dependsOn[]` optional for advanced flows later
- `tips[]` optional

## Timer suggestion model

Not every timer needs to auto-start.
The recipe runtime should mark opportunities to offer one.

Recommended fields:
- `label`
- `durationSeconds`
- `announceText`
- `autoOffer` boolean
- `allowUserRename` optional

Example:
```json
{
  "label": "oven timer",
  "durationSeconds": 660,
  "announceText": "Bake for 9 to 11 minutes. Want me to start an oven timer for 10 minutes?",
  "autoOffer": true
}
```

## Alias model

Aliases are not just for whole recipes.
You will want aliases for:
- recipe names
- ingredients
- categories
- possibly equipment

Recipe alias strategy should support:
- exact spoken names
- shortened names
- household nicknames
- ambiguity detection

Example:
- "Pork Sausage Cavatappi Bolognese"
- aliases: `sausage cavatappi`, `sausage pasta`, `bolognese pasta`

## Search model

If you want ingredient-based discovery without runtime AI, the runtime data should include enough indexing to rank matches.

Possible fields:
- `searchTokens[]`
- `ingredientIds[]`
- `primaryProtein`
- `primaryCarb`
- `mealType`
- `cuisineHint`

That lets the system answer:
- "What can I make with shrimp and pasta?"
- "Show me desserts"
- "What are my favorites?"

## Validation rules

The build pipeline should fail or warn if:
- two recipes share the same alias exactly
- a recipe has zero usable steps
- a step has no `speakShort`
- timer labels collide within the same recipe in a confusing way
- ingredient names are too ambiguous without aliases
- step text is too long for a good spoken default

## Build outputs

Recommended generated files:
- `recipes.runtime.json`
- `recipe_aliases.json`
- `ingredient_aliases.json`
- `search_index.json`
- `validation_report.md`

## Authoring philosophy

Do not try to infer everything perfectly forever.
It is better to normalize aggressively and then allow manual overrides where needed.
That keeps the system dependable in the kitchen.
