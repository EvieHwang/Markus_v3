# User Guide

A build framework for Claude Code, distributed as a template repository. Choose your approach based on scope: `/patch` for bounded changes that fit a single session, the feature build pipeline for deliberate feature work that warrants a written spec. The framework provides skill commands (in `.claude/commands/`) that produce specification artifacts in `features/[name]-[number]/` and then build against them. The artifacts are the contract between what you wanted and what got built.

---

## Choosing your approach

**Quick change — use `/patch`.** Bug fixes, tweaks, polish, small features where the intent is clear and the work fits in a single session. No feature artifacts are produced. The PR body is the documentation. Use when you know what correct looks like and the change is contained.

**Feature build — use `/feature` → `/spec` or manual steps → `/build`.** Real features built from a written spec. A pre-build sequence (declaration → requirements → design → adversarial review → tests → DAG) produces committed artifacts. A DAG-driven build then executes wave-by-wave. Use when the work is deliberate, spans multiple components, or requires hard-to-reverse architectural decisions.

---

## Repo structure

```
/
├── CLAUDE.md              # operational map for the app
├── declaration.md         # what this project is and why
├── constitution.md        # principles, standards, decisions, patterns
├── README.md              # human-facing project readme
│
├── features/
│   └── [name]-[number]/   # one folder per feature
│       ├── declaration.md, requirements.md, design.md,
│       │   adversarial-review.md, dag.md, state.md,
│       │   verify.md, tests/, spec-summary.md,
│       │   build-deviations.md (created during build if design is contradicted)
│
└── .claude/
    └── commands/          # all skill commands
        ├── setup.md
        ├── declaration.md
        ├── patch.md
        ├── feature.md, requirements.md, architecture.md,
        │   adversarial.md, spec.md, dag.md,
        │   tests.md, next.md, build.md, retro.md
```

Feature folders are named `[feature-name]-[number]`. Numbers are sequential per feature name and disambiguate iterations — never overwrite a previous version, create a new numbered folder. Artifacts inside feature folders are populated by skills at runtime; never pre-create empty placeholders (several skills detect their pass number by checking which artifacts exist).

---

## Core documents

**`declaration.md`** — the project's statement of intent. What the project is, why it exists, for whom, what it explicitly does not do, the **Shape** (3–7 named components or seams the app will eventually have), and the **Roadmap** (3–7 anticipated features in rough order). The first four sections are durable; Shape and Roadmap are explicitly revisable as the project learns. Shape is not architecture — it commits to no contracts or data models. Roadmap is not a commitment — it is memory, capturing the "what comes next" thinking that otherwise evaporates between project setup and feature 2.

**`constitution.md`** — the project's accumulated judgment. Contains: the standards registry (Apple HIG, WCAG, OWASP, OpenAPI), architectural principles, patterns in use (frontend stack, commit style, service layout), quality gates that must hold before any PR, the testing framework and run command (populated on first test generation), the state-file format spec, and the decision log.

**`CLAUDE.md`** — the app's operational map. Repo layout pointers, read-before-build discipline lines, run/test/deploy context for whichever target the app uses, and user-global identity coordinates (carried in-file because the cloud sandbox has no `~/.claude/CLAUDE.md`).

Every skill reads constitution.md and declaration.md before architectural decisions. Most skills read the relevant feature artifacts in order.

---

## Standards registry

Lives in `constitution.md` under `## Standards`. Default entries:

| Domain | Standard |
|---|---|
| Interface | Apple Human Interface Guidelines |
| Accessibility | WCAG 2.1 AA |
| Security | OWASP Top 10 |
| API contracts | OpenAPI Specification |

Extended entries available when relevant: Microsoft REST API Guidelines (external APIs), OWASP Top 10 for LLMs (AI integration), OWASP ASVS (sensitive data).

Skills follow these standards without deviation unless `declaration.md` explicitly requires otherwise. Any deviation must be surfaced as a decision, not made silently.

---

## Running a quick change

```
/patch
```

The skill reads CLAUDE.md and constitution.md, identifies the minimal change, presents a plan with breakage risk surfaced, waits for approval, implements only that change, runs existing tests, and opens a PR.

Test failures get one remediation attempt; a second failure stops and reports.

The PR body has four sections (Intent / Change / Verification / Risk) — this is the record of the change. For work that refines a prior feature, it also reads that feature's artifacts.

---

## Running a feature build

The feature build pipeline has a pre-build sequence, two iterative loops, and a DAG-driven build. The pre-build artifacts get committed as they're produced.

### Pre-build sequence

The pre-build steps can be run manually or orchestrated automatically. Both options produce identical artifacts — the difference is how much you're involved between steps.

**Orchestrated (recommended for most features)**

