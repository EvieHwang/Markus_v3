# User Guide

A three-tier build framework for Claude Code, distributed as a template repository. Each tier matches a different size of work: T1 for bounded changes that fit a single session, T2 for features that need a written spec before building, T3 for work too large to hold in one context window. Choose the tier that matches the scope. The framework provides skill commands (in `.claude/commands/`) that produce specification artifacts in `features/[name]-[number]/` and then build against them. The artifacts are the contract between what you wanted and what got built.

---

## The three tiers

**Tier 1 — small bounded change.** Bug fixes, tweaks, polish, small features where the intent is clear and the work fits in a single session. No feature artifacts are produced. The PR body is the documentation. Use when you know what correct looks like and the change is contained.

**Tier 2 — feature build.** Real features built from a written spec. A four-skill sequence produces intent → plan → verify (tests) → build. All four skills run in a single context window. Use when the work is deliberate but contained — you could complete it in a focused session if the spec were already written.

**Tier 3 — full system build.** Large features or full applications that don't fit in one context window. A pre-build sequence (declaration → requirements → design → adversarial review → DAG) produces committed artifacts. A DAG-driven build then executes across multiple sessions, advancing wave-by-wave. Use when the work spans multiple components, requires hard-to-reverse architectural decisions, or won't complete in one focused session.

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
│       ├── (T2: intent.md, plan.md, verify.md, tests/)
│       └── (T3: declaration.md, requirements.md, design.md,
│                adversarial-review.md, dag.md, state.md,
│                verify.md, tests/)
│
└── .claude/
    └── commands/          # all skill commands
        ├── setup.md
        ├── declaration.md
        ├── t1-build.md
        ├── t2-intent.md, t2-plan.md, t2-verify.md, t2-build.md
        ├── t3-feature-declaration.md, t3-requirements.md,
        │   t3-architecture.md, t3-adversarial.md, t3-generate-dag.md,
        │   t3-test-coach.md, t3-next-step.md, t3-build.md, t3-retro.md
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

## Running Tier 1

```
/t1-build
```

The skill reads CLAUDE.md and constitution.md, inspects the affected module (and any existing feature artifacts if this is refining T2/T3 output), proposes a minimal plan with breakage risk surfaced, waits for approval, implements only the minimal change, runs existing tests, and opens a PR.

Test failures get one remediation attempt; a second failure stops and reports.

The PR body has four sections (Intent / Change / Verification / Risk) — this is the record of the change.

---

## Running Tier 2

Four skills in sequence. Each commits its artifact to the current branch.

```
/t2-intent     feature-name: [name]
/t2-plan       feature-name: [name]
/t2-verify     feature-name: [name]
/t2-build      feature-name: [name]
```

**`t2-intent`** — coached conversation, then writes `intent.md` (Purpose, User stories, Out of scope). Confirm before output; review the written doc before continuing.

**`t2-plan`** — reads intent. Surfaces architectural considerations and the implementation approach. If a consideration reshapes the intent, the skill stops and the user updates intent.md before re-running. This feedback loop is the primary quality lever in T2.

**`t2-verify`** — derives behavioral tests (from intent) and structural tests (from plan). On first use in a project, the skill picks a test framework and writes it into constitution.md's `## Testing` section. Outputs a human-readable `verify.md` summary plus executable test files. Untestable requirements stop the skill — fix intent or plan first.

**`t2-build`** — implements until every test passes. Treats tests as immutable spec (never edits them to make them pass). On a test failure, attempts one remediation, then stops. Opens a PR with sections for Intent / Plan / Verification / Risk.

---

## Running Tier 3

T3 has a pre-build sequence, two iterative loops, and a DAG-driven build. The pre-build artifacts get committed as they're produced.

### Pre-build sequence

```
/declaration                        # one-time per project
/t3-feature-declaration  feature-name: [name]
/t3-requirements         feature-name: [name]
/t3-architecture         feature-name: [name]
... (iterate requirements ↔ architecture until convergence)
/t3-adversarial          feature-name: [name]
... (address findings via the loop; re-run adversarial)
/t3-generate-dag         feature-name: [name]
/t3-test-coach           feature-name: [name]
```

**`declaration`** — project-level coach. Produces `declaration.md` at repo root, including the **Shape** section (3–7 named components/seams) and the **Roadmap** section (3–7 anticipated features in rough order, each tagged with the seams it touches). One-time at setup; re-runnable to refine or extend Shape and Roadmap as the project learns. The Roadmap is the bridge between project-level thinking and feature-level builds — it captures the "what comes next" intuition you have at setup so feature 2 doesn't start cold.

