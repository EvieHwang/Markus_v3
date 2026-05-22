# Design: walking-skeleton-1

*Walking skeleton — first feature. Architecture deliberately minimal; later Roadmap features will deepen each seam.*

## Ground-truth check (resolved before drafting)

- **Precedent repo:** none consulted. User has a prior prototype but it does not need to seed this design.
- **Xcode/SDK:** Xcode 26 (iOS 26 SDK) — mandatory for App Store submissions starting April 28, 2026.
- **Deployment target:** iOS 18 minimum (broad reach + modern SwiftUI primitives without locking out users still on iOS 18/19).
- **Concurrency:** Swift 6 strict concurrency on by default; everything in this design is `@MainActor` unless explicitly otherwise.
- **Test invocation:** open the repo in Xcode and run tests in-IDE (⌘U). No CLI/CI test path is in scope for this feature. (Constitution.md still references `xcodebuild test`; that command remains correct if needed but is not the canonical workflow.)
- **Deploy surface:** none — Apple platform deploy is manual Xcode build/sign/upload; no GitHub Actions workflow in this feature.
- **Pattern reuse from constitution.md:** none. Constitution registers Python and React patterns only; this is the first iOS surface in the repo, so nothing in this design is marked `Reuses pattern:`. The next iOS feature can begin citing patterns this feature establishes.

## High-level shape

A SwiftUI document-based app. The app's root scene is a `DocumentGroup` configured for the markdown UTType, which gives us the system document browser for free (AC-1.1, AC-1.3) and handles security-scoped open/save in-place (AC-2.4, AC-6.3) without any custom file-management code.

The opened document is a `ReferenceFileDocument` so we can drive change-tracking through the system `UndoManager` (the standard SwiftUI hook for "this document is dirty"). The document holds raw markdown text.

The document view is a single SwiftUI `View` that flips between two child views based on a local `@State` mode enum. There is no navigation stack — mode switching is a view swap inside one screen, matching the kickoff doc's "no chrome that competes with the document."

## Components

### 1. App entry — `Markus_v3App.swift`
- A SwiftUI `App` whose body is a single `DocumentGroup(newDocument:editor:)` over `MarkdownDocument` (the reference file document) and `DocumentView` (the editor view).
- `.scenePhase` observed to trigger a final save on `.background` transitions (AC-4.4, EC-6).
- No splash, no launch-screen logic beyond the standard `LaunchScreen` storyboard (which is blank per AC-1.2).

### 2. Markdown document — `MarkdownDocument.swift`
- `final class MarkdownDocument: ReferenceFileDocument`.
- `readableContentTypes = [UTType.markdown, UTType("net.daringfireball.markdown")!]` covering `.md` and `.markdown` extensions (AC-2.1, EC-5).
- Holds `@Published var text: String` for the raw source.
- Holds `let initialByteSize: Int` — the size of the file as read; used by `DocumentView` to choose the initial mode per EC-2 (≥ 500 KB → raw mode by default).
- `init(configuration:)` decodes the file's bytes as UTF-8; on decode failure, throws a non-fatal `DocumentError.invalidEncoding` which the host surfaces with an alert and dismisses (EC-4). Captures `configuration.file.regularFileContents?.count` into `initialByteSize`.
- `snapshot(contentType:)` returns the current `text`; `fileWrapper(snapshot:configuration:)` writes UTF-8 bytes.
- A `markDirty()` helper registers a no-op undo against the host's `UndoManager` — this is how SwiftUI's DocumentGroup learns the document is dirty and schedules a save.

### 3. Document mode — `DocumentMode.swift`
- `enum DocumentMode { case rendered, raw }`. Local view state; never persisted (AC-5.4).

