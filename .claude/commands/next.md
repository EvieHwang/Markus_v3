---
description: Executes one wave of features/[feature-name]-[number]/dag.md — implements each task in the wave, runs the tests tagged to those tasks, updates state.md.
---

Read constitution.md, features/[feature-name]-[number]/dag.md, features/[feature-name]-[number]/state.md, and features/[feature-name]-[number]/verify.md. Note the test run command from constitution.md's `## Testing` section.

Identify the next wave to execute:
- If all tasks in state.md are `complete`, exit with "all tasks complete — ready for final test run and PR."
- If any task is `in-progress` or `failed`, do not start a new wave; report the in-flight state and stop.
- Otherwise, the next wave is the lowest-numbered wave with `pending` tasks.

**Commit policy.** The separate state.md commit exists for resumability across session boundaries, not bookkeeping. Choose the commit mode for this wave up front:
- **Folded mode** — single-task waves, when the task is expected to complete within this session. Skip the `in-progress` state commit; fold the `complete` state update into the implementation commit (one commit per task).
- **Checkpointed mode** — multi-task waves, or any wave where a sandbox session boundary is likely (long-running task, prior history of failures in this DAG, explicit user request). Commit `in-progress` before implementation and `complete` after, as separate commits.
- **Failure override** — regardless of mode chosen, if a task fails partway through, commit state.md with status `failed` and the reason as its own commit. Failure always gets a durable checkpoint.

For each task in the identified wave:
- Read only the inputs that task requires (per its DAG entry).
- In checkpointed mode: set status to `in-progress` in state.md, commit. In folded mode: skip this step.
- Run the tests tagged to this task and confirm they are failing in the expected way — correct module, correct error type, not a false pass. A test that passes before its task has been implemented is tagged incorrectly or is testing the wrong thing; stop and fix the test before writing any implementation code.
- Implement the task.
- Verify against the task's acceptance condition.
- On success: set status to `complete`, note the commit SHA in state.md. In checkpointed mode commit state.md separately; in folded mode include the state.md update in the implementation commit.
- On failure: set status to `failed`, note the reason in state.md, commit (always separate, see failure override), stop.

Tasks within a wave may be run in parallel via sub-agents (Agent tool). Dependencies are guaranteed satisfied within a wave, so parallel execution is safe.

After all wave tasks complete:
- Run the tests tagged with this wave's task IDs (consult verify.md for the task → test mapping).
- On test failure for a completed task: set the responsible task back to `failed`, note the reason, commit, stop.

Do not advance past one wave. `/build` re-invokes this skill in a loop to drive the full DAG to completion; invoke it directly to resume a partial DAG (after a session ended) or for manual single-wave execution. One wave per invocation matches the cloud-sandbox session boundary, so state.md is always durable at a clean boundary.

Exit condition: every task in the targeted wave is `complete`, tests tagged to those tasks pass, state.md reflects the current truth, and all changes are committed.