**`t3-feature-declaration`** — coaches a feature-level declaration anchored to the project declaration. Produces `features/[name]-[number]/declaration.md` (What / Why / Success / Shape touched / Out of scope). On invocation, the skill reads the Roadmap and proposes the next unbuilt entry as the default starting point. The user can confirm, override, or update the Roadmap if the sequence has shifted.

The skill behaves differently depending on whether prior features exist:
- **First-feature mode (walking skeleton).** When no prior feature folders exist, the skill coaches toward the thinnest vertical slice that exercises every seam in the project Shape end-to-end. Most behaviors are stubbed; the success criterion is "all the seams meet." This gives later features a working spine to iterate against instead of a blueprint.
- **Normal mode (feature 2+).** Coaches toward depth on a coherent slice. References the Shape to ask which components the feature touches; a feature that touches every seam is either another skeleton (legitimate if the Shape has grown) or a feature trying to do too much (split it).

Size sanity check at the end of declaration: can the value be described in one sentence without "and" doing heavy lifting? Multiple "ands" usually means multiple features. Surface mis-sizing here — it's far cheaper to re-do the declaration than to re-do requirements, design, and DAG.

**The requirements ↔ architecture loop.** Each skill writes a stability marker at the bottom of its output when it has no new flags to surface (`Requirements stable — no architectural feedback to incorporate`; `Architecture stable — no requirements changes flagged`). The loop has converged when both the most recent `requirements.md` and `design.md` carry their markers. Iterate as many times as needed — twice is common, once is enough for trivial work, more is needed when committed architecture surfaces new constraints.

**`t3-adversarial`** — reviews requirements + design through six lenses (integrity, coverage, security, standards compliance, failure modes, scope drift). Outputs `adversarial-review.md` as a living artifact: every finding has a stable ID (F-001, F-002…), severity (HIGH / MEDIUM / LOW), a recommended action naming which skill should address it, and a status (`open` / `addressed` / `acknowledged` / `resolved` / `deferred`). Zero findings is a valid outcome — the skill judges readiness, it does not manufacture findings to justify a pass.

