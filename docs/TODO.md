add this to webhooks

#!/bin/bash
# Check if recipes are out of sync
python scripts/gleaner.py

if [ -f "PROMPT_STAGING.md" ]; then
  echo "--------------------------------------------------------"
  echo "STOP! Your recipes and voice sidecar are out of sync."
  echo "PROMPT_STAGING.md has been generated. Process it first."
  echo "--------------------------------------------------------"
  # Optional: Opens the file in VS Code automatically
  # code PROMPT_STAGING.md 
  exit 1
fi