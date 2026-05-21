---
description: Produces features/[feature-name]-[number]/requirements.md in testable terms. Re-run as part of the requirements ↔ architecture loop until convergence.
---

Read constitution.md, declaration.md, and features/[feature-name]-[number]/declaration.md. If features/[feature-name]-[number]/design.md exists, read it too — incorporate the architectural constraints it surfaces. If features/[feature-name]-[number]/adversarial-review.md exists, read it too — every finding marked `open` whose recommended action is t3-requirements must be addressed in this pass.

Produce behavioral requirements in testable terms:
- **User stories with acceptance criteria** — each story names a user, a need, and the criteria that confirm it works.
- **Edge cases and failure modes** — what happens at the boundaries and when things go wrong.
- **Out of scope** — what this feature explicitly does not address.

If design.md exists and surfaces architectural constraints, revise requirements to reflect them. Do not silently absorb the constraints — note in the document what changed and why.

If design.md exists and you find no requirements changes are needed, state that explicitly at the end of requirements.md ("Requirements stable — no architectural feedback to incorporate"). If t3-architecture also reports stable on its next run, the loop has converged.

If you surface something that needs more debate than a revision can capture, stop and surface it; don't paper over it.

**Standards-creep check.** For each acceptance criterion: is it serving the feature's stated intent (from the feature declaration), or is it surfaced by a constitution-level standard (accessibility, security, API contracts)? Standards apply by default, but when a thin feature would absorb a heavy set of cross-cutting criteria (e.g., full WCAG sign-off for a one-page admin tool), surface the tension rather than silently absorbing the cost. The user decides whether to absorb, scope-down, or defer — the skill does not silently pad the feature.

If adversarial-review.md exists, address every `open` finding the recommended action attributes to t3-requirements (typically coverage and scope findings). In requirements.md, note which findings were addressed, e.g., `*Addresses adversarial F-003.*`. Set the status of each addressed finding to `addressed` in adversarial-review.md (the next adversarial run will verify and promote to `resolved`). Findings already marked `acknowledged` or `deferred` do not require action.

Write features/[feature-name]-[number]/requirements.md.

Present the written requirements to the user for review. Revise until they are sound.

Commit the completed requirements.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: features/[feature-name]-[number]/requirements.md exists, the user has confirmed it, requirements are testable, any changes from the prior version are noted, and the file is committed.
