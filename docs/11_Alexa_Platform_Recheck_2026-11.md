# 11 Alexa Platform Recheck (2026-11-04)

A second look at the question doc 10 left open: has the Alexa side of this
project gotten easier since March 2026? Web research only; nothing in this pass
changed code. Evidence is dated and linked so it can be rechecked.

## Short answer

Yes, but not through the door docs 02 to 09 were built for. The custom-skill
path (ASK, interaction model, Lambda, APL) did not get easier and is now in
maintenance mode. What did change: Alexa+ shipped a native personal recipe
library with step-by-step cooking and named timers, which covers most of the v1
feature set in doc 00 with no skill, no code and no certification. The cost
condition is Prime (Alexa+ is free with Prime, $19.99/month without).

## 1. Alexa+ personal recipe library (the real change)

What Amazon says Alexa+ does today (US, general availability since
2026-02-04, free for Prime members):

- Add a recipe by sharing a link or a photo with Alexa+ in the Alexa app, by
  emailing it to alexa@alexa.com, or by dropping a link into Alexa.com. Alexa+
  extracts "the ingredient details, cooking steps, and notes scribbled in the
  margins" into a recipe card in a personal library.
- You can modify ingredients ("doubling the amount of chocolate chips") and ask
  Alexa to "walk you through the cooking steps".
- Timers are native and named: "set another timer for 25 minutes for the rice",
  "what timers are running", "how much time is left on the pasta timer".
- Echo Show displays the recipe and the current step.

Mapped against doc 00's "high-confidence v1 feature set":

| Doc 00 feature | Alexa+ native | Notes |
|---|---|---|
| launch naturally | yes | no invocation name at all |
| start by name or alias | likely | LLM matching, not a curated alias list |
| disambiguate similar names | likely | Alexa+ asks "which one"; behavior not controllable |
| next / repeat / back / resume | yes | "next step", "repeat that" confirmed in guides |
| ingredient amounts mid-recipe | likely | the card holds the ingredient list; unverified by voice |
| labeled overlapping timers | yes | confirmed |
| browse favorites / recent / categories | partial | library exists; no evidence of category browse |
| search by ingredients across MY library | unverified | plausible for an LLM over a library |
| readable current-step screen on Echo Show | yes | Amazon's own copy |

What it does NOT give: deterministic behavior, a testable session model, or
any of the explicit-state guarantees in doc 09. It trades all of that for zero
build effort and an LLM bill paid by Amazon.

## 2. Importing by link (built 2026-11-04)

Checked 2026-11-04 against the live Pages site before the change: the served
`index.html` contained no recipe text at all (recipes arrive by `fetch()` of
the JSON and then live in localStorage), so a link importer saw an empty
shell. The runtime JSON was public but not on a page.

Fixed the same day: `scripts/build_runtime_data.py` now generates one static
page per recipe under `recipes/` with schema.org Recipe JSON-LD (ingredients,
HowToSection/HowToStep instructions, image, notes), plus `recipes/index.html`.
The vault's "Page" link and the meal shuffler's "Full recipe page" button open
them. The probe, no email needed:

