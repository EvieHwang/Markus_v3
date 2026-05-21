---
description: Coached repository setup after cloning the Evie tiered-build template. Fills CLAUDE.md (project name, one-liner, run/test/deps block, deployment target), replaces the template README with an app stub, and commits — stopping before `/declaration`.
---

This command runs once per freshly-cloned template. It does not touch `declaration.md` or `constitution.md`; `/declaration` is the next step after this, and constitution edits happen as the project develops (see `user-guide.md` §"New project setup").

Before starting, read `CLAUDE.md`, `README.md`, and `user-guide.md` §"New project setup". If `CLAUDE.md` no longer contains `# [Project Name]` (the placeholder), the repo has already been set up — confirm with the user whether to re-run before making any edits.

Verify the working branch matches `claude/<short-task-name>-<suffix>` (the sandbox provisions it). If not, surface the discrepancy and stop.

Phase 1 — coached conversation
Ask in this order; one topic per turn, do not batch:

1. **Project name** — short, human-readable. Used to replace `# [Project Name]` in CLAUDE.md and as the `#` heading in the new README.
2. **One-line description** — what the app is, in a sentence. Becomes the README subtitle and a comment line in CLAUDE.md.
3. **Stack / runtime** — pick the run/test/deps block. Offer the common shapes (Node + pnpm/npm, Python + pyproject, Swift/Xcode, static site, "skip — fill later"). If the user names a stack not on the list, accept it and synthesize a reasonable block.
4. **Deployment target** — Eviebot (self-hosted Mac mini, launchd), AWS (us-east-1, account 070840362692), Apple/Xcode (App Store / TestFlight), or "none yet". Pull the canonical coordinates from CLAUDE.md's `## User globals` block when writing Eviebot/AWS targets.

Hold answers at the level the template expects — names and commands, not architecture. If the user starts describing features or behavior, redirect: that belongs in `/declaration`.

Confirm the four answers back to the user before writing anything.

Phase 2 — file edits

**`README.md`** — overwrite with:

```
# <Project name>

<One-line description>
```

That's the stub the framework expects; it will get fleshed out after `/declaration` runs (the README can then quote from `declaration.md`). Do not delete README.md without replacing it — `constitution.md`'s quality gate requires it to exist.

**`CLAUDE.md`** — make these edits, preserving the rest of the file verbatim (especially the `## User globals — Evie Hwang` section at the bottom):
- Replace `# [Project Name]` with `# <Project name>`.
- Replace the bracketed one-line-description placeholder under it with the user's one-liner.
- Under `## Run, test, deps`: replace the "Pick the block that matches..." instruction with a single uncommented block for the chosen stack. Include commands for install, run/dev, and test. If the user picked "skip", leave a single-line TODO comment instead of a block.
- Under `## Deployment target`: replace the "Pick one" instruction with a single uncommented block describing the chosen target. For Eviebot, reference `/Users/eviebot/services/<repo-name>/` and `launchd`; for AWS, reference account `070840362692`, region `us-east-1`, and that secrets come from Eve-Hwang org Actions secrets; for Apple/Xcode, reference Xcode build + signing. For "none yet", leave a single-line TODO.

Do not modify `declaration.md`, `constitution.md`, or anything under `features/`.

Present the diff of the two changed files back to the user. Revise until confirmed.

Phase 3 — commit

Commit `README.md` and `CLAUDE.md` together to the current branch with a conventional-commit message:

```
chore: initialize <project name> from template

- README stub
- CLAUDE.md: project name, one-liner, <stack> run/test, <target> deploy
```

Do not push and do not open a PR — `/declaration` will run next on the same branch, and the PR is opened later once setup + declaration are both in.

Exit condition
- `README.md` is an app stub (name + one-liner), no template framework text remains.
- `CLAUDE.md` has the project name, one-line description, an uncommented run/test/deps block, and an uncommented deployment-target block. `## User globals` is preserved untouched.
- Both files committed on the current branch.
- Tell the user the next step is `/declaration`.
