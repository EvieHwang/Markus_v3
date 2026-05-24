---
description: Adversarial review of features/[feature-name]-[number]/ — finds problems in requirements and design. Outputs adversarial-review.md as a living artifact with stable finding IDs.
---

You are a reviewer judging whether requirements and design are ready to build. Zero findings is a valid outcome when the spec is sound. Only surface a finding if you can name a concrete failure mode it would cause — generic concerns ("consider adding more error handling", "think about scale") are not findings and must be dropped.

Read in order: constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, features/[feature-name]-[number]/design.md. If features/[feature-name]-[number]/adversarial-review.md already exists, read it too.

**Stop condition (re-run guard).** If adversarial-review.md exists, run `git log -1 --format=%H -- features/[feature-name]-[number]/requirements.md features/[feature-name]-[number]/design.md` and compare against the commit recorded in the existing adversarial-review.md's header. If neither file has changed since the last review:
- Do not re-run the lenses.
- Report "No changes to requirements.md or design.md since adversarial review at [SHA] — open findings remain as previously documented."
- Exit without modifying the file.

If the files have changed, scope this pass to what changed: re-examine sections touched by the diff and any finding whose subject overlaps the diff. Do not re-derive findings against unchanged content.

**Mode declaration.** State at the top of adversarial-review.md which mode this pass ran in:
- **Fresh review** — no prior adversarial-review.md, or the diff since last review is substantial (multiple sections, new components, new requirements). Run the full lens sweep.
- **Verification pass** — prior adversarial-review.md exists and the diff is targeted (addressing specific findings, surgical edits like one clause or one bootstrap argument). Scope strictly to (a) verifying each `addressed` finding is genuinely fixed in the latest requirements.md/design.md, and (b) attacking the fix itself with the original lens for adjacent-gap regressions. Do not surface new findings against unchanged content.

Pick the mode based on the diff before starting. A surgical fix does not warrant a full lens sweep.

Review through these lenses:
- **Scope check (run before all others).** For each candidate finding, trace its subject to a specific sentence in declaration.md, the feature declaration, or requirements.md. If the finding is about *how* the design implements something — a specific call signature, an internal attribute name, a library API shape, a constructor argument — rather than *what* the feature requires, do not file it. Surface it instead as feedback to `/architecture` with the note "implementation prescription, not behavioral constraint." Only findings whose subjects trace to declared behavior reach the remaining lenses.
- **Integrity** — do the documents contradict each other? Does the design implement the requirements? Do the requirements serve the feature declaration?
- **Coverage** — what behaviors are unspecified? What edge cases are missing?
- **Security** — what attack surfaces does the design expose? Does it comply with constitution.md's security standards? **Every security finding must name the specific file and line where the vulnerability would manifest (or, pre-implementation, the specific component and the requirement/design section).** Findings that only restate a pattern ("SQL injection risk") without naming where it lands are not actionable — drop them or merge into a located finding.
- **Standards compliance** — does the design respect every applicable item in constitution.md's standards registry (accessibility, API contracts, interface)?
- **Failure modes** — what breaks silently vs. visibly? What recovery is missing?
- **Scope drift** — what has been added beyond the feature declaration? Beyond the project declaration?

**Pattern-reuse scoping.** If design.md declares `Reuses pattern: X` for an attack surface or component (per the architecture skill's pattern-reuse marker), scope the security and failure-modes lenses for that surface to HIGH severity only — assume the constitution-registered pattern is already vetted. Note at the top of adversarial-review.md which lenses were scoped down and why.

**LOW-severity bar.** A LOW finding is only emitted if it names a specific file:line (or specific requirement/design section). LOW findings without a location are dropped.

If adversarial-review.md exists, this is a re-run:
- For every finding marked `addressed`, verify the fix exists in the latest requirements.md / design.md **and** treat the fix itself as a new finding to attack. Apply the original lens (and any others that fit) to the proposed mitigation. A fix that addresses the letter of the original finding but introduces an adjacent gap stays `open` with a follow-on note — do not promote it to `resolved`. Promotion to `resolved` requires both: the fix is present, and the fix itself withstands the lens.
- Findings marked `acknowledged` or `deferred` stay as-is unless something has changed that invalidates the acceptance.
- Add new findings discovered in this pass with new IDs.

**Severity inheritance.** Findings carry their *unmitigated* severity, not their mitigated severity. An acknowledged HIGH stays HIGH in the registry; the acceptance is recorded in the status, not by lowering severity. This keeps the registry honest about what risk the project carries.

**Acknowledged findings propagate to the constitution.** When a finding is marked `acknowledged`, append one row to the `## Acknowledged risks` table in constitution.md with: feature name, finding ID (e.g., F-002), severity, one-line risk, one-line rationale, mitigation (or "none"). If the section does not exist yet, create it per the format documented in the constitution template. This is the project-level surface for cumulative risk.

Write features/[feature-name]-[number]/adversarial-review.md. Start with a one-line header recording the commit SHA of requirements.md and design.md at the time of this review (used by the stop condition on the next run). Then two sections:

`## Open findings`
For each open finding:
- **ID** — stable identifier (F-001, F-002, …). Never reuse.
- **Severity** — HIGH (blocks DAG generation), MEDIUM (must be addressed or explicitly acknowledged before DAG), LOW (documented but non-blocking).
- **Lens** — which lens surfaced this.
- **Finding** — what is wrong.
- **Recommended action** — which skill to re-run to address it (typically `/architecture` for design/security issues, `/requirements` for coverage/scope issues, or back to `/feature` for scope drift that needs re-scoping).
- **Status** — `open` / `addressed` (claimed by req/arch but not yet verified) / `acknowledged` (user accepts the risk without fix) / `deferred` (user defers to future work). Deferred findings carry a **Re-surface condition** note (e.g., "re-examine when the caching layer lands") so the next adversarial pass — including a post-build pass against the actual implementation — knows when to revisit them.

`## Resolved findings`
Findings that were addressed and verified. Keep IDs visible for audit trail; full text can be summarized.

`## Prescription feedback`
Items from the scope check identified as implementation prescriptions rather than behavioral constraints. Each entry names the specific design section containing the prescription and states why it is prescriptive rather than behavioral. These have no finding IDs and no severity — they are feedback for `/architecture` to restate as behavioral constraints. Omit this section entirely if the scope check found no prescriptions.

Present the open findings to the user. The user decides which to address, acknowledge, or defer. Resolution happens by re-entering the requirements ↔ architecture loop — adversarial does not modify those documents directly.

Commit the completed adversarial-review.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: features/[feature-name]-[number]/adversarial-review.md exists, every open finding has severity / lens / recommended action / status, prior addressed findings have been verified, the user has reviewed, and the file is committed.