### 4. Document view — `DocumentView.swift`
- The top-level editor view bound to a `MarkdownDocument`.
- `@State private var mode: DocumentMode` — initial value computed in `.onAppear` from `document.initialByteSize`: ≥ 500 KB → `.raw`, otherwise `.rendered` (AC-2.2, EC-2 *addresses adversarial F-004*). The 500 KB threshold is a single constant `private static let largeFileByteThreshold = 500 * 1024`.
- `@State private var hasUnsavedChanges = false` (drives the autosave debouncer).
- `@State private var activeAlert: ActiveAlert?` — drives the save-failure alert (see component #8).
- Body switches between `RenderedView`, `RawEditorView`, and `DocumentLoadingView` (see component #12) based on `mode` and the document's load state.
- Navigation bar title is the document's filename without extension (AC-2.3), pulled from the host `UIDocument.fileURL` via SwiftUI's `DocumentConfiguration` environment.
- Toolbar item (only when `mode == .raw`): eye-icon button labeled "Show rendered" that sets `mode = .rendered`. The label is set via `.accessibilityLabel("Show rendered")` (AC-A11Y-1).
- On `mode` change to `.rendered`: trigger a save immediately (AC-5.2).
- `.onChange(of: scenePhase)` — on `.background`, trigger a save (AC-4.4).
- Observes `SaveStatusObserver` (component #11) for save failures; on a failure event, sets `activeAlert = .saveFailed(...)`.

### 5. Rendered view — `RenderedView.swift`
- Wraps a `Markdown` view from the **MarkdownUI** Swift package (see Dependencies). MarkdownUI renders GitHub Flavored Markdown natively in SwiftUI: CommonMark + tables + task lists + strikethrough + autolinks (AC-2.1, EC-3).
- Wrapped in a `ScrollView`.
- A full-area `.contentShape(Rectangle()).onTapGesture { mode = .raw }` provides tap-to-edit (AC-3.1).
- An `OpenURLAction` environment override intercepts link taps: returns `.discarded` and sets `mode = .raw` (AC-3.3). Long-press link handling is **not implemented** in the skeleton (out of scope).
- `.accessibilityAction(named: "Edit") { mode = .raw }` (AC-A11Y-2).
- Empty source produces an empty rendered view (AC-2.5).

### 6. Raw editor view — `RawEditorView.swift`
- A SwiftUI `TextEditor` bound to `document.text`.
- `.font(.system(.body, design: .monospaced))` (AC-4.1).
- On every text change: marks the document dirty via `document.markDirty()` and notifies the autosave coordinator.
- No tuning of autocorrect / smart quotes / list continuation / shortcuts in this feature — default UIKit `UITextView` behavior (AC-4.6, deferred items to Roadmap #6).
- TextEditor naturally requires a tap to gain focus; this fulfills AC-3.4 (the first tap was the mode switch; the second tap places the cursor).

### 7. Autosave coordinator — `AutosaveCoordinator.swift`
- `@Observable final class AutosaveCoordinator`.
- Exposes `func textChanged()`. Each call cancels any in-flight save task and schedules a new one after 500 ms idle (AC-4.4 typing-pause).
- The save action is to call `document.markDirty()` again at idle, then ask the `UndoManager` to `setActionIsDiscardable(true)` so the autosave doesn't pollute the undo stack with redundant entries. DocumentGroup's auto-save-in-place flushes the document to disk on the next system tick.
- Implementation uses a `Task` with `try await Task.sleep` + `Task.checkCancellation`, on the main actor.

### 8. Error surface — `DocumentError.swift` + `ActiveAlert.swift` + `ToastModifier.swift`
*Addresses adversarial F-002 (via AC-RECOVER-1/2 design) and F-008 (via VoiceOver announcement wiring).*

- `enum DocumentError: Error { case invalidEncoding, saveFailed(underlying: Error), fileMissing, iCloudDownloadFailed }`.
- `enum ActiveAlert: Identifiable { case saveFailed(DocumentError), invalidEncoding, iCloudDownloadFailed }` — drives a single SwiftUI `.alert(item:)` modifier on `DocumentView`.
- **Save-failed alert** (AC-RECOVER-1): two buttons — `"Copy contents to clipboard"` and `"Dismiss"`. Body text names the failure ("Couldn't save. Your edits are still in memory and can be copied.").
- **Copy action implementation** (AC-RECOVER-1, AC-RECOVER-2, AC-A11Y-3 — *addresses adversarial F-008*): the Copy button's action closure does three things, in order, on `@MainActor`:
  1. `UIPasteboard.general.string = document.text` (write clipboard).
  2. `UIAccessibility.post(notification: .announcement, argument: NSLocalizedString("Copied", comment: "VoiceOver announcement after Copy contents to clipboard"))` (audible confirmation for VoiceOver users — fires regardless of toast visibility, satisfying AC-A11Y-3's independence requirement).
  3. Trigger `toast = "Copied"` on the host `DocumentView` (visual confirmation).
- **Toast** (AC-RECOVER-2): `ToastModifier` shows a transient bottom-aligned `Text` for 2 s after `toast` is set. Implemented as a SwiftUI `ViewModifier` with a `@State` `Task` that clears `toast` after `Task.sleep(for: .seconds(2))`. The toast text uses `.accessibilityHidden(true)` because VoiceOver users get the announcement instead, and double-announcing is more annoying than helpful.
- `invalidEncoding` (EC-4): the document fails to open and the user is bounced back to the browser with an alert; no Copy action (there's no in-memory text to copy).
- `iCloudDownloadFailed` (EC-13 failure path): user-visible alert; user dismisses back to browser.
- `fileMissing`: surfaced as a `saveFailed(.fileMissing)` for the skeleton — the recovery alert with Copy still applies. Full deletion banner is Roadmap #3.

### 9. UTType registration
- `Info.plist` declares the app's document types as conforming to `public.plain-text` with extensions `md` and `markdown` and identifier `net.daringfireball.markdown` (the de-facto UTI used by other markdown apps so files associated with our app are picked up cleanly).
- This is what makes `DocumentGroup` filter the browser to markdown files (AC-1.3).

### 10. Privacy Manifest — `PrivacyInfo.xcprivacy`
*Addresses adversarial F-006.*

- `NSPrivacyTracking = false`.
- `NSPrivacyTrackingDomains = []`.
- `NSPrivacyCollectedDataTypes = []`.
- `NSPrivacyAccessedAPITypes` enumerates the required-reason API categories `UIDocument` and `DocumentGroup` actually touch:
  - `NSPrivacyAccessedAPICategoryFileTimestamp` with reason `C617.1` (file timestamp inspected for display in document metadata; reading/writing in-place).
  - `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (SwiftUI/DocumentGroup internals persist scene-state/document-state via `UserDefaults`; we do not write our own preferences in this feature, but the framework does on our behalf and Apple's reviewer holds the manifest accountable).
  - `NSPrivacyAccessedAPICategoryDiskSpace` with reason `E174.1` (`UIDocument` checks free space before saving; not user-facing but invoked by the framework).
- Required for App Store submission in 2026.
- If the build agent finds during implementation that any of the above APIs are NOT actually called by `UIDocument`/`DocumentGroup` on iOS 26 (because Apple reorganized the internals), drop the unused entry — over-declaring is acceptable but wasteful; under-declaring is a submission reject.

### 11. Save status observer — `SaveStatusObserver.swift`
*Addresses adversarial F-003 (with follow-on mechanism clarification).*

- `@Observable @MainActor final class SaveStatusObserver`.
- **Subscription mechanism (clarified per F-003 follow-on).** SwiftUI's `DocumentGroup` does not expose the underlying `UIDocument` instance to user code. The observer therefore subscribes to `UIDocument.stateChangedNotification` with `object: nil` (global). This is safe in Markus because the app is single-document-at-a-time per the project declaration — at most one `UIDocument` is in `.normal`/`.savingError`/`.editingDisabled` state at any moment, so any state-change notification can be treated as relevant. A future feature that ever opens multiple documents simultaneously would need to revisit this (likely by adding a `notification.object as? UIDocument` identity check; flagged as a Roadmap-3-or-later concern, not skeleton).
- `init()` (no arguments — there's no `UIDocument` to pass in) registers the observer; `deinit` removes it.
- Exposes `@Published var lastSaveError: DocumentError?` — set when the most recent state-change notification's source document is in `.savingError`. `DocumentView` observes this and triggers the save-failed alert (component #8, AC-RECOVER-1).
- Exposes `@Published var isDownloadingFromiCloud: Bool` — set when a notification's source document is in `.editingDisabled` AND not in `.normal`. `DocumentView` uses this to show `DocumentLoadingView` (component #12) when needed.
- The notification handler runs on the main thread (`UIDocument` posts on its own queue, but the handler uses `Task { @MainActor in … }` to hop) so all `@Published` mutations stay on `@MainActor` per Swift 6 strict concurrency.
- **Build-agent note:** if iOS 26's `UIDocument.stateChangedNotification` userInfo provides the source document directly (rather than via `notification.object`), use that path — the API may have moved in modern releases.

### 12. Document loading view — `DocumentLoadingView.swift`
*Addresses adversarial F-007 (architecture side) and requirements EC-13.*

- Tiny SwiftUI view: a centered `ProgressView` with the label "Downloading…".
- `DocumentView` renders this in place of `RenderedView`/`RawEditorView` whenever `saveStatusObserver.isDownloadingFromiCloud == true`.
- **Possible redundancy note (per F-007 follow-on).** SwiftUI's `DocumentGroup` may itself show a system download indicator before handing the document to `MarkdownDocument.init(configuration:)`, in which case `isDownloadingFromiCloud` will never observe `.editingDisabled` from inside the document view and `DocumentLoadingView` will never render. This is acceptable — the component is harmless if unused, and serves as a safety net if the system indicator is missing/insufficient on iOS 26. The build agent should verify behavior on a real device with a not-yet-downloaded iCloud file before declaring the work complete; if `DocumentLoadingView` is verified unreachable, it may be deleted, but leaving it in is also fine.
- On a download failure (`SaveStatusObserver` reports `.savingError` while still `.editingDisabled`), `DocumentView` sets `activeAlert = .iCloudDownloadFailed` and dismisses back to the document browser on alert dismissal.

## Project layout

```
Markus_v3.xcodeproj/
Markus_v3/
  App/
    Markus_v3App.swift
    Info.plist
    PrivacyInfo.xcprivacy
  Documents/
    MarkdownDocument.swift
    DocumentError.swift
    ActiveAlert.swift
    SaveStatusObserver.swift
  Models/
    DocumentMode.swift
    AutosaveCoordinator.swift
  Views/
    DocumentView.swift
    RenderedView.swift
    RawEditorView.swift
    DocumentLoadingView.swift
    ToastModifier.swift
Markus_v3Tests/                  (XCTest unit tests)
  MarkdownDocumentTests.swift
  AutosaveCoordinatorTests.swift
  SaveStatusObserverTests.swift
Markus_v3UITests/                (XCUITest end-to-end)
  WalkingSkeletonFlowUITests.swift
Package.resolved                 (SwiftPM lockfile, committed)
```

## Dependencies

Single external Swift package:

- **MarkdownUI** — github.com/gonzalezreal/swift-markdown-ui, pinned via SwiftPM as `.upToNextMinor(from: "2.4.0")` (*addresses adversarial F-005*). Pure-SwiftUI GFM renderer with Theme support. `Package.resolved` is committed. Bumping past a minor (2.5 → 2.6) requires an intentional change in the Xcode project's package settings, not an unattended `swift package update`.

This is the project's first external dependency. Alternatives considered and rejected:
- **swift-markdown** (Apple) — parser only; would require building our own SwiftUI renderer (too much for a skeleton).
- **Down** — cmark-gfm wrapper rendering to `NSAttributedString`; less SwiftUI-native, requires more glue.
- **Hand-rolled** — out of scope for a walking skeleton.

## Contracts and seams

| Seam (from declaration.md Shape) | Realized as | Skeleton scope |
|---|---|---|
| Document browser entry | `DocumentGroup` at app root | Full participation; no custom UI |
| File access layer | `ReferenceFileDocument` + DocumentGroup's UIDocument under the hood | Read + write-in-place only; no bookmark persistence, no external-change observation, no follow-on-move, no delete detection |
| Document model | `MarkdownDocument` class | Holds `text` + dirty-via-undo |
| Rendered view | `RenderedView` (MarkdownUI) | GFM display, tap-to-edit, link-tap-to-edit; no fading chrome, no long-press menu |
| Raw editor | `RawEditorView` (TextEditor) | Plain monospace text editing; no autocorrect tuning, no list continuation, no shortcuts |
| Mode switcher | `@State mode: DocumentMode` in `DocumentView` | Tap-to-edit, eye-icon-to-render; no scroll-anchor preservation |
| Conflict & lifecycle UI | `DocumentError` + minimal alert/banner surface | Non-fatal save-error surface only; no conflict sheet, no deletion banner, no new-file flow |

Each seam has an obvious extension point for the next Roadmap feature:
- Roadmap #2 (last-file resume): persist `UIDocument.fileURL` as a security-scoped bookmark on close; on next launch, attempt to resolve and present the document directly instead of `DocumentGroup`'s browser.
- Roadmap #3 (conflict + lifecycle): observe `UIDocument.documentStateChangedNotification`; reuse `DocumentError`'s banner surface for deletion; build the three-option sheet against the existing `MarkdownDocument`.
- Roadmap #4 (scroll preservation): inject a `ScrollViewReader`-based anchor into both `RenderedView` and `RawEditorView`; the mode switcher reads/writes it.
- Roadmap #5 (new file creation): pre-existing `DocumentGroup(newDocument:)` API already supports this — wire up `Markus_v3App` accordingly.
- Roadmap #6 (editing polish): subclass `UITextView` and bridge via `UIViewRepresentable`, replacing `TextEditor`.
- Roadmap #7 (full a11y pass): the two AC-A11Y additions already establish the labelling pattern; the rest is propagation.

## Build agent must know

- **Do not invent file-management UI.** `DocumentGroup` is the only entry point. If a custom list of recent files seems tempting, that's Roadmap #2 (and even there, it's "reopen the last file directly," not a list).
- **Do not persist mode.** `@State` only; reset on every document open. Mode survives short backgrounding (scene alive) but resets on scene tear-down per EC-6 — this is the explicit acceptable behavior, not a bug to fix.
- **Do not copy the file anywhere.** All reads/writes go through the `ReferenceFileDocument` lifecycle; do not write `text` to `Documents/` or `Caches/` or `tmp/` for any reason in this feature.
- **Do not tune the text editor.** AC-4.6 mandates default behavior. Smart quotes, autocorrect, list continuation are Roadmap #6.
- **Do not add a settings screen, an onboarding flow, or any nav stack pages.** Project-level out-of-scope.
- **All UI work runs on `@MainActor`.** Swift 6 strict concurrency is on; document state mutations stay on the main actor.

## Changes from the prior pass

Third-pass design — addresses the three remaining adversarial findings from the re-attack pass.

- **Component #8 (Error surface)** — Copy action now explicitly calls `UIAccessibility.post(notification: .announcement)` before triggering the visual toast; toast text is `.accessibilityHidden` to avoid double-announce (addresses F-008 architecture side, satisfies AC-A11Y-3).
- **Component #11 (SaveStatusObserver)** — subscription mechanism clarified: global `UIDocument.stateChangedNotification` (object: nil) instead of per-document, because SwiftUI's `DocumentGroup` doesn't expose `UIDocument` to user code. Safe in Markus because the app is single-document-at-a-time (addresses F-003 follow-on).
- **Component #12 (DocumentLoadingView)** — added explicit note that `DocumentGroup` may handle iCloud download natively and this component may be unreachable; safety-net behavior documented (addresses F-007 follow-on).

**Second-pass changes (retained):** `MarkdownDocument.initialByteSize`, mode initialization from byte size, Privacy Manifest enumeration, MarkdownUI pin tightening.

## Requirements implications

Three pre-existing clarifications from the first pass remain (AC-3.3 / AC-3.4 / AC-4.4). No new clarifications from this pass.

The 500 KB threshold for EC-2 is a design constant declared in `DocumentView`. If tuning is desired later (e.g., 250 KB or 1 MB based on real-world testing), it's a one-line change with no cascading impact on requirements.

## Architecture stable — no requirements changes flagged
