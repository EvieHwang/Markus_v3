# Markus_v3

Simple Markdown app for iOS

## Repo map
- `declaration.md` — what this project is and why it exists
- `constitution.md` — principles, standards, decisions, and project conventions (testing framework, state-file format, etc.)
- `features/[feature-name]-[number]/` — per-feature artifacts, produced by tier-specific skills at runtime

Before any build action: read `constitution.md`.
Before any architectural decision: read `constitution.md` and `declaration.md`.

## Precedent repos to consult before building
*Other repos that encode patterns this project inherits or replaces. List them here so a fresh build agent knows what to read for ground truth before assuming a precedent.*

- `<owner>/<repo>` — what pattern it provides and how this project relates. [Replace or delete per project. Delete the section entirely if there are no precedent repos.]

If access to a listed repo is scoped out of the current session, ask the user before guessing — earlier specs from precedent repos are not always current and may have been superseded.

## Build flow note
Spec tests in `features/<feature>/tests/` are written **before** implementation and intentionally fail (ImportError or pytest.skip equivalent) until each tagged task is built. When picking up a task, the first action is to run the tests for that task and confirm they're failing in the expected way (right module, right reason). Only then write code. A test that passes before its task has been implemented is a signal that the test is wrong or tagged to the wrong task — fix it before continuing.

## Development environment
Development runs in Claude Code cloud sandboxes attached to this GitHub repo.

- The container is ephemeral and re-cloned each session. Anything not committed and pushed is lost.
- No `~/.claude/CLAUDE.md` exists in the sandbox — user-global preferences are carried at the bottom of this file.
- GitHub access is via the GitHub MCP server (tools prefixed `mcp__github__`). The `gh` CLI is not available.
- Development branch pattern: `claude/<short-task-name>-<suffix>`. Open a PR to `main` when work is complete. Always assign the PR to the repo owner. 

## Run, test, deps

### iOS app (Xcode + Swift)
- Install: open `Markus_v3.xcodeproj` (or `.xcworkspace`) in Xcode. Swift Package Manager (SwiftPM) resolves dependencies automatically on open. No separate install command.
- Run locally: in Xcode, press Run (⌘R) to launch in the chosen simulator or device.
- Tests: in Xcode, press Test (⌘U). Or from the command line:
  `xcodebuild test -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 15'`
- Package manager / lockfile: Swift Package Manager (`Package.resolved` — committed automatically by Xcode).


## Deployment target

### Apple platform (iOS via Xcode → App Store / TestFlight)
- Specs live in this repo; build runs in Xcode locally
- No CI deploy path; release is a manual Xcode build and submission
- Signing: managed via Xcode (automatic signing with the Apple Developer team, or manual provisioning profiles as configured in the project)
- "Deploy success" for an Apple build means the archive builds, signs, and uploads cleanly. There is no live-service health check; treat App Store / TestFlight acceptance as the equivalent gate.

## Secrets
- Canonical source: **GitHub Actions Secrets at the Eve-Hwang org level.**
- Commit a `.env.example` listing every required key with no values.
- Never commit `.env` or any file containing secret values.
- On deploy, the workflow injects secrets into the chosen target (writes `.env` on Eviebot, sets env vars on AWS, configures the Xcode build). Anything on the target is an artifact of deployment, not a source of truth — if the target is rebuilt, the next deploy recreates it.
- Adding a new secret: add to Eve-Hwang org secrets → add the key to `.env.example` → add the inject step to the deploy workflow.

---

## User globals — Evie Hwang
*Carried in this file because Claude Code cloud sandboxes have no `~/.claude/CLAUDE.md`. These coordinates apply to every project, not just this one.*

### GitHub
- `EvieHwang` (personal) — used for public AWS-hosted apps
- `Eve-Hwang` (organization) — used for private Eviebot-hosted apps
- Self-hosted runner: **Eviebot** (org-level, Default runner group)

### AWS
- Account: `070840362692` (user: `eve-hwang`)
- Default region: `us-east-1`

### Eviebot — runtime server
- Mac mini, headless, always-on. macOS — use `launchd`, not systemd.
- Runner user: `eviebot`. All paths under `/Users/eviebot/`.
- Services live at `/Users/eviebot/services/<repo-name>/` with a venv at `.venv/`.
- Use `python3.11` (Homebrew) when 3.10+ is needed; otherwise confirm `python3 --version` before assuming.

### Gateway integration
- Gateway repo: `eviebot-mcp-gateway`, running on port 8080.
- To add a new MCP backend, follow the gateway repo's `CLAUDE.md` exactly. Port allocation, auth patterns (A/B), and the `gateway.py` block are defined there — read it first.
- Check existing service labels with `launchctl list | grep eviebot` before choosing a new one.
