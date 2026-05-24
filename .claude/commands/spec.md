---
description: Orchestrates the full pre-build pipeline — requirements → architecture (loop until stable) → adversarial (loop to address findings) → DAG → tests → PM summary → PR. Runs autonomously after feature declaration is confirmed, stopping only for decisions that require product judgment. Individual steps can still be run manually at any time for refinement or closer involvement.
---

Read features/[feature-name]-[number]/declaration.md before anything else. If it does not exist or contains only template placeholders, stop immediately — run `/feature` first and confirm the feature declaration before invoking this skill.

Read constitution.md and declaration.md.

## State detection

Check which artifacts exist in features/[feature-name]-[number]/ and resume from the appropriate point. Pipeline stages in order:

1. requirements.md
2. design.md (requirements ↔ architecture loop)
3. adversarial-review.md
4. verify.md + tests/
5. dag.md + state.md
6. spec-summary.md
7. push + PR — terminal step

If a PR for this branch already exists and spec-summary.md is populated, report that the pipeline is complete and exit.

## Sub-agent context convention

Every Stage 1–5 sub-agent reads, before its task:
- `constitution.md`
- `declaration.md`
- every file already present in `features/[feature-name]-[number]/` (declaration, requirements, design, adversarial-review, dag, state, verify, tests/ — whichever exist)

Per-stage prompts below only name *additional* inputs or special instructions. Do not restate the standard reading list in each prompt.

## Orchestration rules

**Proceed autonomously:**
- Writing or rewriting requirements.md and design.md to incorporate architectural feedback or adversarial findings
- Marking adversarial findings `addressed` in adversarial-review.md after the relevant sub-agent addresses them
- Moving to the next stage when the conditions below are met
- After each stage's commit lands, push the branch to origin (`git push -u origin <current-branch>`). This keeps the stop-hook quiet between stages and gives crash-recovery. Sub-agents commit but do not push; the orchestrator pushes.

**Stop and ask the user** — do not proceed autonomously when:
- Adversarial review surfaces a scope drift finding (lens: "Scope drift") that conflicts with the feature declaration
- Architecture or requirements surfaces tension with the project or feature *declaration* (not just with each other)
- A HIGH adversarial finding cannot be resolved by req/arch changes alone and requires an `acknowledged` or `deferred` decision that only the user can make
- The req↔arch loop has not converged after 3 cycles (see Iteration tracking) — surface the specific point of tension
- Adversarial findings have bounced back to Stage 1 three times without converging — surface the unresolved findings

When stopping, present exactly the product or scope question that requires judgment. Do not list technical options. After the user answers, resume from the point where the pipeline stopped.

**Async sub-agent launches.** If the Agent tool returns "Async agent launched" (harness behavior on long-running agents), wait for the completion notification before launching the next stage. Do not poll or fire additional tool calls in the meantime.

## Iteration tracking

Two independent counters, both capped at 3:

- **req↔arch cycles** — one cycle = one Stage 1 → Stage 2 round-trip. Adversarial findings bouncing back to Stage 1 do not increment this counter.
- **adversarial revision rounds** — one round = one Stage 3 → Stage 1 → Stage 2 → Stage 3 loop triggered by open HIGH/MEDIUM findings.

If either counter reaches 3 without convergence, stop and surface the specific conflict.

## Stage execution

Each stage runs as a focused sub-agent spawned via the Agent tool. The sub-agent does its work and commits its output. The orchestrator does not carry the sub-agent's reasoning — after each sub-agent exits, it reads the committed artifact from disk to determine the next routing decision, then pushes.

---

### Stage 1 — Requirements

Spawn a sub-agent with this task:

> Additional inputs: if features/[feature-name]-[number]/adversarial-review.md exists, address every open finding whose recommended action is requirements — note each addressed finding inline in requirements.md (e.g., *Addresses adversarial F-003.*) and mark it `addressed` in adversarial-review.md.
>
> Produce behavioral requirements in testable terms: user stories with acceptance criteria, edge cases and failure modes, and out-of-scope statements. If this is a revision, note what changed from the prior version and why. At the bottom, state either "Requirements stable — no architectural feedback to incorporate" or list what still needs architectural resolution and why.
>
> Write features/[feature-name]-[number]/requirements.md and commit it. Do not push.

After the sub-agent exits, read requirements.md. Extract: does the stability marker appear at the bottom? Push the branch.

---

### Stage 2 — Architecture

Spawn a sub-agent with this task:

