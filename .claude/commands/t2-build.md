---
description: Builds the feature from intent/plan/verify until all tests pass, then opens a PR.
---

Read in this order: constitution.md, declaration.md, features/[feature-name]-[number]/intent.md, features/[feature-name]-[number]/plan.md, features/[feature-name]-[number]/verify.md. Note the test run command from constitution.md's `## Testing` section.

Implement the feature described by intent and plan. Do not expand scope, refactor adjacent code, or add capabilities beyond what intent and plan describe — even if you see opportunities.

The tests in features/[feature-name]-[number]/tests/ are the spec. Do not modify them to make them pass. If a test appears wrong, stop and surface the conflict — the resolution is to update intent or plan and regenerate tests via t2-verify, not to edit them in place.

Run tests using the command from constitution.md's `## Testing` section.

Build until every test passes. Do not consider the feature complete until then.

On test failure: attempt one remediation. If it fails again, stop and report with full context. Do not proceed.

A second failure after remediation usually signals a conflict between spec and implementation, not a coding mistake. Continued retries thrash toward green by tweaking surface symptoms; escalation to the user surfaces the deeper issue earlier.

Commit using conventional commit format, one commit per logical unit of work, on the current branch (the sandbox provisions this; do not create a new one).

Open a PR against `main` with these sections:
- **Intent** — link to features/[feature-name]-[number]/intent.md and summarize.
- **Plan** — link to plan.md and summarize the approach.
- **Verification** — link to verify.md and report test results.
- **Risk** — what this change could affect; anything to watch.

Exit condition: every test in features/[feature-name]-[number]/tests/ passes, commits follow convention, and the PR is open against `main`.
