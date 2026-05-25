# Build Deviations: editor-foundation-4

Living record of departures from the committed spec made during the build, per `/build` policy. Each entry will be considered a candidate adversarial finding on the next `/adversarial` pass.

---

## Test fixes (Wave 1) — Markus_v3Tests/EditorFoundationTests.swift

The spec test file at `features/editor-foundation-4/tests/EditorFoundationTests.swift` was copied to `Markus_v3Tests/EditorFoundationTests.swift` to enter the Xcode test target. Three compile-time fixes were applied to the Xcode-target copy; the spec file is unchanged.

### Fix 1 — Add `import UIKit`
- **Original:** `import Testing` / `import Foundation` / `@testable import Markus_v3`
- **Why wrong:** `SmartQuoteSuppressionTests` references `UITextView` properties (`smartQuotesType`, `smartDashesType`, `spellCheckingType`, `autocorrectionType`) which require UIKit. With the `MemberImportVisibility` upcoming feature enabled in this project, transitive import of UIKit via `@testable import Markus_v3` does not surface UIKit member symbols.
- **Corrected:** added `import UIKit` at the top.

### Fix 2 — `@MainActor` on `RawEditorScrollStateTests`
- **Original:** `@Suite("RawEditorScrollState — write/read path") struct RawEditorScrollStateTests {`
- **Why wrong:** `RawEditorScrollState` is a `@MainActor final class` by design (design.md §3). Tests that instantiate it or read/write `currentFractionalY` must also be main-actor isolated. Without the annotation the tests are nonisolated and fail to compile.
- **Corrected:** added `@MainActor` annotation to the suite.

### Fix 3 — `UITextViewMigrationTests` cannot use `MarkdownDocument(text:)`
- **Original:** `let doc = MarkdownDocument(text: source)` (four call sites in `UITextViewMigrationTests`).
- **Why wrong:** `MarkdownDocument` (walking-skeleton-1) exposes no `init(text:)`. Its public initializers are `init()` and `init(file:contentType:)`. The spec generator assumed a convenience initializer that does not exist in this codebase.
- **Corrected:** Added a private `makeDoc(_:)` helper that wraps the source string in a `FileWrapper` and constructs the document through the supported `init(file:contentType:)`. The behavioral assertions (text round-trip, empty file, Unicode preservation) are unchanged.

### Why these are test fixes, not requirement/design changes
None of the three fixes alter the behavior under test. Each is a compilation-level adaptation to the actual project surface (Swift 6 approachable concurrency, the `MemberImportVisibility` upcoming feature, and the walking-skeleton `MarkdownDocument` API). The spec file in `features/editor-foundation-4/tests/` is left as-is so future spec regeneration starts from a clean source.
