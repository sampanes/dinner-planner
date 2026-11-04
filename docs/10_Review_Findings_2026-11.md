# 10 Review Findings (2026-11)

A review of the repo as it stood after the phase 0 commit, plus a check of what
changed on the Alexa platform since March 2026. Nothing in this pass changed code.

## Summary

- The static site works and the meal-plan page is the strongest part of the repo.
- The runtime recipe build is deterministic, but its step splitting is not good
  enough for voice yet. This is the main blocker for the Alexa direction.
- The Alexa client is still empty folders. The earlier hello-world attempt most
  likely failed because of an account / locale mismatch, not because of code.

## Web app

### What works well

- `groupings.html` / `app.js`: seeded shuffle (cyrb128 + mulberry32) makes every
  plan reproducible from its URL (`#/app?seed=...&meals=...&overlap=...&lock=...`).
  Plans can be shared and locked meals survive a reshuffle.
- The overlap slider picks meals that share ingredients, which keeps the grocery
  list short. This is a genuinely useful feature.
- `scripts/build_runtime_data.py` is idempotent: re-running it on the current
  source produces no diff.

### Problems

1. **localStorage shadows `recipes.json` on the main page.**
   `script.js` (DOMContentLoaded handler) loads from localStorage whenever a saved
   copy exists and never re-reads `data/source/recipes.json`. New recipes pushed to
   the repo do not appear for a returning visitor. The only refresh path is a hidden
   one: clicking the word "your" in the subtitle calls `loadRecipes()`, which also
   overwrites any local edits without warning.
2. **The two pages can disagree.** Recipes added or edited on `index.html` live only
   in that browser's localStorage. `groupings.html` fetches the JSON file directly,
   so it never sees those edits. The download button is the only bridge back to the
   source file.
3. **Step splitting is too coarse for voice.** `split_steps()` only recognizes
   `1. 2. 3.` style numbering. HelloFresh-style instructions (bare step numbers,
   section headings, bullet points) fall through.
   - "Pork Sausage Cavatappi Bolognese" becomes a single step of about 1,900 chars.
   - Roughly 15 other recipes have longest steps of 180 to 300 chars, which is too
     long for one spoken Alexa turn.
4. **Non-ASCII content.** At review time: 73 non-ASCII chars in `app.js`, 9 in
   `script.js`, 11 in `groupings.html`, 2 in `index.html`, 3 in
   `scripts/reformat_json.py`, and 141 in `data/source/recipes.json`
   (degree signs, curly quotes, bullets, fraction slashes, emoji in UI strings).
   These should be normalized to ASCII, both as house style and because they will
   cause problems in speech output and slot matching.
5. Minor: `index.html` uses the Tailwind Play CDN script, which is meant for
   development only. Fine for a personal site, but it is a runtime dependency on a
   third-party script. Recipe fields are rendered with `innerHTML`, which is
   acceptable only because all data is self-authored.

### Repo hygiene

- `.gitignore` now ignores `trash*` so local scratch files from the Alexa attempt
  (exported skill packages, console notes, request/response dumps) stay out of Git.
  Those files contain account-specific identifiers and should never be committed.
- The `Do not ignore:` block at the bottom of `.gitignore` is read by Git as
  patterns, not comments. It matches nothing today, so it is harmless, but it
  should become `#` comments to avoid confusion.

## Alexa: why the hello-world attempt failed

Observed during the earlier attempt:

- The developer console simulator answered every launch with
  "Sorry, <invocation name> is not supported on this device", across several
  invocation names.
- It only started responding after the developer account settings were changed.
- Even then, the LaunchRequest that got through carried `"locale": "en-IN"`.
- The skill was created from the stock hello-world template, which declares five
  English locales (en-US, en-CA, en-GB, en-IN, en-AU).

Most likely cause: an account / marketplace mismatch rather than code. A skill in
development is only enabled on devices registered to the same Amazon account that
owns the developer console login (or to beta testers invited to it), and the
account's marketplace needs to line up with the locale being tested. This is a
strong hypothesis, not a confirmed one; the attempt never reached a real-device test.

Recommended retry:

1. Sign in to the developer console with the Amazon account the Echo Show is
   registered to, or use the skill's beta test feature to invite that account.
2. Make the skill `en-US` only; delete the other four template locales.
3. Choose the final invocation name before building (see doc 09).
4. Test by voice on the actual Echo Show, not only in the simulator.

## Alexa platform changes since March 2026

- Custom skills still run on Echo devices, including Echo Show, per current Amazon
  developer docs. No official statement was found on how custom-skill invocation
  behaves now that Alexa+ is the default assistant; verify on device.
- 2026 deprecations (Routines Kit, skill quality coach / score, dialog evaluation
  tool, automotive skills, Amazon Pay in skills) do not affect this project.
- New Alexa+ developer previews include MCP (Model Context Protocol) support and a
  Smart Home AI toolkit. MCP could eventually let Alexa+ itself drive a recipe
  session against this repo's runtime data, with the LLM cost carried by Amazon
  rather than this project. It is preview-only; hobbyist access was not checked.

References:
- https://developer.amazon.com/en-US/docs/alexa/ask-overviews/deprecated-features.html
- https://developer.amazon.com/en-US/docs/alexa/build/build-your-skill-overview.html
- https://developer.amazon.com/docs/devconsole/alexa-simulator.html
- https://developer.amazon.com/docs/alexaplus/smarthome/whats-new

## Suggested next steps

1. Get the hello-world skill speaking on the real Echo Show using the retry steps
   above. This answers whether the platform path works at all.
2. Teach `split_steps()` the HelloFresh layout and add a max-length warning to the
   validation report.
3. Fix the localStorage shadowing on `index.html` (for example, compare against the
   fetched JSON or add a visible "reload from repo" button).
4. ASCII-normalize the source recipes and UI strings.