> Additional inputs: if features/[feature-name]-[number]/adversarial-review.md exists, address every open finding whose recommended action is architecture — note each addressed finding inline in design.md (e.g., *Addresses adversarial F-002, F-005.*) and mark it `addressed` in adversarial-review.md.
>
> Produce the architecture: components, contracts, behavioral constraints, seam relationships. Every constraint must be behavioral — it states a property the user or system cares about (e.g., "requests must time out within 5 s"), not a call signature, attribute name, specific function, or code shape. If a draft constraint names a library API detail or internal implementation shape, restate it as the behavioral property it protects. The single exception: when the call shape itself is the contract (a public interface this project exposes to callers), name it explicitly and say why. For any component or attack surface that genuinely reuses a pattern from constitution.md's pattern registry, mark it explicitly as `Reuses pattern: [name]`. List any requirements that the architecture implies should change. At the bottom, state either "Architecture stable — no requirements changes flagged" or list what should change and why.
>
> **Upstream marker maintenance.** If the requirements.md stability marker is stale only because this architecture pass resolved a question that requirements had deferred to architecture (the requirement *text* does not need to change, only the deferred-question note), flip the requirements.md marker to "stable" yourself and add a one-line note in design.md explaining which question was resolved (e.g., "Resolves the BR-6 deferred question; flipping requirements.md marker to stable."). Only do this for marker-only updates — any change to requirement text still routes through Stage 1.
>
> Write features/[feature-name]-[number]/design.md and commit it (and requirements.md if you flipped its marker). Do not push.

After the sub-agent exits, read design.md and requirements.md. Extract: are both stability markers present? Does design flag requirements changes? Push the branch.

