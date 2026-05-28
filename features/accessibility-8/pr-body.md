# PR: feat(accessibility-8): VoiceOver, Dynamic Type, and link-behavior accessibility pass

**Open URL:** https://github.com/EvieHwang/Markus_v3/pull/new/claude/accessibility-8-build

**Title:** `feat(accessibility-8): VoiceOver, Dynamic Type, and link-behavior accessibility pass`

**Assignee:** EvieHwang

---

## Feature declaration

Link to [`features/accessibility-8/declaration.md`](features/accessibility-8/declaration.md). Five focused accessibility fixes across four UI surfaces (rendered view, raw editor, mode switcher, conflict/lifecycle UI) closing concrete gaps against WCAG 2.1 AA and Apple HIG: restored standard link behavior, heading rotor traits, live Dynamic Type in the raw editor, accessible names/hints on conflict & deletion controls, and VoiceOver mode-switch announcements.

## Requirements

Link to [`features/accessibility-8/requirements.md`](features/accessibility-8/requirements.md). Stable. 5 concerns, each with acceptance criteria. Revision 1 incorporated adversarial round-1 fixes (heading rotor behavioral verification, post-banner-dismissal focus, context-specific Dismiss label, raw editor 1pt font floor).

## Design

Link to [`features/accessibility-8/design.md`](features/accessibility-8/design.md). Stable. Five surgical changes:
1. `RenderedView.swift` — remove `OpenURLAction` override; `simulateLinkTap` becomes a no-op
2. `MarkdownThemeFactory.swift` — add `.accessibilityAddTraits(.isHeader)` to all six heading builders
3. `MarkdownEditorTextView.swift` — register `UIContentSizeCategory.didChangeNotification` observer; remove in `deinit`; 1pt floor in `configureAppearance`
4. `DetectorSurfaces.swift` — `.accessibilityLabel` on all five buttons, `.accessibilityHint` on Discard Mine, context-specific Dismiss label, post `.layoutChanged` after both banner-dismissal paths
5. `DocumentView.swift` — `UIAccessibility.post(.announcement, ...)` at each user-triggered mode-switch call site (no `.onChange` observer)

All changes are additive to the accessibility tree or replace a blocking override with platform-default behavior. No visual rendering changes.

## Adversarial review

Link to [`features/accessibility-8/adversarial-review.md`](features/accessibility-8/adversarial-review.md). 5 findings, all addressed and verified in round 1:

| Finding | Severity | Status |
|---------|----------|--------|
| F-001 | HIGH | addressed — announcements posted at triggering call sites, no `.onChange` observer |
| F-002 | HIGH | addressed — AC-2.2/AC-2.5 require behavioral XCUITest verification + design fallback |
| F-003 | MEDIUM | addressed — both banner-dismissal paths post `.layoutChanged` |
| F-004 | LOW | addressed — context-specific Dismiss label ("Dismiss file deleted notice") |
| F-005 | LOW | addressed — raw editor font has unconditional 1pt floor |

No `acknowledged` or `deferred` findings.

## Build summary

DAG completion (see [`features/accessibility-8/state.md`](features/accessibility-8/state.md)):

| Wave | Task | Status | Commit |
|------|------|--------|--------|
| 1 | T-001 RenderedView link behavior + test corrections | complete | `aed08ac` |
| 2 | T-002 MarkdownThemeFactory heading traits | complete | `02648ff` |
| 2 | T-003 MarkdownEditorTextView Dynamic Type observer + 1pt floor | complete | `02648ff` |
| 2 | T-004 DetectorSurfaces accessibility labels + `.layoutChanged` | complete | `02648ff` |
| 3 | T-005 DocumentView mode-switch announcements | complete | `0c8f5ff` |

**Final test results:** all unit tests pass (`Markus_v3Tests`). UI tests pass on retry — three test runs surfaced different transient flake patterns (`testSecondCollisionDoesNotStackSheet`, `testInvalidUtf8UsesAlertNotConflictSheet`, `test_backFromOpenedFile_returnsToBrowser`, `testBackThenRelaunchStillResumes`, `testEdgeSwipeBackReturnsToBrowser`), all of which passed on isolated re-run with no code change. None of those tests touch the accessibility surfaces modified here. Treating as pre-existing simulator flakiness; no functional regression.

## Risk

- **MarkdownUI trait propagation** — the heading `.isHeader` trait is applied to `configuration.label` per design. If MarkdownUI's internal layout marks the container as `accessibilityElement(children: .contain)`, the trait may land on the container rather than the leaf VoiceOver focuses. The design includes a fallback (wrap in `.accessibilityElement(children: .combine)`) but it has not been needed; on-device VoiceOver-rotor verification is required to confirm heading navigation works (AC-2.2 / AC-2.5 manual step).
- **VoiceOver simulator coverage** — several ACs (AC-1.2, AC-2.2, AC-3.4, AC-4.4, AC-4.9, AC-5.1/5.2) are intrinsically unautomatable in XCUITest (VoiceOver gestures, hint readability, `UIAccessibility.post` interception). The verify.md lists each as a manual-verification item; do a one-time VoiceOver pass on device before next release.
- **Existing UI-test flake** — five different UI tests intermittently failed across the build runs; none related to this feature. Worth a dedicated stabilization pass since they make the green-light signal noisy.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
