---
description: Coached conversation that produces features/[feature-name]-[number]/intent.md
---

Read constitution.md and declaration.md before starting.

Phase 1 — coached conversation:
Ask questions to understand:
- What is being built and why
- Who needs it and what they are trying to accomplish
- What success looks like from the user's perspective
- What is explicitly out of scope

Continue until intent is clearly formed. Do not proceed to Phase 2 until the user confirms.

Phase 2 — structured output:
Write features/[feature-name]-[number]/intent.md with:
- **Purpose** — what this feature is and why it exists.
- **User stories** — as a [user] I need [X] so that [Y]. Each story names a user, the need, and the success criterion.
- **Out of scope** — what this feature does not address.

Present the written document back to the user for review. Revise until it says what they meant.

Commit the completed intent.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: features/[feature-name]-[number]/intent.md exists, the user has confirmed it captures their intent, and it is committed.