**Loop routing:** If either stability marker is absent (and the gap is not marker-only — design didn't flip it because text actually needs changing), increment the req↔arch counter and return to Stage 1. If both are present, proceed to Stage 3.

---

### Stage 3 — Adversarial review

Choose one of two modes based on the change since the last adversarial-review.md:

- **Fresh review** — no prior adversarial-review.md, or the requirements/design diff since the last review is substantial (multiple sections, new components, new requirements).
- **Verification pass** — prior adversarial-review.md exists and the diff is targeted: addressing specific findings from the prior review, surgical edits (one or two clauses, one bootstrap arg, etc.). The pass verifies the fixes hold and does not re-derive findings against unchanged content.

State which mode you're using when spawning the sub-agent.

Spawn a sub-agent with this task:

> Additional instructions: you are running in **[fresh review | verification pass]** mode. In verification mode, do not re-run the full lens sweep — scope to (a) verifying that each `addressed` finding is genuinely fixed in the latest requirements.md/design.md, and (b) attacking the fix itself with the original lens to check it didn't introduce an adjacent gap. Do not surface new findings against unchanged content.
>
> You are a reviewer judging whether requirements and design are ready to build. Zero findings is a valid outcome when the spec is sound. Only surface a finding if you can name a concrete failure mode it would cause — generic concerns are not findings.
>
> If adversarial-review.md already exists, run `git log -1 --format=%H -- features/[feature-name]-[number]/requirements.md features/[feature-name]-[number]/design.md` and compare against the SHA recorded in the existing review's header. If neither file has changed since the last review, report "No changes since last adversarial review at [SHA]" and exit without modifying the file.
>
> Review through lenses — apply **scope check first**: for each candidate finding, trace its subject to a specific sentence in the declarations or requirements.md. If the finding concerns *how* the design implements something (a specific call signature, an internal attribute name, a library API shape, a constructor argument) rather than *what* the feature requires, do not file it as a finding — record it in a `## Prescription feedback` section of adversarial-review.md with the note "implementation prescription, not behavioral constraint" and the specific design section. Only findings whose subjects trace to declared behavior proceed to the remaining lenses: integrity, coverage, security (located findings only — name the specific component and spec section; pre-implementation findings that cannot name a file:line must name the spec section precisely), standards compliance per constitution.md, failure modes, scope drift. Apply pattern-reuse scoping: if design.md marks a surface `Reuses pattern: X`, scope security and failure-modes lenses for that surface to HIGH severity only.
>
> For each open finding: ID (F-001…, never reuse), severity (HIGH / MEDIUM / LOW), lens, finding, recommended action (architecture or requirements), status (open). LOW findings without a named location are dropped. Verified addressed findings move to resolved. Acknowledged findings get appended to constitution.md's Acknowledged risks table.
>
> Write features/[feature-name]-[number]/adversarial-review.md with a one-line header recording the current commit SHAs of requirements.md and design.md, plus which mode this pass used. Commit it. Do not push.

After the sub-agent exits, read adversarial-review.md, then push the branch. Classify each open finding:

- **Prescription feedback** (`## Prescription feedback` section in adversarial-review.md is non-empty) → return to Stage 2 without incrementing the adversarial counter. The architecture sub-agent will read the feedback and restate prescriptions as behavioral constraints. Do not also return to Stage 1 unless requirements changes are independently needed.
- **Scope-level** (lens is "Scope drift", or finding surfaces declaration tension) → stop and ask the user
- **Technical, HIGH or MEDIUM** → increment the adversarial-revision counter and return to Stage 1; the req/arch sub-agents will read adversarial-review.md and address the relevant findings
- **Technical, LOW** → non-blocking; proceed to Stage 4
- **No open findings and no prescription feedback** → proceed to Stage 4

---

### Stage 4 — Test generation

Spawn a sub-agent with this task:

> Check constitution.md's Testing section. If it names a framework, use it. If empty, choose the framework that best fits the project's stack and any existing tests — write the choice and run command into constitution.md's Testing section before generating tests.
>
> Generate two categories of tests: behavioral (from requirements, verifying what was specified) and integration tests from design seams (from design: do the seams hold? Test that timeouts fire at the right boundaries, errors map to the right taxonomy, and interfaces between components behave as designed. Do not test private attributes, specific call signatures, or constructor arguments — test observable seam behavior). Do not tag tests with DAG task IDs — the DAG does not exist yet; task ID labels are applied in the next stage.
>
> If a requirement cannot be tested as written, surface the specific untestable requirement and exit without writing any test files — a weak test is worse than no test.
>
> Write features/[feature-name]-[number]/verify.md (human-readable coverage summary mapping each requirement and design seam to the tests that verify it; the task → test mapping will be added in the next stage) and features/[feature-name]-[number]/tests/ (executable test files). Commit all files, including constitution.md if the Testing section was updated. Do not push.

After the sub-agent exits, push the branch. Check whether the sub-agent surfaced any untestable requirements. If so, stop and present the gap to the user — the resolution is to update requirements.md (re-entering the loop from Stage 1) before proceeding to Stage 5.

---

### Stage 5 — DAG generation

Spawn a sub-agent with this task:

> Verify prerequisites: requirements.md and design.md both carry their stability markers; adversarial-review.md has no open HIGH findings and no open MEDIUM findings; verify.md and tests/ exist. If any condition is unmet, report which one and exit without writing.
>
> Generate a dependency graph of all build tasks. For each task: ID (T-001…), description, inputs, outputs, dependencies, wave, acceptance condition (objectively checkable). Group into parallel waves. Each task must be atomic and completable in a single session with margin — if a task aggregates multiple distinct concerns, split it.
>
> Size check before committing: 1–2 tasks total likely means this feature is too small for a full DAG (surface this). DAG that does not fit one screen, more than ~3–4 waves, or that introduces a new framework, dependency, or deploy path is too large (surface this and recommend splitting the feature). Walking-skeleton features get accommodation on breadth but not on depth.
>
> Write features/[feature-name]-[number]/dag.md. Initialize features/[feature-name]-[number]/state.md with every task in pending status.
>
> Apply task ID labels to the existing tests: read verify.md and the test files in tests/, map each test to the task IDs whose acceptance conditions it verifies, and add the authoritative task → test mapping to verify.md. Every task must have at least one test; if any task has no matching test, surface it and exit without committing — the resolution is to add coverage via /tests before continuing. Do not modify the test files themselves; verify.md is the authoritative mapping.
>
> Commit dag.md, state.md, and the updated verify.md. Do not push.

After the sub-agent exits, read dag.md and verify.md and push the branch. If the sub-agent surfaced a sizing problem, a too-large warning, or a task with no test coverage, stop and present this to the user before proceeding to Stage 6.

---

### Stage 6 — PM summary

Write features/[feature-name]-[number]/spec-summary.md directly. By this point the orchestrator has read all the relevant committed artifacts and does not need a sub-agent.

**Feature** — What it is and why it exists now. One paragraph from the feature declaration, written for a reader who hasn't seen the spec.

**What it does** — Plain-language description of the core behaviors delivered. Derived from requirements but written for a product manager: no implementation detail, no technical jargon. Describes what a user or operator will experience.

**Risks carried** — Any adversarial findings marked `acknowledged` or `deferred`, stated in product terms: what could go wrong and what decision was made about it. If none, state "No risks acknowledged."

**Out of scope** — What this feature explicitly does not address, drawn from the feature declaration and requirements.

**Build preview** — Number of waves, number of tasks, and the DAG's session-budget assessment. One sentence on whether the DAG fits comfortably in one build session or whether anything about it warrants attention.

**Next step** — "Start a new session and run `/build feature-name: [name]`."

Commit spec-summary.md and push the branch.

---

### Stage 7 — Push and open PR

The cloud sandbox is ephemeral — the spec is only handed off to the next session via a PR.

Push the branch one final time to ensure all commits are upstream. Open a pull request against `main` using the GitHub MCP server (`mcp__github__create_pull_request`):

- Title: `spec: [feature-name]`
- Body: include spec-summary.md content plus a one-line note that the PR is the handoff to the next session for `/build`.
- Ready for review (not draft).
- Assigned to the repo owner per CLAUDE.md.

Present the PR URL to the user. The pre-build pipeline is complete.
