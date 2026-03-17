# 02: Alexa & Voice Interface - The Interactive Bridge & Personality Tuning

## 1. Overview
This document outlines the Private Developer Skill that turns the Echo Show into a kitchen-aware interface. It handles Natural Language Understanding (NLU) to map verbal commands to app actions and provides high-quality, persona-driven speech output via Alexa hardware.

## 2. Interaction Model (The "If/Else" Brain)
We define specific **Intents** to map human phrases to technical triggers.

| Intent Name | Sample Utterances | Data Sent to App |
| :--- | :--- | :--- |
| `NextStepIntent` | "Next step", "What's next?", "I'm ready" | `action: MOVE_NEXT` |
| `RepeatStepIntent` | "What was that?", "Say again", "Repeat" | `action: REPEAT` |
| `ActionConfirmedIntent` | "I strained the pasta", "Onions are chopped" | `action: CONFIRM_TASK`, `item: {Ingredient}` |
| `TimerStatusIntent` | "How much time?", "Check the timer" | `action: GET_TIMER` |

### The "Slot" Strategy
To handle "human terms" without expensive LLM calls, use **Custom Slot Types** for ingredients and actions.
- **Slot `{Ingredient}`:** Dynamically populated from your `ingredients` list (e.g., "zucchini", "cavatappi").
- **Slot `{Action}`:** Common kitchen verbs ("strained", "halved", "chopped").

## 3. Speech Synthesis (SSML) & Personality
To ensure the assistant sounds like a "robot friend" rather than a computer, we use Speech Synthesis Markup Language (SSML).

- **Voice Selection:** Use `<voice name="Brian">` (British Butler) or `<voice name="Kendra">` (Professional US).
- **Prosody Tuning:** Use `<prosody rate="92%" pitch="medium">` to prevent instructions from feeling rushed during frantic cooking moments.
- **Intelligent Reminders:** Instead of a generic beep, Alexa uses the `name` field: "The timer for your **Chocolate Chip Cookies** is done. Ready to take them out?".
- **Contextual Pro-Tips:** For complex steps like "Roast Zucchini," Alexa can inject tips gleaned from your text: "Remember to toss them halfway through for even browning!".

## 4. Visuals (APL - Alexa Presentation Language)
The Echo Show leverages your `example_recipes.json` data for a high-end visual experience.
- **Background:** The `image` URL is used as a full-screen blurred backdrop or a side-panel reference.
- **Quality Badges:** Display the `pinkStar` and `blueStar` rankings as "Spousal Approval" icons in the header.
- **Dynamic Recipe Card:** - **Main Body:** Extra-large font for the current instruction.
    - **Progress:** A "Step X of Y" counter.
    - **Overlay:** A countdown circle that appears automatically when a `timer` block is triggered in `recipes_voice.json`.

## 5. Alexa for Apps Implementation
- **The Local Hand-off:** When an intent is triggered, the Alexa Skill sends a custom URI scheme (e.g., `dinnerplanner://update?step=next`) to the Android device.
- **Bi-Directional Sync:** If you manually tap "Next" on the Android app, the phone sends a message to Alexa to update the Echo Show's screen and announce the new step.
- **Fallthrough:** If the app is closed, Alexa prompts: "Please open Dinner Planner on your phone so I can show you the next step."

## 6. Development "Gotchas" & Troubleshooting
- **Endpoint Latency:** If using AWS Lambda, ensure it is in the same region as your Alexa account to minimize "Thinking..." delays.
- **Acoustic Interference:** Kitchens are noisy (running water, sizzling pans). **Tip:** Use the "Expect Response" flag in your skill code to keep the microphone open for a few seconds after an instruction if a "Yes/No" is required.
- **Accent Mapping:** If you choose a British voice (Brian), ensure your SSML uses British spellings or pronunciations (e.g., "Al-yoo-min-ee-um") for consistency.