1. Confirm Prime and that the Echo Show is on Alexa+.
2. Open a recipe page (for example
   https://sampanes.github.io/dinner-planner/recipes/pork-sausage-cavatappi-bolognese.html)
   on the phone, share it to the Alexa app (or paste it into Alexa.com) and
   let Alexa+ add it to the library.
3. On the Echo Show: "Alexa, walk me through the cavatappi bolognese", then
   "next", "repeat that", "how much sour cream", "start a timer for the
   zucchini".

What to look at: whether the card keeps the image from the page, whether the
steps are the page's text or a rewrite, and whether the section names
("Roast Zucchini") survive. Those three answers decide how much of the page
content is under this repo's control versus Alexa+'s.

## 3. Custom skills on Alexa+: not easier, murkier

- Amazon's only statement is still the February 2025 "AI-native SDKs" post:
  existing skills "remain available to customers using the original Alexa
  experience"; a developer who wants an existing skill "considered for direct
  invocation on Alexa+" submits a form "for evaluation by our team"; "new
  developer tools will be focused on Alexa+". No 2026 update found.
- 2026 deprecations confirm maintenance mode: skill quality coach and score
  (2026-04-28), Routines Kit (2026-05-13), automotive skills (2026-08-07).
- Field evidence that a development-stage custom skill still launches by voice
  on an Alexa+ account: a Music Assistant skill issue (2026-10-21, es-MX): the
  account had Alexa+ for 6 to 7 months, "abre music assistant" reached the
  skill as a LaunchRequest, while typed routed commands did not and Alexa+
  answered that the provider "is not supported". A Home Assistant user
  (2025-12-13) reported Alexa+ Preview stopped opening a custom skill on an
  Echo Show 8 until it was named exactly; Alexa+ could not list skills.
- Implication for doc 10's hello-world post-mortem: "<invocation name> is not
  supported on this device" is also what an Alexa+ account produces when it
  declines to route to an unevaluated skill. Doc 10's marketplace / en-IN
  hypothesis still stands (the account change made it respond). Both are
  checked on the device: ask "Alexa, which account is this?" and note whether
  the voice is the Alexa+ one.
- Alexa-hosted skills: no change to the free hosting found.

## 4. MCP: confirmed closed to hobbyists

- 2026-07-23, "Alexa+ for Builders": MCP Toolkit, Category SDK and Smart Home
  AI Toolkit, all "currently available in Preview", and the portal says
  "currently available to select partners working directly with our team".
- Oct 2026 hackathon entrants confirmed it in practice: the add-ons console and
  web simulator show "Coming Soon" on a new developer account, `@alexa-ai/cli`
  is not on the public npm registry, and organizers said participants would
  not get access.
- Requirements once it opens: an MCP server over Streamable HTTP, OAuth with
  401 on unauthenticated requests, under 500 ms round trip. That is a hosted
  server with a bill, which doc 07 forbids.
- A community bridge (`KayLerch/alexa-skill-mcp-bridge`) emulates the Alexa+
  MCP client with a custom skill plus Bedrock Nova 2 Lite on AgentCore: about
  $0.0013 per turn, cents per month idle. Near-free, but it is a hackathon
  development bridge and puts an LLM at runtime, which doc 00 rules out.

## 5. Cost check

| Path | Recurring cost | Condition |
|---|---|---|
| Alexa+ recipe library | $0 | household already has Prime; else $19.99/month |
| Custom skill, Alexa-hosted | $0 | unchanged; Alexa+ routing is the risk |
| MCP add-on | n/a | partner-only |
| Community MCP bridge | cents/month | AWS account, Bedrock, LLM at runtime |

The free non-Prime Alexa+ tier is text chat on Alexa.com and in the app, not
voice on an Echo, so it does not help the kitchen case.

## Recommended order

1. Probe the recipe library with one shared page link (section 2). Ten
   minutes, no code. Note what "next", "repeat", an ingredient question and
   a timer actually do.
2. If it covers the kitchen loop: shelve `clients/alexa/` and the handler work
   in docs 04, 06 and 09; keep docs 00, 01 and 03 as the product and data
   contract; import all 33 pages (the pages and the step splitting landed
   2026-11-04).
3. If it does not (no Prime, or Alexa+ mangles the steps): run doc 10's retry
   (en-US only, same account, real device) with the extra Alexa+ routing check
   from section 3 before blaming code.

## References

- https://www.aboutamazon.com/news/devices/new-alexa-plus-amazon-devices
- https://www.aboutamazon.com/news/devices/alexa-plus-web-ai-assistant
- https://www.aboutamazon.com/news/devices/alexa-plus-available-free-prime-members-us
- https://aiworldhq.com/article/use-alexa-to-guide-you-through-cooking-recipes-and-manage-multiple-kit
- https://developer.amazon.com/en-US/blogs/alexa/alexa-skills-kit/2025/02/new-alexa-announce-blog
- https://developer.amazon.com/en-US/docs/alexa/ask-overviews/deprecated-features.html
- https://developer.amazon.com/alexaplus/blogs/2026/07/alexa-plus-new-ways-to-build-experiences
- https://developer.amazon.com/alexaplus
- https://developer.amazon.com/docs/alexaplus/add-ons/choose-the-proper-alexaplus-integration-approach.html
- https://github.com/alams154/music-assistant-alexa-skill-prototype/issues/94
- https://community.home-assistant.io/t/open-a-dashboard-on-amazon-alexa-echo-show/709520?page=5
- https://github.com/devcaos/duly/pull/15
- https://github.com/KayLerch/alexa-skill-mcp-bridge
