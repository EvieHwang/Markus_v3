---
description: Produces features/[feature-name]-[number]/design.md. Re-run as part of the requirements ↔ architecture loop until convergence.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, and features/[feature-name]-[number]/requirements.md. If features/[feature-name]-[number]/design.md exists, read it too. If features/[feature-name]-[number]/adversarial-review.md exists, read it too — open findings whose recommended action is t3-architecture must be addressed in this pass.

**Ground-truth check before drafting.** Identify the sections of CLAUDE.md you intend to lean on for this design — precedent repos, deployment shape, gateway/proxy/auth patterns, the User globals block. List them back to the user and ask whether each is current. If CLAUDE.md names a precedent repo (see its `## Precedent repos to consult before building` section, if present), attempt to read it; if access is out of scope, ask the user to confirm the precedent before assuming it. A wasted architecture pass built on a stale section costs more than one short exchange up front.

Produce the architecture given the current requirements:
- Components, contracts, and hard technical constraints.
- How components relate and where the seams are.
- What the build agent must know before touching code.

**Pattern reuse.** If a component or attack surface reuses a pattern already documented in constitution.md's pattern registry (e.g., "OAuth via the existing auth module", "deploy via the existing Eviebot launchd template", "same DB access layer as feature X"), mark it explicitly in design.md as `Reuses pattern: [name from constitution]`. The adversarial skill uses these markers to scope its review — unmarked surfaces get full scrutiny, marked surfaces get HIGH-severity-only review on the assumption that the constitution-registered pattern is already vetted. Only mark surfaces where the reuse is genuine and complete; partial reuse is not reuse.

Then list any requirements that the architecture implies should change. Do not silently reshape requirements — surface them explicitly.

If the surfaced list is non-empty, the user should run t3-requirements next to incorporate the changes, then re-invoke this skill. The loop continues until neither side flags new changes.

If the surfaced list is empty, this side of the loop is stable. State that explicitly at the end of design.md ("Architecture stable — no requirements changes flagged"). If t3-requirements also reports stable on its next run, the loop has converged.

If the architecture surfaces tension with the project or feature declaration (not just requirements), stop and surface that separately. Declaration tension is more serious than requirements tension — it usually means the feature is mis-scoped.

If adversarial-review.md exists, address every `open` finding the recommended action attributes to t3-architecture (typically design, security, and standards-compliance findings). In design.md, note which findings were addressed, e.g., `*Addresses adversarial F-002, F-005.*`. Set the status of each addressed finding to `addressed` in adversarial-review.md (the next adversarial run will verify and promote to `resolved`). Findings already marked `acknowledged` or `deferred` do not require action.

Write features/[feature-name]-[number]/design.md.

Present the written design to the user for review. Revise until it is sound.

Commit the completed design.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: features/[feature-name]-[number]/design.md exists, the user has confirmed it, any requirement-change flags are explicit, and the file is committed.
