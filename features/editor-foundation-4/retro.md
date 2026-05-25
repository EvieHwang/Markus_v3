# Retro: editor-foundation-4

Captured after `/build` shipped (PR #20, merged), manual device test passed.

---

## What went well

- **Spec converged in one loop.** Requirements ↔ architecture: 1 pass each, both files end with explicit "stable" notes. No churn.
- **Adversarial round 2 confirmed all round-1 findings addressed.** Three MEDIUM findings (F-001 stale anchor on momentum scroll, F-002 opacity-0 not mandated, F-003 no reference mechanism for the live read) — all resolved at the spec level before build started. Zero new findings emerged during build.
- **The F-003 fix worked exactly as designed.** `RawEditorScrollState` (`@MainActor` `ObservableObject` with non-`@Published` property) gave `DocumentView` a clean synchronous read path inside the eye-icon action closure. No Swift 6 concurrency errors, no UIKit reference escape, no surprise re-renders. Worth recognizing as a reusable SwiftUI ↔ UIKit pattern for live UIKit state reads.
- **DAG sizing was right.** 7 tasks / 4 waves, Wave 1 ran 4 truly-independent parallel tasks. No task ended `failed`; no implementation needed redo.
- **Folded-mode commits for single-task waves** kept history readable without losing resumability. Only Wave 1 (multi-task) needed the `in-progress → complete` checkpoint pattern. The distinction is paying off.
- **Build deviations were logged, not absorbed silently.** The three Wave-1 test fixes ended up in `build-deviations.md` rather than as quiet edits to the spec.

## What went badly

- **Three compile-time bugs in the generated spec tests** that `/tests` couldn't catch (it doesn't compile against the actual project):
  1. Missing `import UIKit` — required because the Xcode project enables `MemberImportVisibility`; `@testable import Markus_v3` doesn't transit UIKit member symbols.
  2. Missing `@MainActor` on `RawEditorScrollStateTests` — Swift Testing suite structs are nonisolated by default even when the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  3. `MarkdownDocument(text:)` referenced — that initializer doesn't exist on the walking-skeleton `MarkdownDocument` (only `init()` and `init(file:contentType:)` do).

  All three were honest spec-generator gaps, not implementation mistakes. They added one debug-and-fix round to Wave 1. Costly compared to a quick local typecheck the spec generator could in principle run.

- **T-006 DAG description said "external signature unchanged"** when in reality the constructor gained two new parameters. Cost: ~5 minutes deciding whether to break `DocumentView` (and have it not compile until Wave 4) or to stub. Resolved by stubbing in T-006 and wiring in T-007, but the DAG language was misleading.

- **`RenderedView` deferred-apply is a 30×16ms polling loop.** Pragmatic — meets the design's "implementation choice" latitude and the opacity-0 reveal hides any flake — but smelly: polling in a reactive framework, magic 480 ms budget, silent fall-through to scroll-to-top if the timeout trips. See **Open refinements** below.

- **PR-open path is fragile.** The auto-mode classifier blocks `gh` based on CLAUDE.md's cloud-sandbox note (we were on the local Mac), and the active fine-grained PAT lacks the `repository.defaultBranchRef` read scope that `gh pr create` needs. Build couldn't finish autonomously; user had to open the PR by hand.

## Loop iteration counts vs. spec stability

| Loop | Passes | Outcome |
|------|--------|---------|
| requirements ↔ architecture | 1 each | Clean convergence; both end with "stable" |
| Adversarial | 2 | Round 1: 3 MEDIUM findings (F-001/F-002/F-003). Round 2: 0 new findings, all confirmed addressed. Normal cadence. |
| DAG | 1 | No resizing. 7 tasks / 4 waves as generated. |
| Build → spec rework | 0 | No task ended `failed`; no requirement or design edit happened during build. |

This is what stable-spec-into-build looks like. The one Wave-1 fix round was in the *Xcode-target copy* of the tests, not in spec artifacts.

## Open refinements

Carried forward as follow-up `/patch` work; not blocking but worth landing before the next iOS feature builds on these patterns.

### R-1 — Replace `RenderedView` polling loop with reactive triggers
**Where:** `Markus_v3/Views/RenderedView.swift`, the `.task(id:)` + `applyPendingAnchor()` polling loop introduced in T-007.

**Why:** Four concrete problems with the current code:
1. Polling violates SwiftUI's reactive model (the framework already exposes change signals via `.onChange`, `.onScrollGeometryChange`).
2. The 480 ms budget (30 × 16 ms) is a magic number with no principled basis — adapts to neither device speed nor document length.
3. On timeout, the code silently scrolls to y=0 and clears the pending binding as if successful. The opacity-0 reveal masks this from the user; the AC-3.1 promise is violated and no signal surfaces.
4. `Task.sleep(for:)` doesn't align to SwiftUI layout passes, so the polling can sit between two layouts and miss the frame `contentHeight` was first known.

**Refinement:** Drop the polling task. Apply the anchor whenever either upstream signal updates:
```swift
.onChange(of: contentHeight) { _, _ in applyAnchorIfReady() }
.onChange(of: pendingScrollAnchor) { _, _ in applyAnchorIfReady() }

private func applyAnchorIfReady() {
    guard let anchor = pendingScrollAnchor else { return }
    // Empty-doc shortcut: anchor at top applies without waiting for content
    if anchor.fractionalY == 0 {
        scrollPosition.scrollTo(y: 0)
        pendingScrollAnchor = nil
        return
    }
    guard contentHeight > 0 else { return }
    let scrollable = max(0, contentHeight - viewportHeight)
    scrollPosition.scrollTo(y: CGFloat(anchor.fractionalY) * scrollable)
    pendingScrollAnchor = nil
}
```

