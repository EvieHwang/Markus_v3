---
description: Generates executable tests in features/[feature-name]-[number]/tests/ and a human-readable coverage summary at verify.md, tagged with DAG task IDs so the build agent knows which tests verify which tasks.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, features/[feature-name]-[number]/design.md, and features/[feature-name]-[number]/dag.md.

Check the `## Testing` section in constitution.md.
- If it names a framework, use it.
- If it is empty, choose the framework that best fits the project's stack and any existing tests. Surface the choice and the run command to the user, confirm, then populate the `## Testing` section in constitution.md with the chosen framework and run command. This is a one-time decision per project.

Derive two categories of tests:
1. **Behavioral tests** — from requirements: does it do what was specified?
2. **Structural tests** — from design: does it implement correctly given the architectural constraints?

Tag each test with the DAG task IDs whose acceptance conditions it verifies. A test may cover multiple tasks; a task may be covered by multiple tests. Every task in dag.md must have at least one test covering it.

If verify.md and tests/ already exist, regenerate from the current requirements / design / dag — prior tests are not preserved, they were tied to the prior version of the spec. The user should re-run this skill after any change to requirements, design, or dag.

If a requirement cannot be tested as written, surface the gap explicitly and stop. A weak test is worse than no test because it creates false confidence. Resolve the gap by updating requirements.md or design.md (re-entering the loop) before continuing.

Outputs:
- `features/[feature-name]-[number]/verify.md` — human-readable test summary and coverage rationale. Maps each DAG task to the tests that verify it. This is the artifact the user reviews.
- `features/[feature-name]-[number]/tests/` — executable tests in the chosen framework. The user does not normally read these directly; a separate agent interprets them on request.

Present the verify summary to the user for review. Revise until coverage is sound.

Commit verify.md, the test files, and (if updated) constitution.md to the current branch (the sandbox provisions this; do not create a new one).

Exit condition: both verify.md and the test files exist, every requirement and every DAG task has at least one test, every test is tagged with the task IDs it verifies, the `## Testing` section in constitution.md is populated, the user has confirmed coverage, and all files are committed.
