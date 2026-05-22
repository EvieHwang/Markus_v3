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
- `init(configuration:)` decodes the file's bytes as UTF-8; on decode failure, throws a non-fatal `DocumentError.invalidEncoding` which the host surfaces with an alert and dismisses (EC-4).
- `snapshot(contentType:)` returns the current `text`; `fileWrapper(snapshot:configuration:)` writes UTF-8 bytes.
- A `markDirty()` helper registers a no-op undo against the host's `UndoManager` — this is how SwiftUI's DocumentGroup learns the document is dirty and schedules a save.

### 3. Document mode — `DocumentMode.swift`
- `enum DocumentMode { case rendered, raw }`. Local view state; never persisted (AC-5.4).

### 4. Document view — `DocumentView.swift`
- The top-level editor view bound to a `MarkdownDocument`.
- `@State private var mode: DocumentMode = .rendered` (rendered is the default on every open — AC-2.2).
- `@State private var hasUnsavedChanges = false` (drives the autosave debouncer).
- Body switches between `RenderedView` and `RawEditorView` based on `mode`.
- Navigation bar title is the document's filename without extension (AC-2.3), pulled from the host `UIDocument.fileURL` via SwiftUI's `DocumentConfiguration` environment.
- Toolbar item (only when `mode == .raw`): eye-icon button labeled "Show rendered" that sets `mode = .rendered`. The label is set via `.accessibilityLabel("Show rendered")` (AC-A11Y-1).
- On `mode` change to `.rendered`: trigger a save immediately (AC-5.2).
- `.onChange(of: scenePhase)` — on `.background`, trigger a save (AC-4.4).

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

### 8. Error surface — `DocumentError.swift` + a small `errorBanner` SwiftUI modifier
- `enum DocumentError: Error { case invalidEncoding, saveFailed(underlying: Error), fileMissing }`.
- `saveFailed` covers EC-9, EC-10, EC-12 — save fails non-fatally; the in-memory text is preserved and a transient `.alert` or banner is shown.
- `invalidEncoding` covers EC-4 — the document fails to open and the user is bounced back to the browser with an alert.
- `fileMissing` is reserved for use when a write fails because the file no longer exists at the original URL; the skeleton surfaces it as a saveFailed for now. Full handling (Save As, deletion banner) is Roadmap #3.

### 9. UTType registration
- `Info.plist` declares the app's document types as conforming to `public.plain-text` with extensions `md` and `markdown` and identifier `net.daringfireball.markdown` (the de-facto UTI used by other markdown apps so files associated with our app are picked up cleanly).
- This is what makes `DocumentGroup` filter the browser to markdown files (AC-1.3).

### 10. Privacy Manifest — `PrivacyInfo.xcprivacy`
- Declares **no** data collection, no tracking, no required-reason API usage beyond the standard file-access categories.
- Required for App Store submission in 2026.

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
  Models/
    DocumentMode.swift
    AutosaveCoordinator.swift
  Views/
    DocumentView.swift
    RenderedView.swift
    RawEditorView.swift
Markus_v3Tests/                  (XCTest unit tests)
  MarkdownDocumentTests.swift
  AutosaveCoordinatorTests.swift
Markus_v3UITests/                (XCUITest end-to-end)
  WalkingSkeletonFlowUITests.swift
Package.resolved                 (SwiftPM lockfile, committed)
```

## Dependencies

Single external Swift package:

- **MarkdownUI** — github.com/gonzalezreal/swift-markdown-ui (>= 2.4.0). Pure-SwiftUI GFM renderer with Theme support. Pinned via SwiftPM in the Xcode project; `Package.resolved` is committed.

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
- **Do not persist mode.** `@State` only; reset on every document open. Mode survives only across a backgrounding (per EC-6) because SwiftUI keeps the view alive.
- **Do not copy the file anywhere.** All reads/writes go through the `ReferenceFileDocument` lifecycle; do not write `text` to `Documents/` or `Caches/` or `tmp/` for any reason in this feature.
- **Do not tune the text editor.** AC-4.6 mandates default behavior. Smart quotes, autocorrect, list continuation are Roadmap #6.
- **Do not add a settings screen, an onboarding flow, or any nav stack pages.** Project-level out-of-scope.
- **All UI work runs on `@MainActor`.** Swift 6 strict concurrency is on; document state mutations stay on the main actor.

## Requirements implications

Three small clarifications surfaced; none reshape the requirements but they're worth recording:

1. **AC-3.3 (link tap in rendered mode → raw mode).** Implementation is via SwiftUI's `OpenURLAction` environment override. The exact behavior: the tap target is the link's hit area, not the surrounding document area, but the resulting action (switch to raw mode, no link follow) is identical to the AC. No requirements change.

2. **AC-3.4 (tap-to-edit requires a second tap to place cursor).** Naturally satisfied: a SwiftUI `TextEditor` requires a tap to gain focus once shown. The first tap was the mode switch (handled by `DocumentView` before `TextEditor` is rendered); the second tap places the cursor inside `TextEditor`. No requirements change.

3. **AC-4.4 typing-pause autosave.** The 500 ms idle save trigger is implemented as a debounced call to `markDirty()`, not a direct disk write — DocumentGroup's auto-save-in-place is the actual disk-writer and runs on its own cadence (typically within a second of the dirty mark). The user-visible latency from "stop typing" to "file on disk updated" may therefore be ~500 ms (debounce) + the system autosave tick (sub-second), totaling under ~1.5 s in practice. If the requirement is "edits hit disk within 500 ms of the last keystroke," that's tighter than this design provides and we'd need an explicit save call. Surfacing for confirmation.

## Architecture stable — no requirements changes flagged

(Item 3 above is a clarification, not a change. If the user reads it and wants tighter latency, they should re-run `/t3-requirements` to revise AC-4.4 explicitly; otherwise this design satisfies the requirements as written.)