```
/declaration                        # one-time per project
/feature         feature-name: [name]
/spec            feature-name: [name]
```

`/spec` drives everything from requirements through test generation automatically, using focused sub-agents for each step so each artifact gets full-context quality. It stops only when a decision requires product judgment: scope drift, declaration tension, an unresolvable HIGH finding, or a risk acknowledgment that only you can make. At the end it produces a `spec-summary.md` — a PM-level report covering what the feature does, what risks were acknowledged, what's out of scope, and a build-session preview. Read that, start a new session, and run `/build`.

**Manual (for refinement or closer involvement)**

```
/declaration                        # one-time per project
/feature         feature-name: [name]
/requirements    feature-name: [name]
/architecture    feature-name: [name]
... (iterate requirements ↔ architecture until convergence)
/adversarial     feature-name: [name]
... (address findings via the loop; re-run adversarial)
/tests           feature-name: [name]
/dag             feature-name: [name]
```

Run steps manually when you want to review and shape each artifact before the next step runs, when you're iterating on a particularly complex or ambiguous feature, or when you want to resume at a specific point. The two approaches are interchangeable — `/spec` detects which artifacts already exist and resumes from the right point, so you can switch between manual and orchestrated mid-pipeline.

**`declaration`** — project-level coach. Produces `declaration.md` at repo root, including the **Shape** section (3–7 named components/seams) and the **Roadmap** section (3–7 anticipated features in rough order, each tagged with the seams it touches). One-time at setup; re-runnable to refine or extend Shape and Roadmap as the project learns. The Roadmap is the bridge between project-level thinking and feature-level builds — it captures the "what comes next" intuition you have at setup so feature 2 doesn't start cold.

**`/feature`** — coaches a feature-level declaration anchored to the project declaration. Produces `features/[name]-[number]/declaration.md` (What / Why / Success / Shape touched / Out of scope). On invocation, the skill reads the Roadmap and proposes the next unbuilt entry as the default starting point. The user can confirm, override, or update the Roadmap if the sequence has shifted.

The skill behaves differently depending on whether prior features exist:
- **First-feature mode (walking skeleton).** When no prior feature folders exist, the skill coaches toward the thinnest vertical slice that exercises every seam in the project Shape end-to-end. Most behaviors are stubbed; the success criterion is "all the seams meet." This gives later features a working spine to iterate against instead of a blueprint.
- **Normal mode (feature 2+).** Coaches toward depth on a coherent slice. References the Shape to ask which components the feature touches; a feature that touches every seam is either another skeleton (legitimate if the Shape has grown) or a feature trying to do too much (split it).

Size sanity check at the end of declaration: can the value be described in one sentence without "and" doing heavy lifting? Multiple "ands" usually means multiple features. Surface mis-sizing here — it's far cheaper to re-do the declaration than to re-do requirements, design, and DAG.

**The requirements ↔ architecture loop.** Each skill writes a stability marker at the bottom of its output when it has no new flags to surface (`Requirements stable — no architectural feedback to incorporate`; `Architecture stable — no requirements changes flagged`). The loop has converged when both the most recent `requirements.md` and `design.md` carry their markers. Iterate as many times as needed — twice is common, once is enough for trivial work, more is needed when committed architecture surfaces new constraints.

**`/adversarial`** — reviews requirements + design through six lenses (integrity, coverage, security, standards compliance, failure modes, scope drift). Outputs `adversarial-review.md` as a living artifact: every finding has a stable ID (F-001, F-002…), severity (HIGH / MEDIUM / LOW), a recommended action naming which skill should address it, and a status (`open` / `addressed` / `acknowledged` / `resolved` / `deferred`). Zero findings is a valid outcome — the skill judges readiness, it does not manufacture findings to justify a pass.