Removes the magic number, the polling, and the silent failure path. Behavior is identical when content is ready by first apply (the common case) and strictly better when it isn't.

## Project-level recommendations *(this repo's constitution.md / CLAUDE.md)*

### Add to `constitution.md` → **Patterns in use**

```markdown
- **iOS test target conventions.** Tests in `Markus_v3Tests/` that reference UIKit members must `import UIKit` explicitly — `@testable import Markus_v3` does not transit UIKit symbols under the `MemberImportVisibility` upcoming feature. Tests that construct `@MainActor` types (e.g., `RawEditorScrollState`, anything UITextView-derived) need `@MainActor` on the suite struct, because Swift Testing suite structs are nonisolated by default even with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- **Sendable value types under MainActor default isolation.** `Sendable` structs whose static members or init are called from nonisolated contexts must mark those members `nonisolated` explicitly. See `ScrollAnchor.swift`.
- **Scroll-anchor reveal.** Any iOS view that defers a UIKit `setContentOffset` after layout starts at `opacity 0` and reveals only after the anchor is applied. This is unconditional, not flash-conditional. See `MarkdownTextViewBridge` and `RenderedView`.
- **SwiftUI ↔ UIKit live state reads.** When SwiftUI code needs to read live UIKit state at an event boundary (e.g., the eye-icon read of the raw editor's current scroll position), the reference mechanism is a `@MainActor` `ObservableObject` owned by the SwiftUI parent and written by the `UIViewRepresentable` coordinator. Omit `@Published` on the property so scroll-tick writes don't trigger re-renders. See `RawEditorScrollState.swift`.
```

### Add to `CLAUDE.md` → **Run, test, deps** (iOS section)

```markdown
- New `.swift` files dropped into `Markus_v3/`, `Markus_v3Tests/`, or `Markus_v3UITests/` are auto-discovered (the project uses `PBXFileSystemSynchronizedRootGroup`). No `project.pbxproj` edits are required when adding source or test files.
```

### Qualify `CLAUDE.md` → **Development environment** cloud-sandbox note

```markdown
- The "GitHub access is via the GitHub MCP server, `gh` CLI is not available" note applies to **cloud sandbox sessions only**. On the local Eviebot Mac, `gh` is available — but the auto-mode classifier reads CLAUDE.md verbatim and may block `gh` calls. When working locally, allowlist `gh pr create` in `.claude/settings.local.json` and ensure the active PAT has `pull-requests: write` + `metadata: read` scopes for the repo. The fine-grained PAT currently configured does not satisfy `metadata: read`, which `gh pr create` needs to look up the default branch.
```

## Template-level recommendations *(propagate to the framework template)*

### `/tests` skill

When generating Swift Testing files for an iOS target:
- Inspect the project's `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY` build settings. If MainActor default isolation is on, add `@MainActor` to any suite struct that constructs MainActor-isolated types. If `MemberImportVisibility` is on, add explicit `import` for any framework whose members the test references (UIKit, SwiftUI, etc.), even when `@testable import <Module>` already imports them transitively.
- Before referencing an initializer on an existing type, grep the type definition for available initializers. If the referenced one doesn't exist (e.g., assuming a convenience `init(text:)` when only `init(file:contentType:)` does), either use an existing initializer or flag the missing constructor in `verify.md` as a setup helper to add.

### `/dag` skill

When a task description says "external signature unchanged" but new parameters are being added at the call boundary, rephrase as **"signature additively extended with `<new params>`"** or split into two tasks ("add new params with safe defaults" → "wire callers"). The current ambiguous language ("unchanged" when meaning "compatible") cost time in T-006.

### `/build` skill

Clarify the per-wave gate: **"tests pass after each task"** should explicitly cover the case where Wave N intentionally stubs functionality that Wave N+1 wires up. Stubs are acceptable as long as the existing test suite and a smoke test (e.g., `testAppLaunchesToDocumentBrowser`) keep passing.

### `/next` skill

First-line debug heuristic when a test file fails to compile: check whether the spec generator referenced symbols that don't exist in the project *before* assuming the implementation is wrong. The build doc says "tests are the source of truth," but a spec generator can produce broken tests; distinguish "test asserts wrong behavior" from "test won't compile because it references a phantom API."

### `/spec` (orchestrator)

When the deployment target is iOS / Swift 6+, the orchestrator should add a "concurrency annotations checklist" stage between `/architecture` and `/tests`: for each new type, the designer marks it as MainActor, Sendable, or nonisolated. This would have surfaced the `ScrollAnchor` `nonisolated` annotation and the `RawEditorScrollStateTests` `@MainActor` requirement at spec time, not at build time.

---

## Summary

The build pipeline did its job: tight spec, no rework, fast convergence. The friction surfaced where the framework crosses a project boundary — the spec generator can't typecheck against the live project, and the cloud-sandbox PR-open assumptions don't survive on a local Mac. Both are addressable with the recommendations above. Of the implementation choices made during build, only the `RenderedView` polling loop is worth refactoring as a follow-up — captured as R-1 above.
