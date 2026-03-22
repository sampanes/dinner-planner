import json
import os
import sys

"""
GLEANER.PY - The Staging Area Generator (V4: Modular)
--------------------------------------
Usage:
  python gleaner.py          -> Calls main() to generate PROMPT_STAGING.md
  python gleaner.py --check  -> Calls checker_mode() for Git Hooks
"""

RECIPES_PATH = "../recipes.json"
VOICE_PATH = "../recipes_voice.json"
STAGING_FILE = "../PROMPT_STAGING.md"
DOCS_REF = "docs/02_Alexa_Voice_Interface.md"

def load_json(path):
    if not os.path.exists(path):
        return {} if "voice" in path else []
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def get_missing_recipes():
    """Logic to find recipes missing from the voice sidecar."""
    recipes_data = load_json(RECIPES_PATH)
    voice_data = load_json(VOICE_PATH)
    return [r for r in recipes_data if str(r.get('id')) not in voice_data]

def checker_mode():
    """Strictly for Git Hooks: Exits with 1 if out of sync."""
    print("--- Dinner Planner: Sync Check ---")
    missing = get_missing_recipes()
    if missing:
        print(f"[!] FAIL: {len(missing)} recipe(s) missing from {VOICE_PATH}.")
        sys.exit(1)
    else:
        print("[✓] PASS: Everything is in sync.")
        sys.exit(0)

def main():
    """Standard Mode: Generates the PROMPT_STAGING.md file."""
    print("--- Dinner Planner: Staging Prompt Generator ---")
    missing = get_missing_recipes()

    if not missing:
        print("Everything is up to date.")
        if os.path.exists(STAGING_FILE):
            os.remove(STAGING_FILE)
            print(f"Cleaned up old {STAGING_FILE}.")
        return

    with open(STAGING_FILE, 'w', encoding='utf-8') as f:
        f.write("# LLM WORK ORDER: Dinner Planner Voice Sidecar\n\n")
        f.write("## SYSTEM INSTRUCTIONS\n")
        f.write(f"- Reference: {DOCS_REF} for tone.\n")
        f.write("- Break instructions into 15-word chunks for 'Brian' persona.\n")
        f.write("- Create 'timer' objects for all 'minutes' mentions.\n")
        f.write("- Every 'speech' block MUST be followed by a 'wait' block.\n")
        f.write("- Use 'pinkStar' and 'blueStar' values for flavor text.\n")
        f.write("- RETURN ONLY A SINGLE JSON OBJECT where keys are the Recipe IDs.\n\n")
        
        f.write("## RECIPES TO PROCESS\n")
        for recipe in missing:
            f.write(f"### ID: {recipe['id']} | {recipe['name']}\n")
            f.write("```json\n")
            f.write(json.dumps(recipe, indent=2))
            f.write("\n```\n\n")

    print(f"SUCCESS: {STAGING_FILE} generated with {len(missing)} recipes.")

if __name__ == "__main__":
    if "--check" in sys.argv:
        checker_mode()
    else:
        main()