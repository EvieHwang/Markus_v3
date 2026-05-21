# Tiered Build Framework

A template repository for building software with Claude Code. Three tiers of increasingly structured workflow — small bounded changes up to full system builds — implemented as slash commands that produce specification artifacts and then build against them.

## This repo is a template

You clone or fork it; the clone becomes the app you're building. Skill commands in `.claude/commands/` produce specs and code into the cloned repo. Several files ship with placeholders that get filled in or replaced as you use the template:

- **This `README.md`** — describes the framework; replace it with one describing your app.
- `CLAUDE.md` — `# [Project Name]` and the operational sections (run / test / deploy).
- `declaration.md` — what / why / for whom / out of scope.
- `constitution.md`'s `## Testing` section — framework and run command, populated by `/t2-verify` or `/t3-test-coach` on first use.
- `features/` — empty; folders are created per feature as skills run.

The framework template itself has no executable code and no tests; quality gates in `constitution.md` apply to copied apps, not to this template.

## Getting started

Open the cloned repo in Claude Code (the cloud sandbox is the default development surface) and:

1. Replace this `README.md` with a stub for your app (just `# AppName` and a one-line description is fine to start). Flesh it out as the app takes shape — typically after `/declaration` runs, the README can quote from `declaration.md`. Do not delete `README.md` without replacing it; `constitution.md`'s quality gate requires it to exist.
2. Edit `CLAUDE.md` to set the project name, description, run/test commands, and deployment target.
3. Run `/declaration` to populate `declaration.md`.
4. Pick a tier and run its starting command (`/t1-build`, `/t2-intent`, or `/t3-feature-declaration`).

See [`user-guide.md`](user-guide.md) for the full reference, including how the requirements ↔ architecture loop converges, how adversarial findings flow back through the loop, and how the DAG-driven build works across cloud-sandbox sessions.

## Development environment

Designed for Claude Code in the cloud sandbox attached to this GitHub repo. The sandbox provisions a working branch per session; skills commit to it and open PRs against `main` when work is complete. Local Claude Code works too — the only sandbox-specific accommodation is that user-global preferences are carried inside `CLAUDE.md` rather than `~/.claude/CLAUDE.md` (which does not exist in the sandbox).
