# 07 Cost and Account Strategy

## Goal

Keep the project free or near-free for a household-scale use case.

## Cheap-by-design choices

### 1. Local normalization
Do heavy recipe processing locally instead of through paid APIs.

### 2. Alexa-hosted skill first
Use an Alexa-hosted custom skill for the initial build.

### 3. Static repo-managed recipe data
Store authoring data in the repo and commit generated runtime files.

### 4. No custom backend unless proven necessary
Avoid adding extra cloud services until the hosted-skill path is clearly insufficient.

## What should stay free or near-free in the intended use case

For a personal or household skill, these choices are intended to keep costs low:
- Amazon developer account
- Alexa-hosted skill at small scale
- GitHub repo and static data hosting
- local Python build scripts
- VS Code development workflow

## What tends to create cost

Avoid these early unless they are truly justified:
- paid NLP or LLM API calls at runtime
- custom always-on backend services
- complex multi-device sync infrastructure
- unnecessary external search or data APIs

## Account linking stance

Do **not** use account linking in v1 unless there is a clear need for per-user private data.

Reasons to defer it:
- adds setup friction
- requires more infrastructure and OAuth thinking
- reduces household simplicity

When account linking becomes worth it:
- different favorites per user
- saved history per user
- personalized household profiles that truly matter

## Household mode recommendation

The v1 product should act like a shared household cooking helper.
That means:
- one shared skill experience
- no required login
- recipe library available by voice to either person
- simple favorites and browse experiences

## Data ownership recommendation

Commit both source and generated runtime data to the repo.
That gives you:
- reproducible builds
- easy debugging
- easier rollbacks
- simpler hosted-skill packaging

## Cost guardrails

Before adding any new service, ask:
1. can this be done in the local build pipeline instead?
2. does this improve runtime kitchen behavior in a meaningful way?
3. does this add a recurring bill or operational dependency?
4. does this make the system harder for a household to keep using?

If the answer is mostly "yes, more cost and complexity," do not add it yet.

## Recommended infrastructure boundary for v1

The cleanest low-cost boundary is:
- Git repo holds source docs and source recipes
- local scripts generate runtime data
- generated runtime data is packaged with the skill
- Alexa-hosted logic serves voice and APL responses
- persistent state is limited to lightweight household/session data

That boundary avoids paying for a separate app backend just to read recipe JSON and track step numbers.

## What should not trigger infrastructure expansion yet

These are tempting, but should not automatically justify a backend:
- wanting richer search before trying better local indexes
- wanting more natural aliases before improving normalization
- wanting resume before using hosted persistence correctly
- wanting prettier visuals before state/rendering is clean

## When a custom backend would finally be justified

A real backend becomes easier to justify only when one or more of these become central requirements:
- user-generated or remote recipe syncing across many homes
- account-linked private household data that exceeds hosted convenience
- analytics or reporting you truly need to operate the product
- nontrivial integrations that cannot be packaged safely with the skill
- scale or operational constraints that materially exceed the hosted path

Even then, add the thinnest backend possible.

## Cost stance on timers, lists, and platform features

Prefer built-in Alexa platform features over external substitutes when they directly support the cooking experience.
But also avoid building around platform branches that are outside the core product loop.

### Good use of platform features
- APL for glanceable Echo Show screens
- hosted persistence for simple resume/history
- Alexa timer APIs for recipe-driven timers

### Low-priority or easy-to-overinvest areas
- account linking before shared-household value exists
- external list/task systems before the cooking loop is solid
- analytics stacks before there is a real product question they answer

## Operational simplicity as a cost category

Money is not the only cost.
For this project, the following also count as real cost:
- more credentials to rotate
- more services to debug
- more deployment surfaces
- more ways for the skill to fail during dinner

A free architecture that is fragile is still expensive in practice.

## Practical recommendation

Treat every new dependency as guilty until proven helpful.
The default answer for v1 should be:
- keep it local if possible
- keep it hosted if sufficient
- keep it explicit if ambiguous
- keep it small if uncertain
