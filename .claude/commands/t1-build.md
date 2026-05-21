---
description: Tier 1 — small bounded change (bug, tweak, polish, small feature). PR is the documentation.
---

Tier 1 — small bounded change. Use for bugs, tweaks, polish, or small features where the intent is clear and the work fits in a single session. No feature artifacts are produced — the PR is the documentation.

Before proposing the change:
- Read constitution.md and CLAUDE.md.
- If this work is refining output from an earlier T2 or T3 feature, read that feature's existing artifacts in features/[name]/.
- Identify the minimal change that achieves the intent.

Present the plan. Include: what's changing, why, and what the change could break or affect. Wait for approval before implementing.

Implement only the minimal change. Do not refactor adjacent code, rename, or expand scope — even if you see opportunities.

After implementing:
- Run existing tests.
- If a test fails: attempt one remediation. If it still fails, stop and report rather than proceeding.

Commit using conventional commit format (one commit per logical unit).

Open a PR. The PR body is the record of this change:
- **Intent** — what you set out to do and why.
- **Change** — what was actually modified.
- **Verification** — tests run and any manual checks.
- **Risk** — what this could affect; anything to watch in subsequent work.

Exit condition: existing tests pass and the PR is open.
