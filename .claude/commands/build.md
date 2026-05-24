---
description: Orchestrates the full feature build — drives the DAG wave by wave until all tasks are complete, then opens a PR.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, features/[feature-name]-[number]/design.md, features/[feature-name]-[number]/adversarial-review.md, features/[feature-name]-[number]/dag.md, features/[feature-name]-[number]/state.md, and features/[feature-name]-[number]/verify.md.

Verify the inputs are ready:
- requirements.md and design.md both report stable.
- adversarial-review.md has no `open` HIGH-severity findings; MEDIUM are `acknowledged` or `deferred`.
- dag.md exists and state.md is initialized.
- verify.md exists with task → test mapping.

If anything is missing or blocking, stop and tell the user which artifact needs attention.

Drive the DAG to completion:
1. Invoke the `/next` skill.
2. After it returns, re-read state.md and push the branch (`git push -u origin <current-branch>`). `/next` commits but does not push; the orchestrator pushes after each wave so the stop-hook stays quiet and state is durable across sandbox boundaries.
3. If any task is `failed`: stop and report. Do not retry — the user inspects the failure and decides how to proceed (fix and resume, or re-enter the upstream loop to revise requirements/design).
4. If all tasks are `complete`: proceed to final verification.
5. Otherwise: loop back to step 1 **immediately**. Do not pause to present the wave's results or ask the user whether to continue — the user invoked `/build` to drive the DAG end-to-end. The only autonomous stops are a `failed` task, completion, or a sandbox-imposed interruption.

This works equally for a fresh build and for resuming a partial DAG from a prior session — `/next` reads state.md and picks up where things left off.

**Async sub-agent launches.** If invoking `/next` returns "Async agent launched" (harness behavior on long-running agents), wait for the completion notification before re-invoking. Do not poll or fire additional tool calls in the meantime.

The implementation is the DAG, not your judgment.

**Tests are the build's source of truth — do not modify them to accommodate implementation choices.** When a test fails, assume the implementation is wrong. If, after genuine investigation, the test itself contains a clear error (wrong assertion, constraint built on a false assumption about the library or requirements), you may correct it — but you must document the change in `features/[feature-name]-[number]/build-deviations.md` (create it if it doesn't exist): record which test changed, what the original assertion was, why it was wrong, and what was corrected. **Requirements remain immutable.** If a requirement looks wrong, stop and surface it — the resolution is to revise requirements and regenerate the DAG.

**Design is a recommendation, not an immutable contract.** If implementation reality contradicts the design — a call shape does not exist, a library behaves differently than described, an API has changed — satisfy the behavioral requirement using a different approach. Record the deviation in `features/[feature-name]-[number]/build-deviations.md` (create it if it does not exist): note the design section contradicted, what was done instead, and why. Do not silently edit design.md in place. On any subsequent `/adversarial` pass, build-deviations entries are treated as candidate findings that flow back into the req↔arch loop.

Final verification:
- Run the full test suite using the command in constitution.md's `## Testing` section. Per-wave runs in `/next` only execute tests tagged to that wave's tasks; the final full-suite run catches end-to-end and cross-cutting tests that aren't tied to any single task.
- All tests must pass. If any fail, set the responsible task back to `failed`, commit state.md, stop, and report.

Open a PR against `main` with these sections:
- **Feature declaration** — link to features/[feature-name]-[number]/declaration.md and summarize.
- **Requirements** — link to requirements.md and summarize.
- **Design** — link to design.md and summarize the architecture.
- **Adversarial review** — link to adversarial-review.md. Note `acknowledged` and `deferred` findings and why they were accepted.
- **Build summary** — DAG completion by wave; commit SHAs for each task; final test results.
- **Risk** — anything to watch in subsequent work.

Exit condition: every task in state.md is `complete`, the full test suite passes, all changes are committed, and the PR is open against `main`.
