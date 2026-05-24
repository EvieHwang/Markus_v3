# Design: resume-and-create-2

*Builds on `walking-skeleton-1` design. Most existing components (DocumentView, RenderedView, RawEditorView, AutosaveCoordinator, DocumentError, ActiveAlert, ToastModifier, DocumentLoadingView) carry over with little or no change. This document focuses on what is new or refactored.*

## Ground-truth check (resolved before drafting)

- **Precedent repo:** none. No external precedent named in CLAUDE.md.
- **CLAUDE.md sections leaned on:** Run/test/deps (iOS via Xcode + SwiftPM), Deployment target (manual Xcode build, no CI), Constitution → Testing (Swift Testing + XCUITest), Constitution → Standards (Apple HIG). User confirmed current.
- **Xcode/SDK / deployment target / concurrency:** inherited from walking-skeleton-1 design — Xcode 26, iOS 18 minimum, Swift 6 strict concurrency, `@MainActor` by default.
- **Pattern reuse from constitution.md:** none yet from constitution (it still registers only Python and React patterns). This feature is the second iOS surface in the repo and inherits the conventions walking-skeleton-1 set without citing them as registered patterns.
- **In-repo precedent:** walking-skeleton-1 is the only prior iOS feature. Its components and project layout are the baseline.

## Architectural shift — surfaced for explicit assent

Walking-skeleton-1 implemented the document-based app via SwiftUI's `DocumentGroup` + `ReferenceFileDocument`. The requirements for this feature explicitly name the UIKit API surface (`UIDocumentBrowserViewController.documentBrowser(_:didRequestDocumentCreationWithHandler:)`, `NSUserActivity` for state restoration). Two of the named behaviors are not cleanly reachable from `DocumentGroup`:

1. **Create with our own filename in our own directory.** `DocumentGroup`'s built-in Create button hands control to the system's save dialog. There is no documented hook to intercept it with our own "create `Untitled.md` in the last-opened directory" handler.
2. **Resume directly into a document on launch.** `DocumentGroup` always presents the browser first; there is no documented "skip the browser, open this URL" entry point for cold launch.

The architecture therefore **migrates the app shell from `DocumentGroup` to `UIDocumentBrowserViewController`** (wrapped under a thin SwiftUI App + `UIApplicationDelegateAdaptor`), and **migrates `MarkdownDocument` from `ReferenceFileDocument` to `UIDocument`**. The SwiftUI views below the app shell (`DocumentView` and its children) survive nearly verbatim — they are hosted in a `UIHostingController` that the browser presents.

This is the single biggest change in the feature. It is flagged in the Requirements implications section at the end. The build agent must not start until the user has approved this shift (or directed a different one).

Justification:
- It is what the requirements (as-written) imply.
- It is what Apple's own document-based apps (Files, Pages, Numbers) do.
- It simplifies walking-skeleton-1's `SaveStatusObserver` (the "global notification + single-document assumption" workaround in walking-skeleton-1 design #11 is no longer necessary — we hold a `UIDocument` reference directly).
- It sets up Roadmap #3 (conflict + lifecycle) with first-class access to `UIDocument` state notifications.

Trade-offs:
- Larger surface area added than a thin feature would suggest. Most of the size is one-time platform plumbing, not feature-specific code.
- Walking-skeleton-1 tests for `ReferenceFileDocument` mechanics must be rewritten against `UIDocument`.

## High-level shape

- **Scene root** is a `UIDocumentBrowserViewController` subclass (`MarkusDocumentBrowserViewController`).
- **Opening a document** uses the system pattern: `presentDocument(at:)` with the system's zoom transition. The presented controller is a `UINavigationController` whose root is a `UIHostingController` hosting the existing SwiftUI `DocumentView`.
- **The nav controller's back button** is the standard left-bar chevron + previous-screen label ("Documents"). Tapping it dismisses the presented nav controller, returning to the browser. Edge-swipe-back is added explicitly via `UIScreenEdgePanGestureRecognizer` on the nav controller's view, because `UIDocumentBrowserViewController`'s present-with-transition pattern does not give us `interactivePopGestureRecognizer` for free (see Requirements implications).
- **Resume** is driven by `LastDocumentStore`, which persists an `NSUserActivity` carrying a security-scoped bookmark to the most recently opened file. On scene activation, the store is consulted; on resolution success, the browser is told to immediately `presentDocument(at:)` the resolved URL.
- **Create** is driven by `CreateNewDocumentFlow`, invoked from the browser's `didRequestDocumentCreationWithHandler` delegate method. The flow consults `LastDocumentStore` for the target directory, falls back to local Documents if needed, asks `UntitledNameResolver` for a free filename, writes a zero-byte file, registers it with `UntouchedFileTracker`, and returns the URL to the completion handler.
- **Untouched-file cleanup** runs on document close. `UntouchedFileTracker` deletes any newly-created file that never received a keystroke.

