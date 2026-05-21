---
description: Derives features/[feature-name]-[number]/plan.md from the existing intent and architectural constraints.
---

Read constitution.md, declaration.md, and features/[feature-name]-[number]/intent.md before starting.

Phase 1 — architectural considerations:
Identify what the intent implies architecturally:
- What components are affected or created.
- What constraints apply given the existing architecture.
- What technical decisions must be made before implementation begins.

If any consideration surfaces something that reshapes the intent — a constraint that makes a requirement impossible or expensive, or a requirement that was missing — stop. Surface this to the user and update intent.md before proceeding. This feedback loop is the most important quality lever in T2.

Phase 2 — implementation approach:
Derive the approach from those constraints:
- How it gets built.
- What the build agent needs to know before touching code.
- What the build agent must not do.

Write features/[feature-name]-[number]/plan.md with two sections labeled `## Architectural considerations` and `## Implementation approach`. Do not restate intent. Plan informs implementation; intent describes purpose.

Present the written plan to the user for review. Revise until it is sound.

Commit the completed plan.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: features/[feature-name]-[number]/plan.md exists, intent.md has been updated if architectural review surfaced changes, the user has confirmed the plan, and it is committed.
