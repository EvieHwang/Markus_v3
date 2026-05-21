# Constitution

## Standards
Interface:        Apple Human Interface Guidelines
                  developer.apple.com/design/human-interface-guidelines
Accessibility:    WCAG 2.1 AA
                  w3.org/WAI/WCAG21/quickref
Security:         OWASP Top 10
                  owasp.org/www-project-top-ten
API contracts:    OpenAPI Specification
                  spec.openapis.org

Extended (apply when relevant):
API design:       Microsoft REST API Guidelines
AI integration:   OWASP Top 10 for LLMs
Security depth:   OWASP ASVS

Agents follow these without deviation unless the declaration 
explicitly requires otherwise. Deviation must be surfaced as 
a decision, not made silently.

## Architectural principles
- Feature files are the spec. They are never modified during implementation; if they are wrong, fix the document and restart the affected step.
- No Docker for local development unless the project has multi-service dependencies that genuinely require it.
- All deployments run through GitHub Actions, triggered by push to `main`.
- Prefer self-hosted runners (Eviebot) over SSH-based deploy steps.

[Add app-specific principles below as they are decided.]

## Patterns in use
- **Commits:** conventional commits, one per logical unit of work.
- **Frontend stack:** React + TypeScript + Tailwind + shadcn/ui. Vanilla JS is acceptable only for stateless single-page tools.
- **UI aesthetic:** information-dense, 14px base, tight line heights, dark mode as a first-class surface.
- **UX checklist:** apply Nielsen's 10 heuristics as a general sanity-check on any interface; Apple HIG (see Standards) is the authoritative reference for platform decisions.
- **Python service layout:** `pyproject.toml` with a console-script entry point (not `requirements.txt`); deployment plists live in `deploy/` (not `launchd/`).

[Add app-specific patterns below as they are established.]

## Quality gates
- All tests pass.
- `README.md` and `CLAUDE.md` exist and are current.
- `.env.example` lists every key the deploy workflow injects — no drift between the committed example and the actual required secrets.

[Add app-specific gates below as they are established.]

## Testing
Framework: [populated by t2-verify on first use]
Run: `[command — populated by t2-verify on first use]`

## Out of scope
[List what this codebase explicitly does not do. Populated per app.]

## Decision log
| Date | Decision | Rationale |
|------|----------|-----------|
[populated as significant decisions are made]

## Acknowledged risks
*Cross-feature accumulation surface. Each adversarial finding marked `acknowledged` gets one row here so the project never silently forgets that it knowingly took on risk. Severity is the unmitigated severity — an acknowledged HIGH stays HIGH. Populated by `/t3-adversarial` when a finding moves to `acknowledged`.*

| Feature | Finding | Severity | Risk | Rationale | Mitigation |
|---------|---------|----------|------|-----------|------------|
[populated by the adversarial review process]

## Artifact formats

### State file
Location: features/[feature-name]-[number]/state.md
Format:
| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|

Valid status values: pending, in-progress, complete, failed
Notes column captures the commit SHA on completion and the failure reason on failure.
Updated by: t3-generate-dag (initializes), t3-next-step (updates)
