---
description: Orchestrates the full T3 build — invokes t3-next-step in a loop until features/[feature-name]-[number]/state.md shows all tasks complete, then opens a PR.
---

Read constitution.md, declaration.md, features/[feature-name]-[number]/declaration.md, features/[feature-name]-[number]/requirements.md, features/[feature-name]-[number]/design.md, features/[feature-name]-[number]/adversarial-review.md, features/[feature-name]-[number]/dag.md, features/[feature-name]-[number]/state.md, and features/[feature-name]-[number]/verify.md.

Verify the inputs are ready:
- requirements.md and design.md both report stable.
- adversarial-review.md has no `open` HIGH-severity findings; MEDIUM are `acknowledged` or `deferred`.
- dag.md exists and state.md is initialized.
- verify.md exists with task → test mapping.

If anything is missing or blocking, stop and tell the user which artifact needs attention.

Drive the DAG to completion:
1. Invoke t3-next-step.
2. After it returns, re-read state.md.
3. If any task is `failed`: stop and report. Do not retry — the user inspects the failure and decides how to proceed (fix and resume, or re-enter the upstream loop to revise requirements/design).
4. If all tasks are `complete`: proceed to final verification.
5. Otherwise: loop back to step 1.

This works equally for a fresh build and for resuming a partial DAG from a prior session — t3-next-step reads state.md and picks up where things left off.

The implementation is the DAG, not your judgment. Do not modify requirements, design, dag, or tests during build. If something looks wrong, stop and surface it — the resolution is to update upstream artifacts (back into the loop) and regenerate the DAG, not to edit in place.

Final verification:
- Run the full test suite using the command in constitution.md's `## Testing` section. Per-wave runs in t3-next-step only execute tests tagged to that wave's tasks; the final full-suite run catches end-to-end and cross-cutting tests that aren't tied to any single task.
- All tests must pass. If any fail, set the responsible task back to `failed`, commit state.md, stop, and report.

Open a PR against `main` with these sections:
- **Feature declaration** — link to features/[feature-name]-[number]/declaration.md and summarize.
- **Requirements** — link to requirements.md and summarize.
- **Design** — link to design.md and summarize the architecture.
- **Adversarial review** — link to adversarial-review.md. Note `acknowledged` and `deferred` findings and why they were accepted.
- **Build summary** — DAG completion by wave; commit SHAs for each task; final test results.
- **Risk** — anything to watch in subsequent work.

Exit condition: every task in state.md is `complete`, the full test suite passes, all changes are committed, and the PR is open against `main`.
