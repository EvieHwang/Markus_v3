# Build DAG: walking-skeleton-1

*Walking skeleton — breadth across all 7 seams. 10 tasks across 5 waves. Each task is atomic and commits independently.*

Drives `/t3-build`. Wave N starts only after Wave N-1 completes. Tasks within a wave run in parallel.

---

## Wave 1 — Project bootstrap

### T-001 — Xcode project + dependency + manifest
**Description:** Create the Xcode project (SwiftUI App, iOS 18 minimum, Swift 6 strict concurrency on). Configure Info.plist with `.md` and `.markdown` document types conforming to `public.plain-text` (UTI `net.daringfireball.markdown`). Add a blank `LaunchScreen` storyboard. Add `PrivacyInfo.xcprivacy` enumerating required-reason API categories: `FileTimestamp` C617.1, `UserDefaults` CA92.1, `DiskSpace` E174.1. Add MarkdownUI SwiftPM dependency pinned `.upToNextMinor(from: "2.4.0")` and commit `Package.resolved`.
**Inputs:** design.md (project layout, dependencies, Privacy Manifest spec, UTType decl).
**Outputs:** `Markus_v3.xcodeproj/`, `Markus_v3/App/Info.plist`, `Markus_v3/App/PrivacyInfo.xcprivacy`, `Package.resolved`, empty `Markus_v3App.swift` stub that compiles.
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** `xcodebuild build -scheme Markus_v3 -destination 'platform=iOS Simulator,name=iPhone 15'` succeeds with an empty SwiftUI shell. MarkdownUI resolves. Privacy Manifest validates.

---

## Wave 2 — Models & error types (parallel)

### T-002 — Small types: DocumentMode, DocumentError, ActiveAlert
**Description:** Three small types in their own files:
- `enum DocumentMode { case rendered, raw }`.
- `enum DocumentError: Error { case invalidEncoding, saveFailed(underlying: Error), fileMissing, iCloudDownloadFailed }`.
- `enum ActiveAlert: Identifiable { case saveFailed(DocumentError), invalidEncoding, iCloudDownloadFailed }` with stable `id` per case.
**Inputs:** design.md components #3, #8.
**Outputs:** `Markus_v3/Models/DocumentMode.swift`, `Markus_v3/Documents/DocumentError.swift`, `Markus_v3/Documents/ActiveAlert.swift`.
**Dependencies:** T-001.
**Wave:** 2.
**Acceptance:** files compile under Swift 6 strict concurrency. Unit tests for each type pass (round-trip cases, `Identifiable` IDs are stable).

### T-003 — MarkdownDocument
**Description:** Implement `final class MarkdownDocument: ReferenceFileDocument` per design.md component #2. UTF-8 decode in `init(configuration:)`; throws `DocumentError.invalidEncoding` on failure. Capture `initialByteSize` from `configuration.file.regularFileContents?.count`. `snapshot(contentType:)` returns `text`; `fileWrapper(snapshot:configuration:)` writes UTF-8. `markDirty()` registers a no-op undo against the host `UndoManager`.
**Inputs:** design.md component #2, DocumentError from T-002.
**Outputs:** `Markus_v3/Documents/MarkdownDocument.swift`.
**Dependencies:** T-001, T-002.
**Wave:** 2.
**Acceptance:** unit tests pass: round-trip read/write preserves UTF-8 content; invalid UTF-8 throws `invalidEncoding`; `initialByteSize` matches input bytes; `markDirty()` registers an undo action.

---

## Wave 3 — Behavior & glue (parallel)

### T-004 — AutosaveCoordinator
**Description:** `@Observable @MainActor final class AutosaveCoordinator` per design.md component #7. `textChanged()` cancels in-flight save Task and schedules a new one with `Task.sleep(for: .milliseconds(500))` + `Task.checkCancellation`. On idle, calls `document.markDirty()` and `setActionIsDiscardable(true)` on the undo action.
**Inputs:** design.md component #7, MarkdownDocument from T-003.
**Outputs:** `Markus_v3/Models/AutosaveCoordinator.swift`.
**Dependencies:** T-003.
**Wave:** 3.
**Acceptance:** unit tests pass: rapid `textChanged()` calls produce exactly one `markDirty()` after 500 ms idle; cancellation works correctly across overlapping calls.

### T-005 — SaveStatusObserver
**Description:** `@Observable @MainActor final class SaveStatusObserver` per design.md component #11. Global subscription to `UIDocument.stateChangedNotification` (`object: nil`). Publishes `lastSaveError: DocumentError?` and `isDownloadingFromiCloud: Bool` based on observed state transitions. Notification handler hops to `@MainActor`. `deinit` removes the observer.
**Inputs:** design.md component #11, DocumentError from T-002.
**Outputs:** `Markus_v3/Documents/SaveStatusObserver.swift`.
**Dependencies:** T-002.
**Wave:** 3.
**Acceptance:** unit tests pass: posting a synthetic `UIDocument.stateChangedNotification` with `.savingError` sets `lastSaveError`; with `.editingDisabled` sets `isDownloadingFromiCloud`; lifecycle tests confirm clean teardown.

