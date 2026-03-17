# 03: Infrastructure & Logic Bridge - The Automation Pipeline

## 1. Overview
This document outlines the "Connective Tissue" linking your GitHub repository, the Alexa Skill, and the Android App. The goal is a zero-maintenance, free-to-run pipeline that automatically turns static recipe data into interactive kitchen intelligence.

## 2. The Python "Gleaner" Sidecar Tool
This script is the bridge that keeps your `recipes.json` static while making the app "smart." It identifies new content and prepares it for verbal delivery.

### Technical Logic:
- **Change Detection:** Load `recipes.json` and compare against `recipes_voice.json`. Only process IDs missing from the voice file.
- **Regex Extraction:** Scan `instructions` for patterns like `\d+-\d+ minutes` (e.g., "9-11 minutes") to automatically generate `timer` objects.
- **LLM Enrichment (Gemini/Claude):** - **Prompt:** "Convert these steps into conversational chunks under 20 words. Identify prep tasks like 'Wash and dry produce' and turn them into 'wait_for_tap' speech blocks".
    - **Output:** A structured JSON array of `speech`, `wait_for_tap`, and `timer` objects.

## 3. GitHub Automation (The Pipeline)
Use **GitHub Actions** to make the generation "invisible" to you.
- **Trigger:** `on: push` targeting `recipes.json`.
- **Action:** 1. Sets up a Python environment.
    2. Runs the Gleaner Tool using a repository secret for LLM API keys.
    3. Commits the updated `recipes_voice.json` back to the `main` branch.
    4. Deploys both files to **GitHub Pages** for public HTTPS access.

## 4. AWS Lambda & Alexa Bridge
A minimalist backend acting as the high-speed messenger for your voice commands.
- **Role:** Receives the `IntentRequest` from Alexa (e.g., `NextStepIntent`), validates your User ID, and forwards the command to your phone.
- **Communication Protocol:** Uses **Firebase Cloud Messaging (FCM)** "High Priority" data messages to wake the Android app and trigger the next step in <200ms.
- **Cost:** $0. This falls entirely within the AWS Lambda and Firebase Free Tiers.

## 5. Implementation "Gotchas" & Safety
- **LLM Rate Limits:** If adding 50 recipes at once, ensure the script handles API throttling.
- **JSON Consistency:** Ensure the "Gleaner" script preserves the `id` from `recipes.json` as the key in `recipes_voice.json` so the Android app can accurately map them.
- **Silent Failures:** If the LLM fails to parse a step, the script should fall back to the raw instruction text rather than leaving a blank step.

## 6. Spinoff Ideas & Future Scalability
- **Pantry Inventory:** Extend the Alexa Skill to allow: "Alexa, tell Dinner Planner we used the last of the cavatappi." (Script updates a `pantry.json` in your repo).
- **Spousal "What's for Dinner?":** A feature where Alexa reads out the highest-ranked recipes (`pinkStar`/`blueStar`) if you can't decide what to cook.
- **Grocery Auto-Gen:** Automatically generate a markdown shopping list based on the `ingredients` field of a selected recipe.
