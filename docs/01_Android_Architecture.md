# 01: Android Architecture - The Recipe Brain & State Machine

## 1. High-Level Vision
The Android application is the central orchestrator of the Dinner Planner ecosystem. It transitions from a simple recipe viewer to a **Foreground Kitchen Assistant** that manages hardware resources, timers, and voice synchronization to allow for a hands-free cooking experience.

## 2. Windows 10 Development Environment
Since this project is being built on a high-spec Windows 10 gaming machine:
- **IDE:** Use the standard 64-bit Windows version of Android Studio.
- **Virtualization:** Ensure **VT-x (Intel)** or **AMD-V** is enabled in the BIOS/UEFI to run the Android Emulator.
- **Hypervisor:** Enable **Windows Hypervisor Platform** in "Windows Features" for maximum emulator performance.
- **Drivers:** Install the **Google USB Driver** via the SDK Manager to sideload the app onto your physical phone for Bluetooth testing.

## 3. Core Technical Stack (2025/2026 Standards)
- **Language:** Kotlin 2.x
- **UI Framework:** Jetpack Compose (for a state-driven, reactive UI).
- **Audio Engine:** Jetpack Media3 (specifically for Audio Focus and Ducking logic).
- **Data Fetching:** Ktor Client (to pull `recipes.json` and `recipes_voice.json` from GitHub Raw URLs).
- **Local Persistence:** Room Database (to cache recipes and "spousal rankings" for offline use).
- **Messaging:** Firebase Cloud Messaging (FCM) to receive "Next" signals from Alexa via AWS Lambda.

## 4. Implementation: The State Machine (MVI)
The app uses a **Model-View-Intent** architecture to ensure the UI always reflects the current cooking progress.
- **`currentRecipe`**: The full object mapped from your `recipes.json`.
- **`currentStepIndex`**: Integer tracking the current block in `recipes_voice.json`.
- **`activeTimers`**: A `StateFlow` observed by the UI for real-time countdowns.
- **`interactionMode`**: Enum { HANDS_FREE, MANUAL, VOICE_SYNC }.

## 5. Audio Management: The "Anti-No-Bueno" Strategy
To play music and instructions on the same Bluetooth speaker:
- **Audio Focus:** Request `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`.
- **Attributes:** Use `USAGE_ASSISTANCE_NAVIGATION_GUIDANCE` and `CONTENT_TYPE_SPEECH`.
- **Ducking Logic:** When the app speaks, it signals Android to lower the Spotify volume by ~60% instead of pausing it.
- **The "Podcast" Gotcha:** Android may not automatically duck if the background app is also speech-based (like a podcast); manual pausing may be required.

## 6. High-Fidelity Kitchen Features
- **Visual Sync:** Uses the `image` URL from your JSON as a full-screen reference.
- **Spousal Recognition:** If `pinkStar` or `blueStar` rankings are present, the app triggers a "Brian" or "Kendra" voice to announce the recipe as a "House Favorite".
- **Hands-Free Proximity:** Uses `Sensor.TYPE_PROXIMITY`.
    - *Logic:* Trigger "Next Step" on a `Near -> Far` transition within 500ms to ignore accidental shadows.
- **Al-Dente Override:** A massive UI button that kills active pasta timers and immediately triggers the "Drain and Serve" voice block.

## 7. Persistence & Reliability (Android 15/16)
- **Foreground Service:** You **must** declare `type="mediaPlayback"` in the Manifest to keep timers alive while the screen is off.
- **Wake Locks:** Use `FLAG_KEEP_SCREEN_ON` only during active cooking.
- **WorkManager:** Use for long-duration tasks (like 6+ hour slow-cooker steps) to bypass Android 15's background timeouts.

## 8. Future Proofing: Live Activities
- **Android 16+:** Architecture supports **Live Updates**—interactive lock-screen widgets that show active timers and a "Next" button, requiring no phone unlock.

## 9. Development & Debugging
- **Hardware Testing:** Bluetooth ducking **cannot** be tested on an emulator; use a physical device paired with the Alexa Echo Show.
- **Bluetooth Latency:** Expect a ~200ms lag. Combine "Beeps" and "Speech" into a single audio buffer to prevent music from "ramping up" between sounds.
- **Logging:** Filter Logcat by `[DINNER_PLANNER_STATE]` to track transitions.