### T-006 — ToastModifier
**Description:** SwiftUI `ViewModifier` per design.md component #8: shows transient bottom-aligned `Text` for 2 s after the host's `toast` state is set; auto-clears via a `Task` with `Task.sleep(for: .seconds(2))`. Text uses `.accessibilityHidden(true)` (VoiceOver users receive the announcement separately per AC-A11Y-3).
**Inputs:** design.md component #8.
**Outputs:** `Markus_v3/Views/ToastModifier.swift`.
**Dependencies:** T-001.
**Wave:** 3.
**Acceptance:** snapshot/unit test confirms toast appears, auto-clears after 2 s, and the toast `Text` has `accessibilityElementsHidden`.

---

## Wave 4 — Leaf views (parallel)

### T-007 — RenderedView
**Description:** SwiftUI view per design.md component #5: wraps MarkdownUI's `Markdown` in a `ScrollView`. Full-area `.contentShape(Rectangle()).onTapGesture` switches mode to `.raw` (binding from `DocumentView`). `OpenURLAction` environment override returns `.discarded` and also flips to `.raw`. `.accessibilityAction(named: "Edit")` switches mode.
**Inputs:** design.md component #5, DocumentMode from T-002.
**Outputs:** `Markus_v3/Views/RenderedView.swift`.
**Dependencies:** T-001, T-002.
**Wave:** 4.
**Acceptance:** view compiles; UI test confirms tap on rendered area triggers mode switch; tap on link triggers mode switch (no link follow); `accessibilityAction(named: "Edit")` is discoverable by `XCUIElement.accessibilityCustomActions`.

### T-008 — RawEditorView
**Description:** SwiftUI view per design.md component #6: `TextEditor` bound to `document.text` with `.font(.system(.body, design: .monospaced))`. `.onChange(of: text)` notifies the autosave coordinator and calls `document.markDirty()`.
**Inputs:** design.md component #6, MarkdownDocument from T-003, AutosaveCoordinator from T-004.
**Outputs:** `Markus_v3/Views/RawEditorView.swift`.
**Dependencies:** T-003, T-004.
**Wave:** 4.
**Acceptance:** view compiles; UI test confirms text input updates `document.text`, dirties the document, and triggers the autosave debouncer.

### T-009 — DocumentLoadingView
**Description:** Tiny SwiftUI view per design.md component #12: centered `ProgressView` with label "Downloading…".
**Inputs:** design.md component #12.
**Outputs:** `Markus_v3/Views/DocumentLoadingView.swift`.
**Dependencies:** T-001.
**Wave:** 4.
**Acceptance:** view compiles; snapshot test confirms the spinner + label render. Build-agent note: if `DocumentGroup` natively shows a download indicator before document init, the view may be unreachable — that's acceptable, leave it in as a safety net.

---

## Wave 5 — Integration

### T-010 — DocumentView + Markus_v3App
**Description:** Top-level integration per design.md components #1 and #4. `DocumentView` switches between `RenderedView`, `RawEditorView`, and `DocumentLoadingView` based on mode and `SaveStatusObserver.isDownloadingFromiCloud`. Computes initial mode in `.onAppear` from `document.initialByteSize` (≥ 500 KB → `.raw`, else `.rendered`). Toolbar eye-icon (only in raw mode) with `.accessibilityLabel("Show rendered")`. Navigation bar title is the filename without extension. `.alert(item:)` handles `ActiveAlert.saveFailed` with two actions: "Copy contents to clipboard" (writes pasteboard → `UIAccessibility.post(notification: .announcement, argument: "Copied")` → triggers toast) and "Dismiss". Observes `SaveStatusObserver.lastSaveError` to drive the alert. `.onChange(of: scenePhase)` triggers a save on `.background`. `Markus_v3App` wraps everything in a `DocumentGroup(newDocument: { MarkdownDocument() }, editor: DocumentView.init)` and instantiates `SaveStatusObserver` at app scope.
**Inputs:** design.md components #1, #4, #8 (Copy action). All Wave 4 outputs. `AutosaveCoordinator`, `SaveStatusObserver`, `ToastModifier`.
**Outputs:** `Markus_v3/Views/DocumentView.swift`, fully-implemented `Markus_v3/App/Markus_v3App.swift` (replaces the Wave 1 stub).
**Dependencies:** T-005, T-006, T-007, T-008, T-009.
**Wave:** 5.
**Acceptance:** end-to-end UI test passes: launch → document browser → open a sample `.md` file → see rendered → tap → enter raw → edit → eye icon → return to rendered with edits visible → close + reopen → edits persist on disk at original location, no app-container copy.

---

## Sizing check

10 tasks, 5 waves, ~1 file per task (T-001 and T-010 touch a few). Wave 4 has the widest fan-out (3 parallel views). No new framework or deploy path is introduced; the build agent's working window should accommodate this comfortably.

**Walking-skeleton breadth justification:** the feature touches all 7 Shape seams by design — this is the point of the skeleton, not a sign of mis-sizing. Each individual task is shallow (most files <100 lines).

---

## Next step

After this DAG is committed, run `/t3-test-coach` to generate the XCTest suite tagged to these task IDs. Then `/t3-build` to orchestrate the build wave-by-wave.