## Components

### 1. App entry — `Markus_v3App.swift` + `AppDelegate.swift` + `SceneDelegate.swift` *(rewritten)*

- `Markus_v3App` is a SwiftUI `App` with `@UIApplicationDelegateAdaptor(AppDelegate.self)`. Its body returns a `WindowGroup { EmptyView() }` — the real UI is driven by the UIKit scene delegate. This pattern keeps `@main` SwiftUI-flavored while letting UIKit own scene/window construction (required by `UIDocumentBrowserViewController` being the scene root).
- `AppDelegate` configures the scene-session role to use `SceneDelegate`.
- `SceneDelegate` in `scene(_:willConnectTo:options:)`:
  - Constructs the `UIWindow`, sets `MarkusDocumentBrowserViewController` as the root.
  - Calls `LastDocumentStore.shared.resolveLastDocumentURL()`. If non-nil, immediately calls `browser.presentDocument(at: url)` after `makeKeyAndVisible()` — the user sees the browser zoom directly into the document, with no perceptible browser flash (the system handles the transition).
  - If `NSUserActivity` is present in `connectionOptions.userActivities`, that takes precedence over the bookmark — the activity carries the URL directly.
- On `sceneDidEnterBackground`, calls `UntouchedFileTracker.shared.cleanupIfUntouched(...)` for any tracked URL.

### 2. `MarkusDocumentBrowserViewController.swift` *(new)*

