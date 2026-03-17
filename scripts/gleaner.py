import json
import os
import re
import time
# Note: You will need to install your preferred LLM SDK (e.g., 'google-generativeai')
# import google.generativeai as genai 

"""
GLEANER.PY - The Automation Bridge
---------------------------------
Context: This script implements the "Gleaner" logic defined in:
- docs/00_Master_Blueprint.md (Section 3: Data Flow)
- docs/03_Infrastructure_&_Logic_Bridge.md (Section 2: The Python Tool)

Goal: Scans recipes.json, identifies new entries, and uses an LLM to generate 
voice-friendly "sidecar" JSON for the Android app and Alexa Skill.
"""

# File Paths (Relative to /scripts)
RECIPES_PATH = "../recipes.json"
VOICE_PATH = "../recipes_voice.json"

def load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, 'r') as f:
        return json.load(f)

def save_json(path, data):
    with open(path, 'w') as f:
        json.dump(data, f, indent=2)

def extract_timers(instruction_text):
    """
    Implements the Regex extraction logic described in 
    docs/03_Infrastructure_&_Logic_Bridge.md
    """
    # Look for patterns like "9-11 minutes" or "5 minutes"
    pattern = r'(\d+)(?:-(\d+))?\s*minutes'
    matches = re.findall(pattern, instruction_text)
    
    timers = []
    for match in matches:
        # Use the lower bound of a range for the initial timer logic
        minutes = int(match[0])
        timers.append({
            "type": "timer",
            "minutes": minutes,
            "text": f"It's been {minutes} minutes. Check on your progress."
        })
    return timers

def generate_voice_script(recipe):
    """
    Calls the LLM to 'chunk' instructions as required by:
    docs/01_Android_Architecture.md (Section 5: High-Fidelity Features)
    """
    recipe_name = recipe.get('name', 'Unknown Recipe')
    instructions = recipe.get('instructions', '')
    ingredients = recipe.get('ingredients', [])

    # Placeholder for LLM logic
    # In a real implementation, you would send 'instructions' to Gemini/Claude
    # with a prompt to "Break into 15-word chunks and identify prep steps."
    
    voice_blocks = []
    
    # 1. Start with Ingredient Check (Required by docs/01_Android_Architecture.md)
    ing_list = ", ".join([i['name'] for i in ingredients])
    voice_blocks.append({
        "type": "speech",
        "text": f"Let's make {recipe_name}. Gather your ingredients: {ing_list}. Tap when ready."
    })
    voice_blocks.append({"type": "wait_for_tap"})

    # 2. Process Instructions (Simplified logic for MVP)
    # The real 'Gleaner' uses LLM here to avoid the "drone" effect.
    steps = instructions.split('\n')
    for step in steps:
        if not step.strip(): continue
        
        voice_blocks.append({
            "type": "speech",
            "text": step.strip()
        })
        
        # Check for timers in this step
        step_timers = extract_timers(step)
        voice_blocks.extend(step_timers)
        
        # Every major step should likely wait for confirmation
        voice_blocks.append({"type": "wait_for_tap"})

    return voice_blocks

def main():
    print("--- Starting Dinner Planner Gleaner ---")
    
    recipes_data = load_json(RECIPES_PATH)
    voice_data = load_json(VOICE_PATH)

    # recipes.json is a list of objects per example_recipes.json
    new_count = 0
    for recipe in recipes_data:
        recipe_id = str(recipe.get('id'))
        
        # Only process if not already in the sidecar
        if recipe_id not in voice_data:
            print(f"Gleaning voice data for: {recipe.get('name')} (ID: {recipe_id})")
            
            # This implements the 'LLM Enrichment' from 03_Infrastructure_&_Logic_Bridge.md
            voice_script = generate_voice_script(recipe)
            voice_data[recipe_id] = voice_script
            new_count += 1

    if new_count > 0:
        save_json(VOICE_PATH, voice_data)
        print(f"Successfully added {new_count} new voice scripts to {VOICE_PATH}")
    else:
        print("No new recipes found. Everything is up to date.")

if __name__ == "__main__":
    main()