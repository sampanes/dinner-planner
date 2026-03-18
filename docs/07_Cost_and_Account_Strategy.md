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
