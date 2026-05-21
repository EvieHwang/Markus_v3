---
description: Derives executable tests in features/[feature-name]-[number]/tests/ plus a human-readable coverage summary at verify.md.
---

Read constitution.md and declaration.md, then features/[feature-name]-[number]/intent.md, then features/[feature-name]-[number]/plan.md.

Check the `## Testing` section in constitution.md.
- If it names a framework, use it.
- If it is empty, choose the framework that best fits the project's stack and any existing tests. Surface the choice and the run command to the user, confirm, then populate the `## Testing` section in constitution.md with the chosen framework and run command. This is a one-time decision per project.

Derive two categories of tests in this order:
1. **Behavioral tests** — from intent: does it do what the user needs?
2. **Structural tests** — from plan: does it implement correctly given the architectural constraints?

If a requirement cannot be tested as written, surface the gap explicitly and stop. A weak test is worse than no test because it creates false confidence. Resolve the gap by updating intent.md or plan.md before continuing.

Outputs:
- `features/[feature-name]-[number]/verify.md` — human-readable test summary and coverage rationale; this is the artifact the user reviews.
- `features/[feature-name]-[number]/tests/` — executable tests in the chosen framework. The user does not normally read these directly; a separate agent interprets them on request.

Present the verify summary to the user for review. Revise until coverage is sound.

Commit verify.md, the test files, and (if updated) constitution.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: both verify.md and the test files exist, every behavioral and structural requirement has a test, the user has confirmed coverage via the summary, the `## Testing` section in constitution.md is populated, and all files are committed.