- Subclass of `UIDocumentBrowserViewController`. Sets itself as its own delegate.
- Configured for the markdown UTTypes (`UTType.markdown`, `net.daringfireball.markdown`) — same as walking-skeleton-1's UTType registration.
- `allowsDocumentCreation = true`. `allowsPickingMultipleItems = false`.
- Delegate methods:
  - **`documentBrowser(_:didRequestDocumentCreationWithHandler:)`** *(AC-4.1)*: hands off to `CreateNewDocumentFlow.makeNewDocument(completion:)`. The flow returns `(url: URL, importMode: .move)` or an error; the handler is called with the result.
  - **`documentBrowser(_:didPickDocumentsAt:)`**: calls `presentDocument(at: urls.first!)`.
  - **`documentBrowser(_:didImportDocumentAt:toDestinationURL:)`**: calls `presentDocument(at: destinationURL)`.
  - **`documentBrowser(_:failedToImportDocumentAt:error:)`**: shows a non-fatal alert reusing the `DocumentError` surface (component reused from walking-skeleton-1 #8).
- **`presentDocument(at url: URL)`**:
  - Creates a `MarkdownDocument(fileURL: url)` (the new `UIDocument` subclass — see component #5).
  - Wraps a SwiftUI `DocumentView(document:)` in a `UIHostingController`.
  - Wraps the hosting controller in a `UINavigationController`, sets the hosting controller's `navigationItem.leftBarButtonItem` to a custom chevron + "Documents" item whose action dismisses the modal.
  - Adds a `UIScreenEdgePanGestureRecognizer` to the nav controller's view with `edges = .left`; on `.recognized`, dismisses the modal (AC-3.3 implementation note).
  - Uses `transitionController(forDocumentAt: url)` for the zoom presentation animation.
  - On document open success, calls `LastDocumentStore.shared.record(url:)`.

### 3. `LastDocumentStore.swift` *(new)*

`@MainActor final class LastDocumentStore` — singleton-style (`static let shared`), but injectable for tests.

- **State.** A single security-scoped bookmark `Data?` persisted to `UserDefaults` under key `LastDocumentStore.bookmarkKey`. The bookmark is the durable handle; `NSUserActivity` is its carrier across scene-restoration events but `UserDefaults` is the cold-start source of truth.
- **`record(url: URL)`** *(AC-1.5, AC-3.5)*: creates a bookmark with `URL.bookmarkData(options: .minimalBookmark, …)`, writes it to UserDefaults, and attaches the bookmark data to the scene's `NSUserActivity` (`activityType = "com.evehwang.Markus.openDocument"`). The activity is **not** marked `isEligibleForHandoff` (out of scope).
- **`resolveLastDocumentURL() -> URL?`** *(AC-1.1, AC-1.4, EC-1 through EC-7)*: reads bookmark data from UserDefaults. Calls `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`. If `isStale` is true, attempts to refresh (recreate bookmark from resolved URL and re-persist). If resolution throws, returns nil. **Critically**, calls `startAccessingSecurityScopedResource()` on the resolved URL before returning it; the caller is responsible for the matching `stopAccessing…` when the document closes.
- **`resolveLastDocumentDirectoryURL() -> URL?`** *(AC-4.2)*: same as above but returns the *parent* of the resolved URL. The directory is also security-scoped (the bookmark scope covers the parent because iOS document bookmarks scope to the file system tree, but if the parent is not writable the caller falls through to local Documents per AC-5.1).
- **`clear()`** *(AC-2.4)*: removes the persisted bookmark and the scene's userActivity. Called by SceneDelegate when bookmark resolution fails.

**Concurrency.** All public methods are `@MainActor`. Bookmark resolution can be slow (sync provider round-trip); a future revision may move resolution to a background task with a main-actor callback, but the synchronous-on-main-actor approach is acceptable for this feature because resume blocks scene presentation anyway.

### 4. `CreateNewDocumentFlow.swift` + `UntitledNameResolver.swift` *(new)*

**`CreateNewDocumentFlow`** — `@MainActor struct`, stateless orchestrator.

- **`makeNewDocument(completion: @escaping (Result<URL, Error>) -> Void)`**:
  1. Ask `LastDocumentStore.shared.resolveLastDocumentDirectoryURL()` for the target directory.
  2. If non-nil, verify writability via `FileManager.default.isWritableFile(atPath: ...)` (AC-4.2 / AC-5.1 / EC-14).
  3. If nil or not writable, use `FileManager.default.url(for: .documentDirectory, in: .userDomainMask, …)` — the "On My iPhone / Markus" folder (AC-5.1 / EC-13).
  4. Acquire security scope on the target directory if it came from the bookmark.
  5. Ask `UntitledNameResolver.nextUntitledURL(in: directory)` for the target URL.
  6. Create a zero-byte file via `FileManager.default.createFile(atPath: ...)` (AC-4.4).
  7. Register the URL with `UntouchedFileTracker.shared.registerUntouched(url:)`.
  8. Release security scope on the directory.
  9. Call `completion(.success(url))`.
- **Error path** (EC-12): if creation fails at step 6, call `completion(.failure(...))`. The browser delegate translates this to a non-fatal alert reusing `DocumentError.saveFailed(...)`-style messaging — text reads "Couldn't create new file." No clipboard recovery (no in-memory content to rescue).

**`UntitledNameResolver`** — pure `struct`, no state, no side effects.

- **`nextUntitledURL(in directory: URL) -> URL`** *(AC-4.3, EC-9, EC-11)*:
  - Loop N from 1 upward. For N=1, candidate filename is `Untitled.md`; for N≥2, `Untitled \(N).md`.
  - Probe with `FileManager.default.fileExists(atPath: candidate.path)` — `fileExists` returns true for both files and directories, so EC-11 (folder collision) is handled automatically.
  - Return the first non-existing candidate. **Lowest unused integer wins, gaps are filled** (EC-9).
- **Testability.** Takes an injected `FileManager` for unit tests; defaults to `.default`.
- **No upper bound enforced** (EC-10). The OS will refuse creation long before this matters.

### 5. `MarkdownDocument.swift` *(refactored — `ReferenceFileDocument` → `UIDocument`)*

- `final class MarkdownDocument: UIDocument`.
- **`override func contents(forType:) throws -> Any`**: returns `text.data(using: .utf8) ?? Data()`.
- **`override func load(fromContents contents: Any, ofType:) throws`**: decodes UTF-8; throws `DocumentError.invalidEncoding` on failure (preserves walking-skeleton-1 EC-4 behavior).
- **Holds `@Published var text: String`** for SwiftUI binding (must be on `@MainActor`; `UIDocument` already calls `load`/`contents` on the main thread for the document-based app pattern).
- **Holds `let initialByteSize: Int`** — set during `load(fromContents:ofType:)` from `(contents as? Data)?.count ?? 0`. Preserves walking-skeleton-1's EC-2 large-file behavior.
- **`override func updateChangeCount(_:)`** is called from the text-change handler to mark dirty (replaces walking-skeleton-1's `markDirty()` no-op undo trick — `UIDocument` exposes change-count directly).
- **First-keystroke hook** *(AC-6.2 / AC-6.3)*: the text-change handler also calls `UntouchedFileTracker.shared.markTouched(url: fileURL)` on the first mutation. Subsequent mutations skip this call (the tracker is idempotent on `markTouched`).
- **Close lifecycle**: when the document closes (via `UIDocument.close(completionHandler:)` from the dismiss path), `SceneDelegate` (or the dismissing controller) calls `UntouchedFileTracker.shared.cleanupIfUntouched(url:)` after close completes.

### 6. `UntouchedFileTracker.swift` *(new)*

`@MainActor final class UntouchedFileTracker` — singleton (`static let shared`), injectable for tests.

- **State.** `private var untouchedURLs: Set<URL>`.
- **`registerUntouched(url: URL)`** *(AC-6.1 setup)*: inserts URL into the set. Called by `CreateNewDocumentFlow`.
- **`markTouched(url: URL)`** *(AC-6.2)*: removes URL from the set. Called by `MarkdownDocument` on first keystroke. Idempotent — safe to call repeatedly.
- **`cleanupIfUntouched(url: URL)`** *(AC-6.1, AC-6.4)*: if URL is in the set, attempts `try? FileManager.default.removeItem(at: url)` and removes from the set regardless of delete success. Silent on failure (EC-15 / AC-6.4).
- **`cleanupAllUntouched()`** *(AC-6.5 force-quit best-effort path)*: iterates the set and removes each. Called from `SceneDelegate.sceneDidEnterBackground` and `applicationWillTerminate`. Best-effort; if the app is killed before this fires, a zero-byte stub may remain on disk (EC-16, acceptable per AC-6.4).
- **Last-opened pointer revert** *(AC-6.5)*: when `cleanupIfUntouched` actually deletes a file, it also notifies `LastDocumentStore` to **not** record this URL as last-opened. Implementation: `CreateNewDocumentFlow` defers calling `LastDocumentStore.record(url:)` until *after* the first keystroke, not at create time. Until then, the previous last-opened pointer remains. This is a minor protocol change between components — flagged for the build agent.

### 7. `SaveStatusObserver.swift` *(simplified)*

Walking-skeleton-1's `SaveStatusObserver` used a global `UIDocument.stateChangedNotification` subscription because `DocumentGroup` did not expose the `UIDocument` instance (walking-skeleton-1 design #11). Now that we hold the `UIDocument` directly:

- Subscription becomes per-document: `NotificationCenter.default.addObserver(forName: UIDocument.stateChangedNotification, object: document, ...)`. No more global-subscription single-document assumption.
- The "future-feature risk" callout in walking-skeleton-1 #11 is resolved.
- Otherwise unchanged.

### 8. `DocumentView.swift` *(small modification)*

- Accepts a `MarkdownDocument` (now a `UIDocument` instance) instead of an environment-bound document.
- New initialization param: optional `onDismiss: () -> Void` — invoked by the back chevron and edge-swipe path so the hosting nav controller knows to dismiss.
- The toolbar back chevron is no longer the SwiftUI default — it's a UIKit `UIBarButtonItem` installed on the hosting controller's `navigationItem.leftBarButtonItem` by `MarkusDocumentBrowserViewController.presentDocument(at:)`. Inside the SwiftUI view, no chevron is rendered; the chevron is part of the UIKit nav bar surrounding the hosting controller.
- **New-document keyboard-up behavior** *(AC-4.4)*: when `DocumentView` is initialized with a zero-byte document, the initial mode is `.raw` (overriding the existing `initialByteSize`-based logic) **and** the raw editor focuses the text view immediately, raising the keyboard. Implementation: a `@FocusState` bound to the `TextEditor` is set to `true` in `.onAppear` when the document is zero-byte. The mode-from-byte-size logic in walking-skeleton-1 stays but is preempted by the zero-byte case here.

### 9. `Info.plist` updates

- Add scene configuration entries (`UIApplicationSceneManifest` → `UIWindowSceneSessionRoleApplication` → custom scene class for `SceneDelegate`).
- Confirm `UISupportsDocumentBrowser = YES` and `LSSupportsOpeningDocumentsInPlace = YES` (AC-5.4). Walking-skeleton-1 should already have these via `DocumentGroup`, but verify post-migration.
- UTType document-types entries (the markdown content types) carry over from walking-skeleton-1.

### 10. `PrivacyInfo.xcprivacy`

- No new entries required by this feature. The categories walking-skeleton-1 declared (`FileTimestamp`, `UserDefaults`, `DiskSpace`) cover this feature's behaviors (the bookmark write uses `UserDefaults`; the Untitled collision probe uses file metadata).

## Project layout

Additions and modifications to walking-skeleton-1's layout:

```
Markus_v3/
  App/
    Markus_v3App.swift              [rewritten — thin SwiftUI shell + UIApplicationDelegateAdaptor]
    AppDelegate.swift               [new]
    SceneDelegate.swift             [new]
    Info.plist                      [updated — scene config]
    PrivacyInfo.xcprivacy           [unchanged]
  DocumentBrowser/                  [new directory]
    MarkusDocumentBrowserViewController.swift   [new]
    CreateNewDocumentFlow.swift                 [new]
    UntitledNameResolver.swift                  [new]
  Persistence/                      [new directory]
    LastDocumentStore.swift         [new]
  Documents/
    MarkdownDocument.swift          [refactored — ReferenceFileDocument → UIDocument]
    DocumentError.swift             [unchanged]
    ActiveAlert.swift               [unchanged]
    SaveStatusObserver.swift        [simplified — per-document subscription]
    UntouchedFileTracker.swift      [new]
  Models/
    DocumentMode.swift              [unchanged]
    AutosaveCoordinator.swift       [unchanged]
  Views/
    DocumentView.swift              [updated — accepts UIDocument, zero-byte → raw + focus]
    RenderedView.swift              [unchanged]
    RawEditorView.swift             [unchanged]
    DocumentLoadingView.swift       [unchanged]
    ToastModifier.swift             [unchanged]
Markus_v3Tests/
  ... existing tests ...
  UntitledNameResolverTests.swift   [new — pure unit, exhaustive collision matrix]
  LastDocumentStoreTests.swift      [new — bookmark roundtrip with temp files]
  UntouchedFileTrackerTests.swift   [new — register/touch/cleanup semantics]
  CreateNewDocumentFlowTests.swift  [new — directory-fallback + Untitled-naming integration]
  MarkdownDocumentMigrationTests.swift  [new — load/save/dirty under UIDocument]
Markus_v3UITests/
  WalkingSkeletonFlowUITests.swift  [updated — adjust for new app shell, still asserts skeleton flow]
  ResumeAndCreateFlowUITests.swift  [new — resume on relaunch, create-from-browser end-to-end]
```

## Dependencies

No new external dependencies. MarkdownUI remains the sole external SwiftPM dependency, pinned per walking-skeleton-1.

## Contracts and seams

Mapping to declaration.md's Shape, updated for this feature:

| Seam | This-feature realization | Notes |
|---|---|---|
| Document browser entry | `MarkusDocumentBrowserViewController` (UIKit, scene root) — replaces walking-skeleton-1's `DocumentGroup` | The architectural shift |
| File access layer | `LastDocumentStore` (bookmarks) + `MarkdownDocument` as `UIDocument` + `CreateNewDocumentFlow` (write + naming) + `UntouchedFileTracker` (cleanup) | Now first-class; bookmark persistence and write-new-file are the new capabilities |
| Document model | `MarkdownDocument` (now `UIDocument`) | Same responsibilities, different base class |
| Rendered view | `RenderedView` | Unchanged |
| Raw editor | `RawEditorView` | Unchanged; gains `@FocusState`-driven keyboard-on-launch for zero-byte documents |
| Mode switcher | `@State mode: DocumentMode` in `DocumentView` | Unchanged; new entry condition for zero-byte = `.raw` |
| Conflict & lifecycle UI | `DocumentError` + alert surface (walking-skeleton-1 #8) — reused for EC-12 "couldn't create" error | The deletion banner and three-option sheet are still Roadmap #3 |

Each new component has an obvious extension point for the next Roadmap feature:
- Roadmap #3 (conflict + lifecycle): `SaveStatusObserver` is now per-document and observes a `UIDocument` reference directly, so external-change and deletion detection slot in cleanly. The three-option conflict sheet has a natural home alongside `ActiveAlert`.
- Roadmap #4 (scroll anchor): unchanged from walking-skeleton-1's plan.
- Roadmap #6 (editing polish): `RawEditorView` is still the surface; the `@FocusState` hook added here is reusable.

## Build agent must know

- **The DocumentGroup → UIDocumentBrowserViewController migration is the largest single change.** Build it first as a refactor of `Markus_v3App` + addition of `AppDelegate` + `SceneDelegate` + `MarkusDocumentBrowserViewController`, verify the skeleton flow still works end-to-end before adding resume or create logic on top. The DAG should reflect this — migration is Wave 1, resume and create live in later waves.
- **MarkdownDocument's class hierarchy changes (`ReferenceFileDocument` → `UIDocument`).** Existing `MarkdownDocumentTests` from walking-skeleton-1 require rewriting against the new base class. Do not delete them; rewrite. The behaviors under test (UTF-8 decode failure, `initialByteSize`, dirty-on-edit, save-to-original-location) still apply.
- **Security scope is acquired by `LastDocumentStore.resolveLastDocumentURL()` and must be released by the caller** when the document closes. `MarkdownDocument`'s close handler is the natural place for `stopAccessingSecurityScopedResource()`. Forgetting this leaks a file handle and causes the next resume to fail.
- **`UntouchedFileTracker.registerUntouched(url:)` must be called before the file is opened in `DocumentView`.** Otherwise, if the user immediately taps back without typing, the file leaks.
- **`LastDocumentStore.record(url:)` is called only after the first keystroke for newly created documents**, not at creation time. This is so an untouched-and-cleaned-up Untitled file does not become the resume target (AC-6.5).
- **The back-chevron `UIBarButtonItem` is installed by `MarkusDocumentBrowserViewController.presentDocument(at:)`**, not by SwiftUI inside `DocumentView`. Do not also add a SwiftUI-side chevron — double chrome.
- **Edge-swipe-back is implemented as a `UIScreenEdgePanGestureRecognizer` on the nav controller's view**, not via `interactivePopGestureRecognizer`. The recognizer's action calls the same dismiss path as the back chevron. (See Requirements implications.)
- **All UI work runs on `@MainActor`.** Inherited from walking-skeleton-1. `LastDocumentStore`, `CreateNewDocumentFlow`, and `UntouchedFileTracker` are all explicitly `@MainActor`.
- **Tests for `LastDocumentStore` use temp-directory bookmarks** to avoid touching real iCloud state. Tests for `UntitledNameResolver` use an injected `FileManager` mock and never touch disk.

## Requirements implications

Second pass. All three RIs from the first pass are resolved:

### RI-1 — App-shell architecture migration (DocumentGroup → UIDocumentBrowserViewController) — **resolved**

User explicitly approved the migration. The requirements text did not require changes; the approval is captured in the project decision log (informal — recorded in the feature folder's chat history and reflected in this design's High-level shape section).

### RI-2 — AC-3.3 edge-swipe-back mechanism — **resolved in requirements**

Requirements AC-3.3 has been rewritten to drop the `UINavigationController.interactivePopGestureRecognizer` citation and to specify `UIScreenEdgePanGestureRecognizer` as the implementation mechanism. Design and requirements agree.

### RI-3 — Zero-byte / new-file mode-default override — **resolved in requirements**

Requirements AC-4.4 has been expanded with the one-line clarification that zero-byte (new) files always open in raw mode with keyboard up, explicitly overriding walking-skeleton-1 EC-2's mode-from-byte-size rule. Design and requirements agree.

---

**Architecture stable — no requirements changes flagged.** Requirements ↔ architecture loop has converged. Ready for `/t3-adversarial`.
