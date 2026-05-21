---
description: Coached conversation that populates the project-level declaration.md (what / why / for whom / out of scope).
---

Read the current declaration.md before starting.

Phase 1 — coached conversation:
Ask about:
- **What** — what this project is, in one or two sentences with no implementation detail.
- **Why** — the problem it solves or the need it serves.
- **For whom** — who uses it and what they need from it.
- **Out of scope** — what this project explicitly does not do.
- **Shape** — once the above is settled, ask the user to name 3–7 components or seams the app will eventually have. One line each, no diagrams, no contracts, no data models. This is not architecture — it's a map of the parts that exist, so the first feature has something to slice against. Explicitly tell the user this is revisable as the project learns; the goal is to make implicit decomposition explicit, not to commit to a system design.
- **Roadmap** — after the Shape, ask the user to name the next 3–7 features they anticipate building, in rough order. One line each. Tag each with the Shape seams it touches. This is **not a commitment** — it is memory. The thinking the user does during project setup about "what comes next" otherwise evaporates and has to be reconstructed when feature 2 starts. Explicitly tell the user the Roadmap is revisable as reality diverges; anything beyond the 3–7 horizon is fiction. Do not solicit acceptance criteria, effort estimates, or specs — those belong in the per-feature declaration when the feature is actually about to be built.

If declaration.md is already populated (beyond template placeholders), ask whether the user wants to refine specific sections or rewrite from scratch.

Hold the conversation at the level of intent, not implementation. If the user starts describing how it works rather than what it is, redirect — that content belongs in constitution.md or feature artifacts. The Shape and Roadmap sections are the exception: Shape names components but does not describe their internals; Roadmap names anticipated features but does not specify them.

Continue until the declaration is clearly formed. Do not proceed to Phase 2 until the user confirms.

Phase 2 — structured output:
Write declaration.md (at the repo root) with sections labeled `## What`, `## Why`, `## For whom`, `## Out of scope`, `## Shape (revisable)`, and `## Roadmap (revisable)`. The Shape section is a bulleted list, one line per component/seam. The Roadmap section is a numbered list, one line per anticipated feature, each tagged with the Shape seams it touches (e.g., `1. Auth — adds login/logout. Touches: API gateway, user store.`).

Present the written declaration back to the user for review. Revise until it says what they meant.

Commit the completed declaration.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: declaration.md is populated with all six sections (What / Why / For whom / Out of scope / Shape / Roadmap), the user has confirmed it captures their intent, and it is committed.