The skill is bounded against infinite re-running and tuned for verification quality:
- **Stop condition.** A re-run against unchanged requirements.md and design.md exits without re-deriving findings (it compares against the commit SHA stored in the prior review's header).
- **Located findings only.** Security findings must name a file:line or specific spec section; LOW findings are dropped if they have no location.
- **Pattern-reuse scoping.** When `design.md` marks a surface `Reuses pattern: X` against the constitution's pattern registry, the security and failure-modes lenses for that surface drop to HIGH-severity-only review.
- **Attack the fix.** Verifying an `addressed` finding means re-attacking the proposed mitigation, not just confirming it exists. A fix that closes the original gap but introduces an adjacent one stays `open`.
- **Severity inheritance.** Findings carry unmitigated severity. An acknowledged HIGH stays HIGH on the registry; acceptance is recorded in status, not by lowering severity.
- **Constitution propagation.** Acknowledged findings are appended to `constitution.md`'s `## Acknowledged risks` table so cumulative risk across features is visible at the project level.

When findings exist, the user re-enters the req↔arch loop. `t3-requirements` and `t3-architecture` each read `adversarial-review.md`, address every `open` finding routed to them, and mark those findings `addressed`. The next run of `t3-adversarial` verifies the claims and promotes verified findings to `resolved`.

**`t3-generate-dag`** — gates on (a) both req and arch reporting stable and (b) no `open` HIGH findings in adversarial review. Produces `dag.md` (tasks with ID, description, inputs, outputs, dependencies, wave, acceptance condition) grouped into parallel waves, and initializes `state.md` with every task `pending`.

**One DAG per session.** A T3 feature is designed to run end-to-end in one Sonnet conversation: `/t3-build` drives the whole DAG without crossing a session boundary. The state.md / `/t3-next-step` machinery exists as resilience for sandbox failures, not as a design license for multi-session features. This means the *whole DAG must fit one orchestrator session's working window* — pre-build artifacts in context, plus the code each task produces, plus test output between waves.

The DAG-generation skill sanity-checks the generated DAG against this budget before committing. A DAG of 1–2 tasks was probably T2-sized (the skill recommends downgrading); a DAG that doesn't fit on one screen, runs more than ~3–4 waves, or loads heavy new context (new framework, new dependency, new deploy path) is too large (the skill recommends splitting the feature). The right response to "too large" is to split, not to plan on resuming across sessions. Walking-skeleton features get accommodation on breadth, but if the skeleton's surface still won't fit, the right move is a thinner skeleton — touch a subset of seams in feature 1, extend in feature 2.

**`t3-test-coach`** — generates tests in the chosen framework, tagged by DAG task ID so the build agent knows which tests cover which task. Every task in `dag.md` must have at least one test. If tests already exist from a prior generation, they get regenerated (the prior tests were tied to the prior spec).

### Build

```
/t3-build      feature-name: [name]
```

Orchestrates the DAG. Internally invokes `/t3-next-step` in a loop until `state.md` shows every task complete, then runs the full test suite and opens a PR. The PR body has sections for Feature declaration / Requirements / Design / Adversarial review / Build summary / Risk.

`/t3-next-step` is the per-wave executor — it's user-invokable to resume a partial DAG after a session ended, or for manual single-wave execution. One wave per invocation matches the cloud-sandbox session boundary, so `state.md` is always durable at a clean checkpoint.

**Commit mode per wave.** Single-task waves run in *folded mode*: the state.md update folds into the implementation commit (one commit per task). Multi-task waves, or waves likely to cross a session boundary, run in *checkpointed mode* with separate `in-progress` and `complete` commits for resumability. Failures always get their own durable commit regardless of mode.

Tasks within a wave may run in parallel via sub-agents. Tests tagged to those task IDs run after the wave; a failed test sets the responsible task back to `failed` and stops the loop.

Build skills never modify requirements, design, dag, or tests. If something looks wrong during build, the skill stops and surfaces it — the resolution is to update upstream artifacts and regenerate the DAG, not edit in place.

### Retro

```
/t3-retro      feature-name: [name]
```

Optional, but recommended after each T3 build. Coached conversation that produces `features/[name]-[#]/retro.md` capturing what went well, what went badly (with adversarial-finding IDs and DAG task IDs where applicable), loop iteration counts, and concrete proposed additions to `constitution.md`, `CLAUDE.md`, and skill prompts. Project-vs-template recommendations are marked separately so template-level lessons can be lifted directly into a framework-update PR. Without this, retros happen in chat and evaporate; with it, learning compounds across features.

---

## New project setup

After cloning the template:

1. Run `/setup` — coached fill of `CLAUDE.md` (project name, one-line description, run/test/deps block, deployment target) and replacement of the template `README.md` with an app stub. Commits to the current branch but does not push or open a PR; `/declaration` continues on the same branch.
2. Run `/declaration` to populate the project declaration (intent + Shape + Roadmap).
3. Edit `constitution.md`'s app-specific sections (architectural principles, patterns, quality gates, out-of-scope) as the project develops; the template ships with universal defaults already populated.
4. Pick a tier for your first piece of work and run the corresponding command.

The standards registry, default principles, and patterns ship pre-filled. You can prune anything that doesn't apply to this app (e.g., remove the frontend stack entry for a backend-only project).

---

## Command reference

| Command | Reads | Produces |
|---|---|---|
| `/setup` | CLAUDE, README, user-guide | initialized `CLAUDE.md` + stub `README.md`, committed |
| `/t1-build` | constitution, CLAUDE | PR (no feature artifacts) |
| `/t2-intent` | constitution, declaration | `features/[name]-[#]/intent.md` |
| `/t2-plan` | constitution, declaration, intent | `features/[name]-[#]/plan.md` |
| `/t2-verify` | constitution, declaration, intent, plan | `verify.md`, `tests/`, populates `constitution.md` `## Testing` on first use |
| `/t2-build` | all of the above | code, commits, PR |
| `/declaration` | declaration | `declaration.md` (project root) |
| `/t3-feature-declaration` | declaration, constitution (+ existing feature declaration on re-run) | `features/[name]-[#]/declaration.md` |
| `/t3-requirements` | constitution, declarations, design (if exists), adversarial-review (if exists) | `requirements.md` with stability marker |
| `/t3-architecture` | constitution, declarations, requirements, design (if exists), adversarial-review (if exists) | `design.md` with stability marker |
| `/t3-adversarial` | constitution, declarations, requirements, design, prior adversarial-review (if exists) | `adversarial-review.md` (living artifact) |
| `/t3-generate-dag` | all pre-build artifacts | `dag.md`, `state.md` |
| `/t3-test-coach` | constitution, declarations, requirements, design, dag | `verify.md`, `tests/` |
| `/t3-build` | all pre-build + state + verify | drives DAG; final tests; PR |
| `/t3-next-step` | constitution, dag, state, verify | executes one wave; updates state |
| `/t3-retro` | constitution, declarations, all feature artifacts, git log | `features/[name]-[#]/retro.md` |