The skill is bounded against infinite re-running and tuned for verification quality:
- **Stop condition.** A re-run against unchanged requirements.md and design.md exits without re-deriving findings (it compares against the commit SHA stored in the prior review's header).
- **Located findings only.** Security findings must name a file:line or specific spec section; LOW findings are dropped if they have no location.
- **Pattern-reuse scoping.** When `design.md` marks a surface `Reuses pattern: X` against the constitution's pattern registry, the security and failure-modes lenses for that surface drop to HIGH-severity-only review.
- **Attack the fix.** Verifying an `addressed` finding means re-attacking the proposed mitigation, not just confirming it exists. A fix that closes the original gap but introduces an adjacent one stays `open`.
- **Severity inheritance.** Findings carry unmitigated severity. An acknowledged HIGH stays HIGH on the registry; acceptance is recorded in status, not by lowering severity.
- **Constitution propagation.** Acknowledged findings are appended to `constitution.md`'s `## Acknowledged risks` table so cumulative risk across features is visible at the project level.

When findings exist, the user re-enters the req↔arch loop. `/requirements` and `/architecture` each read `adversarial-review.md`, address every `open` finding routed to them, and mark those findings `addressed`. The next run of `/adversarial` verifies the claims and promotes verified findings to `resolved`.

**`/dag`** — gates on (a) both req and arch reporting stable, (b) no `open` HIGH findings in adversarial review, and (c) `tests/` and `verify.md` existing. Produces `dag.md` (tasks with ID, description, inputs, outputs, dependencies, wave, acceptance condition) grouped into parallel waves, initializes `state.md` with every task `pending`, and applies task ID labels to the existing tests by updating `verify.md` with the authoritative task → test mapping.

**One DAG per session.** A feature build is designed to run end-to-end in one Sonnet conversation: `/build` drives the whole DAG without crossing a session boundary. The state.md / `/next` machinery exists as resilience for sandbox failures, not as a design license for multi-session features. This means the *whole DAG must fit one orchestrator session's working window* — pre-build artifacts in context, plus the code each task produces, plus test output between waves.

The DAG-generation skill sanity-checks the generated DAG against this budget before committing. A DAG of 1–2 tasks was probably too small for a full pipeline (the skill recommends using `/patch` instead); a DAG that doesn't fit on one screen, runs more than ~3–4 waves, or loads heavy new context (new framework, new dependency, new deploy path) is too large (the skill recommends splitting the feature). The right response to "too large" is to split, not to plan on resuming across sessions. Walking-skeleton features get accommodation on breadth, but if the skeleton's surface still won't fit, the right move is a thinner skeleton — touch a subset of seams in feature 1, extend in feature 2.

**`/tests`** — generates tests in the chosen framework from requirements and design. Tests fall into two categories: behavioral tests (from requirements) and integration tests from design seams (from design — test that seams hold, not that specific call signatures were used). `verify.md` maps each requirement and design seam to the tests that cover it; the task → test mapping is added by `/dag`. If tests already exist from a prior generation, they get regenerated (the prior tests were tied to the prior spec).

### Build

```
/build      feature-name: [name]
```

Orchestrates the DAG. Internally invokes `/next` in a loop until `state.md` shows every task complete, then runs the full test suite and opens a PR. The PR body has sections for Feature declaration / Requirements / Design / Adversarial review / Build summary / Risk.

`/next` is the per-wave executor — it's user-invokable to resume a partial DAG after a session ended, or for manual single-wave execution. One wave per invocation matches the cloud-sandbox session boundary, so `state.md` is always durable at a clean checkpoint.

**Commit mode per wave.** Single-task waves run in *folded mode*: the state.md update folds into the implementation commit (one commit per task). Multi-task waves, or waves likely to cross a session boundary, run in *checkpointed mode* with separate `in-progress` and `complete` commits for resumability. Failures always get their own durable commit regardless of mode.

Tasks within a wave may run in parallel via sub-agents. Tests tagged to those task IDs run after the wave; a failed test sets the responsible task back to `failed` and stops the loop.

Build skills treat requirements as immutable. Tests are presumed correct — the default assumption when a test fails is that the implementation is wrong, not the test. When a test genuinely contains an error (wrong assertion, incorrect assumption about the library or requirements), the build agent may correct it using good judgment and must document the change in `build-deviations.md` (which test changed, what the original assertion was, why it was wrong, what was corrected). Design is a recommendation — if a call shape doesn't exist or a library behaves differently than described, the build agent satisfies the behavioral requirement another way and records the deviation in `features/[name]-[#]/build-deviations.md`. If a requirement looks wrong during build, the skill stops and surfaces it — the resolution is to update those artifacts and regenerate the DAG.

**Build-surfaced upstream findings are normal, not failures.** It is common for build agents to discover that a design constraint can't be satisfied exactly as written. This is part of the workflow, not a signal to abandon the feature. The build-deviations file gives the build agent a legitimate channel for "I went a different way, here's why," without halting the DAG or silently editing the spec. After build, you can re-run `/adversarial` against the actual implementation — build-deviations entries are candidate findings that flow back into the req↔arch loop exactly like any other finding.

### Retro

```
/retro      feature-name: [name]
```

Optional, but recommended after each feature build. Coached conversation that produces `features/[name]-[#]/retro.md` capturing what went well, what went badly (with adversarial-finding IDs and DAG task IDs where applicable), loop iteration counts, and concrete proposed additions to `constitution.md`, `CLAUDE.md`, and skill prompts. Project-vs-template recommendations are marked separately so template-level lessons can be lifted directly into a framework-update PR. Without this, retros happen in chat and evaporate; with it, learning compounds across features.

---

## New project setup

After cloning the template:

1. Run `/setup` — coached fill of `CLAUDE.md` (project name, one-line description, run/test/deps block, deployment target) and replacement of the template `README.md` with an app stub. Commits to the current branch but does not push or open a PR; `/declaration` continues on the same branch.
2. Run `/declaration` to populate the project declaration (intent + Shape + Roadmap).
3. Edit `constitution.md`'s app-specific sections (architectural principles, patterns, quality gates, out-of-scope) as the project develops; the template ships with universal defaults already populated.
4. Pick your approach for your first piece of work and run the corresponding command.

The standards registry, default principles, and patterns ship pre-filled. You can prune anything that doesn't apply to this app (e.g., remove the frontend stack entry for a backend-only project).

---

## Keeping the framework up to date

The framework evolves — skill commands get improved, new skills are added, and the template sections of `CLAUDE.md` and `constitution.md` are refined. Downstream projects stay in sync using `/upgrade`.

### What `/upgrade` does

```
/upgrade
```

The skill fetches the latest versions of all framework-owned files from `Eviebot3000/evie-dev-framework` and writes them into the current project. It then opens a PR so the upgrade is visible and reviewable before merging.

**Framework-owned files** (replaced wholesale — projects have no reason to customize these):

| Path | Notes |
|---|---|
| `FRAMEWORK_VERSION` | Date-based version marker |
| `user-guide.md` | This document |
| `features/README.md` | Feature folder conventions |
| `.claude/commands/*.md` | All skill command definitions |

**Mixed files** (never replaced wholesale — contain project-specific content alongside framework template sections):

`CLAUDE.md` and `constitution.md` each have sections the framework owns (e.g., `## Build flow note`, `## Standards`, `## Artifact formats`) and sections the project owns (e.g., project name, run/test/deploy blocks, decision log). `/upgrade` compares the framework-owned sections and surfaces any differences as a manual review checklist in the PR body. Apply what's relevant, skip what isn't.

### First-time bootstrap for pre-existing projects

Projects set up before `/upgrade` existed don't have the skill yet. Bootstrap it in one step: open a Claude Code session on the old project and say:

> Run `curl -sf https://raw.githubusercontent.com/Eviebot3000/evie-dev-framework/main/.claude/commands/upgrade.md -o .claude/commands/upgrade.md` via the Bash tool.

Then run `/upgrade` to pull in the rest.

The `/upgrade` skill uses the same `curl` approach for all subsequent framework file fetches — it never uses the GitHub MCP server (scoped to the current project only) or WebFetch (blocked by sandbox network policy).

### Version tracking

`FRAMEWORK_VERSION` holds a date (`YYYY-MM-DD`) indicating when the framework was last fetched. The upgrade skill reads it to detect whether an upgrade is needed and reports it in the commit and PR. If you need to force a re-upgrade (same-day update), delete `FRAMEWORK_VERSION` locally before running the skill.

---

## Command reference

| Command | Reads | Produces |
|---|---|---|
| `/setup` | CLAUDE, README, user-guide | initialized `CLAUDE.md` + stub `README.md` + `declaration.md`, committed |
| `/declaration` | declaration | updated `declaration.md` — for refining Shape, Roadmap, or scope on an existing project |
| `/upgrade` | `FRAMEWORK_VERSION` (local + framework), framework-owned files | updated skill commands, `user-guide.md`, `FRAMEWORK_VERSION`; PR with manual review checklist |
| `/patch` | constitution, CLAUDE, feature artifacts (if refining prior work) | code change, commit, PR |
| `/feature` | declaration, constitution (+ existing feature declaration on re-run) | `features/[name]-[#]/declaration.md` |
| `/spec` | constitution, declarations, all pre-build artifacts (resumes from current state) | drives requirements → architecture → adversarial → tests → DAG; `spec-summary.md` |
| `/requirements` | constitution, declarations, design (if exists), adversarial-review (if exists) | `requirements.md` with stability marker |
| `/architecture` | constitution, declarations, requirements, design (if exists), adversarial-review (if exists) | `design.md` with stability marker |
| `/adversarial` | constitution, declarations, requirements, design, prior adversarial-review (if exists) | `adversarial-review.md` (living artifact) |
| `/dag` | all pre-build artifacts + `verify.md`, `tests/` | `dag.md`, `state.md`, updated `verify.md` (task → test mapping) |
| `/tests` | constitution, declarations, requirements, design | `verify.md`, `tests/` |
| `/build` | all pre-build + state + verify | drives DAG; final tests; PR |
| `/next` | constitution, dag, state, verify | executes one wave; updates state |
| `/retro` | constitution, declarations, all feature artifacts, git log | `features/[name]-[#]/retro.md` |
