---
description: Generates features/[feature-name]-[number]/dag.md (dependency graph of build tasks organized into parallel waves) and initializes state.md.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, features/[feature-name]-[number]/design.md, and features/[feature-name]-[number]/adversarial-review.md.

Verify the inputs are ready before generating:
- requirements.md and design.md should both report stable (the requirements ↔ architecture loop has converged). If either is unstable, stop and tell the user to complete the loop first.
- adversarial-review.md must have no `open` HIGH-severity findings. MEDIUM findings must be marked `acknowledged` or `deferred`. If anything is blocking, stop and tell the user which findings remain.

Generate a dependency graph of all build tasks. For each task:
- **ID** — stable identifier (T-001, T-002, …).
- **Description** — what the task accomplishes.
- **Inputs** — files, components, or prior tasks it depends on.
- **Outputs** — files or behaviors it produces.
- **Dependencies** — IDs of tasks that must complete first.
- **Wave** — the parallel-execution wave (1, 2, 3, …). Tasks in the same wave can run in parallel; later waves wait for earlier ones.
- **Acceptance condition** — what makes this task done. Must be objectively checkable.

Each task must be atomic and completable in a single session with margin. If a task aggregates multiple distinct concerns (e.g., "rendering + CSRF token store + allowlist + accessibility markup"), split it into atomic sub-tasks with explicit wave ordering. Atomicity beats apparent cohesion — a task that bundles five concerns is five chances to partially complete and leave the DAG in a confusing state. When in doubt, split.

**One-DAG-per-session sizing check.** A T3 feature is designed to run end-to-end in one Sonnet conversation: `/t3-build` drives the whole DAG without crossing a session boundary. The state.md / `/t3-next-step` machinery exists as resilience for sandbox failures, not as a design license for multi-session features. This means the *whole DAG must fit one orchestrator session's working window*, including pre-build artifacts in context plus the code each task produces plus test output between waves.

Before committing dag.md, sanity-check the DAG against the orchestrator-session budget:
- **Too small** — 1–2 tasks total. The feature was almost certainly T2-sized; surface this and recommend re-doing as T2 rather than committing the DAG.
- **Fits on one screen** — the right shape. The user should be able to see all tasks without scrolling. If they can't, the orchestrator's accumulated state is likely to outgrow the working window.
- **Too large signals:**
  - DAG doesn't fit on one screen.
  - More than ~3–4 waves (any one wave is fine; it's the *accumulated* state across waves that pressures the window).
  - Any single task reads a large amount of new context (a big external schema, a large existing module being modified).
  - The feature introduces a new test framework, new dependency, or new deploy path — these load reference material into the orchestrator that wasn't budgeted for.

If any of the "too large" signals fire, surface this to the user before committing and recommend splitting the feature into two feature folders. The right response is to split, not to plan on resuming across sessions.

Walking-skeleton features get explicit accommodation: breadth across seams is expected because that's the point. But each task should still be shallow, and if the skeleton's surface is too wide to fit one session, the right move is to make the *first* skeleton thinner — touch a subset of seams in feature 1, extend the skeleton in feature 2. The Shape lets you make this trade explicitly.

Write features/[feature-name]-[number]/dag.md with all tasks, grouped by wave.

Initialize features/[feature-name]-[number]/state.md following the format in constitution.md's `## Artifact formats / State file` section, with every task in `pending` status.

Present the DAG and the initial state to the user for review. Revise until the dependency structure and wave grouping are sound.

Commit the completed dag.md and state.md to the current branch (the sandbox provisions this; do not create a new one).

After committing, recommend the user run `/t3-test-coach` next to generate the test suite before invoking `/t3-build`.

Exit condition: features/[feature-name]-[number]/dag.md exists with all tasks organized into waves, features/[feature-name]-[number]/state.md exists with every task in `pending` status, the user has confirmed the DAG, and both files are committed.
