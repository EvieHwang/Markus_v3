---
description: Generates executable tests in features/[feature-name]-[number]/tests/ and a human-readable coverage summary at verify.md. Tests derive from requirements and design; task ID labels are applied by /dag after the DAG is committed.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, and features/[feature-name]-[number]/design.md.

Check the `## Testing` section in constitution.md.
- If it names a framework, use it.
- If it is empty, choose the framework that best fits the project's stack and any existing tests. Surface the choice and the run command to the user, confirm, then populate the `## Testing` section in constitution.md with the chosen framework and run command. This is a one-time decision per project.

Derive two categories of tests:
1. **Behavioral tests** — from requirements: does it do what was specified?
2. **Integration tests from design seams** — from design: do the seams hold? Test that timeouts fire at the right boundaries, errors map to the right taxonomy, and interfaces between components behave as designed. Do not test that specific constructors were called with specific arguments, that private attributes hold specific values, or that internal call signatures match what design described — those test the implementation, not the seam. If a candidate test reads private state or asserts a specific call shape, rewrite it to assert the observable behavior the seam should produce.

If verify.md and tests/ already exist, regenerate from the current requirements and design — prior tests are not preserved, they were tied to the prior version of the spec. The user should re-run this skill after any change to requirements or design.

If a requirement cannot be tested as written, surface the gap explicitly and stop. A weak test is worse than no test because it creates false confidence. Resolve the gap by updating requirements.md or design.md (re-entering the loop) before continuing.

Outputs:
- `features/[feature-name]-[number]/verify.md` — human-readable test summary and coverage rationale. Maps each requirement and design seam to the tests that verify it. The task → test mapping is added later by /dag. This is the artifact the user reviews.
- `features/[feature-name]-[number]/tests/` — executable tests in the chosen framework. The user does not normally read these directly; a separate agent interprets them on request.

Present the verify summary to the user for review. Revise until coverage is sound.

Commit verify.md, the test files, and (if updated) constitution.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: both verify.md and the test files exist, every requirement has at least one test, the `## Testing` section in constitution.md is populated, the user has confirmed coverage, and all files are committed.
