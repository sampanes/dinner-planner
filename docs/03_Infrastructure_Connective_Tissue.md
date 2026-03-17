# 03: Infrastructure & Logic Bridge - The Hybrid Automation Pipeline

## 1. Overview
This document outlines the "Connective Tissue" linking the GitHub repository, Alexa Skill, and Android App. It utilizes a **Human-in-the-Loop** staging process to ensure high-quality voice data without the complexity or cost of direct API billing.

## 2. The Python "Gleaner" Staging Tool
Located in `/scripts/gleaner.py`, this script is the bridge that keeps `recipes.json` static while generating the "Work Order" for your AI assistant.

### Technical Logic & "Amnesia-Proofing":
- **Change Detection:** Scans `recipes.json` and compares against `recipes_voice.json`. It identifies IDs that exist in the source but are missing from the voice sidecar.
- **Auto-Overwrite/Cleanup:** Every time it runs, it wipes `PROMPT_STAGING.md` and regenerates it fresh. If everything is synced, it deletes the staging file entirely to prevent "ghost data" errors.
- **The Staging Manifesto:** It generates a single Markdown file containing:
    1. **System Instructions:** Tone (Brian/Kendra), chunking rules (15 words), and mandatory `wait` blocks.
    2. **Raw Data:** The full JSON object for each missing recipe so the LLM can see `image` URLs and `pinkStar/blueStar` rankings for flavor text.

## 3. The "Troglodyte CLI" Workflow
This project favors CLI-driven manual control over automated cloud bots to prevent merge conflicts.
- **Step 1:** Add recipe to `recipes.json` and run `python scripts/gleaner.py`.
- **Step 2:** Feed the resulting `PROMPT_STAGING.md` to a Chat LLM.
- **Step 3:** Paste the JSON output into `recipes_voice.json`.
- **Step 4:** Git commit and push to GitHub Pages.

## 4. AWS Lambda & Alexa Bridge
A minimalist backend acting as the high-speed messenger for voice commands.
- **Role:** Receives the `IntentRequest` from the Echo Show, validates the User ID, and forwards the command via a **Firebase Cloud Messaging (FCM)** "High Priority" message to the Android phone.
- **Latency Target:** <200ms to ensure the "Next Step" response feels snappy in a busy kitchen.
- **Cost:** $0 (Within AWS Lambda and Firebase Free Tiers).

## 5. Implementation "Gotchas" & Safety
- **Git Hygiene:** Ensure `PROMPT_STAGING.md` is added to `.gitignore` so temporary work orders never clutter the remote repository.
- **Pre-Commit Guard:** Use the `.git/hooks/pre-commit` script to block pushes if `recipes.json` has been updated but the voice sidecar hasn't been synced.
- **Erase-to-Reset:** If a voice sidecar output is poor, delete that specific ID from `recipes_voice.json`. The Gleaner will automatically catch the difference and re-generate a new prompt.

## 6. Spinoff Ideas & Future Scalability
- **The Merger Script:** A proposed `merger.py` that accepts AI JSON output via CLI input and automatically injects it into `recipes_voice.json` to avoid opening large files.
- **Pantry Integration:** "Alexa, tell Dinner Planner we used the last of the onions." (Updates a `pantry.json` in the repo).
- **Spousal Suggestions:** A voice feature where Alexa suggests recipes based on the highest `pinkStar`/`blueStar` rankings when you can't decide what to eat.