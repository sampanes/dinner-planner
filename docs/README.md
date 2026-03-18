# Dinner Planner Docs

This `/docs` folder is the working design set for the kitchen-first version of Dinner Planner.

The project direction is intentionally narrow:
- the goal is a calm, hands-free cooking experience
- Alexa/Echo Show is the primary kitchen interface
- recipe authoring stays local and Git-based
- normalization does most of the hard work up front
- no hidden phone puppet-master architecture
- stay inside free or near-free tooling for as long as possible

## Reading order

1. `00_Project_Direction.md` — what this project is and is not
2. `01_Kitchen_Product_Vision.md` — what the real-world experience should feel like
3. `02_System_Architecture.md` — major components and data flow
4. `03_Recipe_Runtime_Model.md` — the normalized recipe shape the system should run on
5. `04_Alexa_Interaction_Model.md` — invocation, intents, disambiguation, timers, and browse/search flows
6. `05_Implementation_Roadmap.md` — practical build order
7. `06_Debugging_and_Testing.md` — day-to-day development workflow in VS Code
8. `07_Cost_and_Account_Strategy.md` — how to keep this free or near-free
9. `08_Backlog_and_Open_Questions.md` — open issues and later ideas

## Design stance

This repo should optimize for these priorities:
1. reliability in the kitchen
2. natural voice flow
3. low recurring cost
4. easy household use
5. extensibility through stronger recipe normalization

## Non-goals for the current direction

These are deliberately out of scope for the current doc set:
- Android as the orchestration brain
- Firebase/FCM relay design
- Bluetooth audio ducking tricks
- LLM calls at runtime
- "smart" cloud automation that is harder to trust than a normalized recipe file
