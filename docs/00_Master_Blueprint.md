# 00: Master Blueprint - The Dinner Planner Ecosystem

## 1. Executive Summary
The Dinner Planner Ecosystem is a multi-device kitchen assistant that transforms a static list of recipes into an interactive, voice-guided experience. It leverages an Android App for logic, an Echo Show for the "Kitchen Interface," and GitHub/AWS for the automation backbone.

## 2. System Map & Connectivity
This project relies on three distinct "nodes" communicating in a loop:



1. **Data Source (GitHub):** Hosts `recipes.json` (manual entries) and `recipes_voice.json` (auto-generated).
2. **The Brain (Android):** Manages the recipe state, active timers, and coordinates audio focus to "duck" background music.
3. **The Voice/Eyes (Echo Show):** Handles verbal commands ("I strained the pasta") and displays "Visual Cards" with images and spousal rankings.

## 3. Data Flow & The "Zero-Change" Rule
The original `recipes.json` remains the **only** file you edit manually.
- **Trigger:** A Git Push triggers a Python "Gleaner" script.
- **Enrichment:** The script identifies durations (e.g., "9-11 minutes") and prep steps (e.g., "Wash and dry produce") to create voice blocks.
- **Output:** A `recipes_voice.json` sidecar is created and served via GitHub Pages.

## 4. Hardware Handshake (The "Anti-Audio-Split" Config)
- **Phone:** Connects to Echo Show via **Bluetooth Speaker Mode** for unified Audio Ducking.
- **Echo Show:** Receives visual APL cards via **Alexa for Apps** and audio via the **Private Developer Skill**.

## 5. Project Startup Checklist (The "Amnesia" Reboot Guide)

### Hardware & OS Setup (Windows 10 Gaming Rig)
- [ ] **BIOS:** Ensure Virtualization (VT-x or AMD-V) is ENABLED.
- [ ] **Windows Features:** Enable "Windows Hypervisor Platform" for high-speed emulator performance.
- [ ] **Android Studio:** Download the 64-bit Windows version; install the "Google USB Driver" for physical device debugging.
- [ ] **Git:** Install Git for Windows and clone the `dinner-planner` repository.

### Development Accounts & API Keys
- [ ] **Amazon Developer:** Create a free account to host the Private Developer Skill.
- [ ] **AWS Console:** Set up the Free Tier for the Lambda "Middleman."
- [ ] **Firebase:** Create a project for Firebase Cloud Messaging (FCM) to talk to the phone.
- [ ] **LLM API:** Keep your Gemini/Claude API keys in GitHub Repository Secrets for the automation script.

### Contextual "Brain Dumps"
- **The "Stars":** Remember that `pinkStar` and `blueStar` are spousal rankings used to trigger unique voice prompts for "House Favorites".
- **The "No Bueno" Fix:** Always route audio through Bluetooth, not Spotify Connect, or the ducking logic will fail.
- **The Accents:** Use SSML tags to give Alexa a "Brian" or "Kendra" persona for specific recipe steps.

## 6. Implementation Roadmap
- **Phase 1:** Build the "Manual Static" MVP (JSON fetch + TTS).
- **Phase 2:** Implement the **Proximity Sensor** "wave" gesture.
- **Phase 3:** Deploy the **GitHub Action** for automated voice generation.

## 7. Key Libraries
- **Android:** Jetpack Media3, Compose, Room, FCM.
- **Alexa:** APL, Alexa for Apps SDK.
- **Backend:** AWS Lambda, Python `recipe-scrapers`.
