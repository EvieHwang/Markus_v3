# Design: resume-and-create-2

*Builds on `walking-skeleton-1` design. Most existing components (DocumentView, RenderedView, RawEditorView, AutosaveCoordinator, DocumentError, ActiveAlert, ToastModifier, DocumentLoadingView) carry over with little or no change. This document focuses on what is new or refactored.*

*Third pass — addresses adversarial findings F-002, F-003, F-004, F-005, F-006. F-001 (zero-byte mode-default ambiguity) is requirements-side and will be addressed in the next `/t3-requirements` pass.*

## Ground-truth check (resolved before drafting)

- **Precedent repo:** none. No external precedent named in CLAUDE.md.
- **CLAUDE.md sections leaned on:** Run/test/deps (iOS via Xcode + SwiftPM), Deployment target (manual Xcode build, no CI), Constitution → Testing (Swift Testing + XCUITest), Constitution → Standards (Apple HIG). User confirmed current.
- **Xcode/SDK / deployment target / concurrency:** inherited from walking-skeleton-1 design — Xcode 26, iOS 18 minimum, Swift 6 strict concurrency, `@MainActor` by default.
- **Pattern reuse from constitution.md:** none yet from constitution. This feature is the second iOS surface in the repo and inherits walking-skeleton-1's conventions without citing them as registered patterns.
- **In-repo precedent:** walking-skeleton-1 is the only prior iOS feature.

## Architectural shift — approved in prior loop

The app shell migrates from SwiftUI `DocumentGroup` + `ReferenceFileDocument` to UIKit `UIDocumentBrowserViewController` + `UIDocument`. SwiftUI views below the app shell (`DocumentView` and its children) survive nearly verbatim, hosted in a `UIHostingController` that the browser presents.

The user explicitly approved this migration as the right long-term foundation. The rationale and trade-offs are recorded in the conversation history and need not be re-litigated here.

## High-level shape

- **App entry** is a SwiftUI `App` with a `WindowGroup`. The window group hosts a `BrowserHostView` (a `UIViewControllerRepresentable`) that wraps a `MarkusDocumentBrowserViewController` instance. This is the "SwiftUI App owns the window; UIKit provides the view controller" hybrid pattern (canonical pattern 2 in iOS terminology — see component #1).
- **No separate `SceneDelegate` or `AppDelegate`.** SwiftUI's lifecycle modifiers (`.onChange(of: scenePhase)`, `.onContinueUserActivity`) cover the hooks we need. The migration does not pay for unnecessary UIKit lifecycle plumbing.
- **Opening a document** uses the system pattern: `presentDocument(at:)` with the system's zoom transition. The presented controller is a `UINavigationController` whose stack is `[placeholderVC, documentVC]`. The placeholder is never visible; it exists so the native `backBarButtonItem` renders with the previous-page title ("Documents").
- **Back navigation** uses the system's `backBarButtonItem` natively (no custom barbutton). Edge-swipe-back uses the system's `UINavigationController.interactivePopGestureRecognizer`, which is active because the nav stack has more than one VC.
- **Pop-triggered dismiss.** When the user pops back toward the placeholder (via chevron tap or edge swipe), the nav controller's delegate intercepts `willShow placeholderVC` and triggers `dismiss(animated:)` on the nav controller, using the browser's `transitionController(forDocumentAt:)` for the zoom-back animation. The placeholder is never visible because the dismiss begins during the pop animation.
- **Resume** is driven by `LastDocumentStore`, which persists an `NSUserActivity` carrying a security-scoped bookmark to the most recently opened file. On the browser representable's first appearance, the coordinator consults the store; on resolution success, it calls `presentDocument(at:)` on the browser.
- **Create** is driven by `CreateNewDocumentFlow`, invoked from the browser's `didRequestDocumentCreationWithHandler` delegate method. The flow consults `LastDocumentStore` for the target directory, falls back to local Documents if needed, asks `UntitledNameResolver` for a free filename, writes a zero-byte file, registers it with `UntouchedFileTracker`, and returns the URL to the completion handler.
- **Untouched-file cleanup** runs on document close (before stop-accessing security scope) and on scene-phase `.background` (best-effort sweep).
- **Single-scene-only** enforced via `Info.plist` (see component #9).

## Components

### 1. App entry — `Markus_v3App.swift` + `ContentView.swift` *(rewritten, pattern 2)*

*Addresses adversarial F-003.*

- `@main struct Markus_v3App: App` with `var body: some Scene { WindowGroup { ContentView() } }`.
- No `@UIApplicationDelegateAdaptor`, no `SceneDelegate`, no `AppDelegate`. The SwiftUI lifecycle is sufficient.
- `ContentView` is a thin SwiftUI view containing one child: `BrowserHostView()` (the `UIViewControllerRepresentable` defined in component #2). `ContentView` also installs three modifiers:
  - `.onChange(of: scenePhase)`: on transition to `.background`, calls `UntouchedFileTracker.shared.cleanupAllUntouched()` for the best-effort sweep (AC-6.5 force-quit path).
  - `.onContinueUserActivity("com.evehwang.Markus.openDocument") { activity in BrowserHostView.continue(activity) }`: routes a continued `NSUserActivity` (delivered after scene tear-down or on Handoff-like restoration if Apple delivers one) to the browser. The static `continue(_:)` is a coordinator hook that calls `presentDocument(at:)` for the URL in the activity.
  - `.handlesExternalEvents(preferring: [], allowing: [])`: explicitly empty — we don't accept external open events outside the document browser flow in this feature.
- **Resume on cold launch** is *not* handled here. It happens in `BrowserHostView.Coordinator.viewControllerDidAppear` (component #2) the first time the browser becomes visible — that's the moment `presentDocument(at:)` is safe to call.
- The `WindowGroup` produces exactly one scene because `Info.plist` sets `UIApplicationSupportsMultipleScenes = NO` (component #9; addresses adversarial F-002).

### 2. `BrowserHostView.swift` + `MarkusDocumentBrowserViewController.swift` *(new, with placeholder-VC dismiss pattern)*

*Addresses adversarial F-003 (representable bridge) and F-005 (native back chevron).*

**`BrowserHostView`** — `struct BrowserHostView: UIViewControllerRepresentable`.

- `makeUIViewController(context:)` constructs a `MarkusDocumentBrowserViewController`, wires its delegate (the browser is its own delegate), and stores a reference on `context.coordinator`.
- `makeCoordinator()` returns a `Coordinator` instance. The coordinator holds the browser reference, owns the `firstAppearance` flag, and serves as the static target for `onContinueUserActivity`.
- `updateUIViewController(_:context:)` is a no-op; state changes are driven by UIKit delegate methods, not by SwiftUI binding flow.
- `Coordinator` exposes a static `continue(_:NSUserActivity)` method routed from `ContentView.onContinueUserActivity`. The implementation extracts the URL from the activity's `userInfo` and calls `currentBrowser?.presentDocument(at: url)`.

**`MarkusDocumentBrowserViewController`** — subclass of `UIDocumentBrowserViewController`.

- Configured for the markdown UTTypes (`UTType.markdown`, `net.daringfireball.markdown`) — same as walking-skeleton-1.
- `allowsDocumentCreation = true`. `allowsPickingMultipleItems = false`.
- Sets itself as `delegate` and as the nav-controller delegate on any presented nav controller (see step 6 below).
- **`viewDidAppear(_:)` override** *(resume orchestration, replaces walking-skeleton-1's SceneDelegate-based orchestration)*:
  - Calls `super.viewDidAppear(animated)`.
  - On the *first* appearance (tracked by an instance flag), consults `LastDocumentStore.shared.resolveLastDocumentURL()`. If non-nil, calls `presentDocument(at: url)` immediately. The user sees the browser zoom directly into the document — the browser is visible for a single frame at most.
  - If the resolve returns nil, leaves the browser visible (first-ever-launch + unrecoverable-resume both fall here per AC-2.1 / AC-2.2).
- **Delegate methods:**
  - `documentBrowser(_:didRequestDocumentCreationWithHandler:)` → calls `CreateNewDocumentFlow.makeNewDocument(completion:)`. On success, returns `(url, .move)` to the handler; on failure, returns `(nil, .none)` and shows a non-fatal alert reusing the `DocumentError` surface (EC-12).
  - `documentBrowser(_:didPickDocumentsAt:)` → `presentDocument(at: urls.first!)`.
  - `documentBrowser(_:didImportDocumentAt:toDestinationURL:)` → `presentDocument(at: destinationURL)`.
  - `documentBrowser(_:failedToImportDocumentAt:error:)` → non-fatal alert via `DocumentError`.
- **`presentDocument(at url: URL)` — placeholder-VC + native-chevron pattern:**
  1. Construct `document = MarkdownDocument(fileURL: url)`.
  2. Call `document.open { success in … }` (component #5 details the failure paths). On `success == false`, do **not** present; surface the appropriate `DocumentError` alert on `self`. On success, continue to step 3.
  3. Construct `placeholderVC: UIViewController`. Set `placeholderVC.title = "Documents"` and `placeholderVC.view.backgroundColor = .systemBackground`. It is never visible; it exists so the native `backBarButtonItem` on `documentVC` renders as "‹ Documents."
  4. Construct `documentVC: UIHostingController(rootView: DocumentView(document: document))`. Set `documentVC.navigationItem.title = url.deletingPathExtension().lastPathComponent` (filename without extension — preserves walking-skeleton-1 AC-2.3).
  5. Construct `navController = UINavigationController(rootViewController: placeholderVC)`. Push `documentVC` with `animated: false`. The stack is now `[placeholderVC, documentVC]`. The native `backBarButtonItem` on `documentVC` is auto-rendered as the chevron + "Documents" label — visually identical to Apple's first-party document apps.
  6. Set `navController.delegate = self` so the browser intercepts navigation events. Implement `navigationController(_:willShow:animated:)` — when `viewControllerToShow === placeholderVC` (a pop is in progress), set `navController.transitioningDelegate = self.transitionController(forDocumentAt: url)` (reverse zoom) and call `navController.dismiss(animated: true)` from inside the `willShow` callback. The pop and dismiss animations overlap; the placeholder is never visible.
  7. Set `navController.modalPresentationStyle = .fullScreen`.
  8. Set `navController.transitioningDelegate = self.transitionController(forDocumentAt: url)` for the forward zoom presentation.
  9. Call `self.present(navController, animated: true)`.
  10. After successful presentation, the document's first-keystroke handler (component #5) will call `LastDocumentStore.shared.record(url:)`. Resume bookmark recording is deferred until first touch for newly created files (per AC-6.5); for files opened from the browser or resume path, recording happens immediately after `present` returns.
- **Edge-swipe-back falls out for free.** Because `documentVC` is the top of a multi-VC nav stack, `interactivePopGestureRecognizer` is automatically active. A left-edge pan triggers a pop; the `willShow placeholderVC` handler in step 6 fires; modal dismiss-with-zoom-back follows. **No custom `UIScreenEdgePanGestureRecognizer` is needed** — this is a deliberate consequence of pattern (b) and surfaces RI-4 in the Requirements implications section.

### 3. `LastDocumentStore.swift` *(new)*

*Addresses adversarial F-006 in the `record(url:)` failure path.*

`@MainActor final class LastDocumentStore` — singleton (`static let shared`), injectable for tests.

- **State.** A single security-scoped bookmark `Data?` persisted to `UserDefaults` under key `LastDocumentStore.bookmarkKey`. The bookmark is the durable handle; `NSUserActivity` is its carrier across scene-restoration events but `UserDefaults` is the cold-start source of truth.
- **`record(url: URL)`** *(AC-1.5, AC-3.5; addresses adversarial F-006)*: creates a bookmark via `URL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)`. On success, writes the data to UserDefaults and attaches it to the scene's `NSUserActivity` (`activityType = "com.evehwang.Markus.openDocument"`). Activity is **not** marked `isEligibleForHandoff` (out of scope).
  - **Failure handling.** `URL.bookmarkData(...)` can throw — share-extension inbox URLs, transient temp paths, files inaccessible due to security-scope race, files on volumes about to unmount. On throw: log via `os_log` at debug level (no user-visible UI per declaration's silent-failure stance), preserve any previously persisted bookmark (do not clear), and return without persisting the new URL. The visible consequence to the user is that the next cold launch falls through to the browser (AC-2.2) — same as a first-ever launch or a stale bookmark. The declaration's "no UI for the stale-bookmark case" rule covers this implicitly.
- **`resolveLastDocumentURL() -> URL?`** *(AC-1.1, AC-1.4, EC-1 through EC-7)*: reads bookmark data from UserDefaults. Calls `URL(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`. If `isStale` is true, recreates the bookmark from the resolved URL and re-persists. If resolution throws, returns nil. **Critically**, calls `startAccessingSecurityScopedResource()` on the resolved URL before returning it; the caller is responsible for the matching `stopAccessing…` when the document closes (component #5 lifecycle).
- **`resolveLastDocumentDirectoryURL() -> URL?`** *(AC-4.2)*: same as above but returns the parent of the resolved URL. The directory inherits security scope from the file bookmark; if the parent is not writable the caller falls through to local Documents per AC-5.1.
- **`clear()`** *(AC-2.4)*: removes the persisted bookmark and resets the scene's userActivity. Called when bookmark resolution fails (from `BrowserHostView.Coordinator.viewControllerDidAppear` and from `MarkdownDocument` open-failure paths in component #5).

**Concurrency.** All public methods are `@MainActor`. Bookmark resolution can be slow under sync-provider conditions; acceptable for this feature because resume blocks presentation by design.

### 4. `CreateNewDocumentFlow.swift` + `UntitledNameResolver.swift` *(new)*

**`CreateNewDocumentFlow`** — `@MainActor struct`, stateless orchestrator.

- **`makeNewDocument(completion: @escaping (Result<URL, Error>) -> Void)`**:
  1. Ask `LastDocumentStore.shared.resolveLastDocumentDirectoryURL()` for the target directory.
  2. If non-nil, verify writability via `FileManager.default.isWritableFile(atPath: ...)` (AC-4.2 / AC-5.1 / EC-14).
  3. If nil or not writable, use `FileManager.default.url(for: .documentDirectory, in: .userDomainMask, …)` — the "On My iPhone / Markus" folder (AC-5.1 / EC-13).
  4. Acquire security scope on the target directory if it came from the bookmark.
  5. Ask `UntitledNameResolver.nextUntitledURL(in: directory)` for the target URL.
  6. Create a zero-byte file via `FileManager.default.createFile(atPath: ..., contents: Data(), attributes: nil)` (AC-4.4).
  7. Register the URL with `UntouchedFileTracker.shared.registerUntouched(url:)`.
  8. Release security scope on the directory.
  9. Call `completion(.success(url))`.
- **Error path** (EC-12): if creation fails at step 6, call `completion(.failure(error))`. The browser delegate translates this to a non-fatal alert reusing `DocumentError.saveFailed(...)`-style messaging — text reads "Couldn't create new file." No clipboard recovery (no in-memory content to rescue).

**`UntitledNameResolver`** — pure `struct`, no state.

- **`nextUntitledURL(in directory: URL, fileManager: FileManager = .default) -> URL`** *(AC-4.3, EC-9, EC-11)*:
  - Loop N from 1 upward. For N=1, candidate filename is `Untitled.md`; for N≥2, `Untitled \(N).md`.
  - Probe with `fileManager.fileExists(atPath: candidate.path)` — returns true for both files and directories, so EC-11 (folder collision) is handled automatically.
  - Return the first non-existing candidate. **Lowest unused integer wins, gaps are filled** (EC-9).
- **Testability.** Takes injected `FileManager`; defaults to `.default`.
- **No upper bound enforced** (EC-10).

### 5. `MarkdownDocument.swift` *(refactored — `ReferenceFileDocument` → `UIDocument`)*

- `final class MarkdownDocument: UIDocument`.
- **`override func contents(forType:) throws -> Any`**: returns `text.data(using: .utf8) ?? Data()`.
- **`override func load(fromContents contents: Any, ofType:) throws`**: decodes UTF-8; throws `DocumentError.invalidEncoding` on failure (preserves walking-skeleton-1 EC-4 behavior).
- **`@Published var text: String`** for SwiftUI binding.
- **`let initialByteSize: Int`** — set during `load(fromContents:ofType:)` from `(contents as? Data)?.count ?? 0`. Preserves walking-skeleton-1 EC-2 large-file behavior.
- **Change tracking via `updateChangeCount(.done)`** — replaces walking-skeleton-1's `markDirty()` no-op undo trick.
- **First-keystroke hook** *(AC-6.2 / AC-6.3 / AC-6.5)*: the text-change handler calls `UntouchedFileTracker.shared.markTouched(url: fileURL)` on the first mutation. For newly-created documents (those that were registered via `CreateNewDocumentFlow`), the first-keystroke handler also calls `LastDocumentStore.shared.record(url: fileURL)` — this is the deferred bookmark-record per AC-6.5 (untouched-and-deleted files do not become the resume target). Subsequent mutations skip both calls.

**UIDocument open/close lifecycle** *(addresses adversarial F-004)*. `UIDocument`'s open and close are asynchronous; they must be sequenced explicitly with the browser's presentDocument and dismiss paths:

- **Open is called before the modal is presented.** In `MarkusDocumentBrowserViewController.presentDocument(at:)` step 2, the flow calls `document.open { success in … }` and only proceeds to steps 3–9 inside the success branch. On `success == false`, the flow consults `document.documentState` to discriminate the error:
  - `.savingError` with a decode failure → `.invalidEncoding` (walking-skeleton-1 EC-4 path).
  - `.editingDisabled` combined with `.savingError` after a download attempt → `.iCloudDownloadFailed` (walking-skeleton-1 EC-13 failure path).
  - File not found (open returns success=false with no state flag, or `NSFileNoSuchFileError`) → `.fileMissing`. This is the open-time race: bookmark resolved successfully, but the file was deleted between resolve and open.
  In all open-failure cases: show the corresponding `DocumentError` alert on the browser (`self`) — do not present the modal. The browser remains visible. For the `.fileMissing` and `.iCloudDownloadFailed` cases triggered by a resume path, the alert's dismiss handler also calls `LastDocumentStore.shared.clear()` so the next launch does not re-attempt the stale bookmark.
- **A brief loading state** is acceptable during open. For typical local files, open is instantaneous and no UI is needed. For iCloud download-pending files, a `ProgressView` is shown on the browser (or via a transient `DocumentLoadingView` overlay reused from walking-skeleton-1 #12).
- **Close is called before the modal dismisses.** The nav-controller delegate's `willShow placeholderVC` callback (component #2 step 6) does, in order:
  1. `document.close { _ in … }` — `UIDocument.close` flushes pending changes through its internal autosave queue before invoking the completion (preserves walking-skeleton-1 AC-4.4 save-before-leave behavior).
  2. Inside the close completion: `UntouchedFileTracker.shared.cleanupIfUntouched(url: document.fileURL)` — deletes the file if untouched. Must come after close so any not-yet-flushed edits are persisted before potential deletion.
  3. `document.fileURL.stopAccessingSecurityScopedResource()` — balances the `startAccessing…` from `LastDocumentStore.resolveLastDocumentURL` (resume path) or `CreateNewDocumentFlow` (create path). Must come last so the deletion in step 2 has the security scope it needs.
  4. The `dismiss(animated: true)` on the nav controller has already been triggered by the `willShow` callback; the close/cleanup/stopAccessing chain runs in parallel with the dismiss animation.

### 6. `UntouchedFileTracker.swift` *(new)*

`@MainActor final class UntouchedFileTracker` — singleton (`static let shared`), injectable for tests.

- **State.** `private var untouchedURLs: Set<URL>`.
- **`registerUntouched(url: URL)`** *(AC-6.1 setup)*: inserts URL into the set. Called by `CreateNewDocumentFlow`.
- **`markTouched(url: URL)`** *(AC-6.2)*: removes URL from the set. Called by `MarkdownDocument` on first keystroke. Idempotent.
- **`isUntouched(url: URL) -> Bool`** *(supports component #8's session-scoped mode decision after F-001 is addressed in requirements)*: returns true iff URL is in the untouched set. Read-only — does not mutate state.
- **`cleanupIfUntouched(url: URL)`** *(AC-6.1, AC-6.4)*: if URL is in the set, attempts `try? FileManager.default.removeItem(at: url)` and removes from the set regardless of delete success. Silent on failure (EC-15 / AC-6.4).
- **`cleanupAllUntouched()`** *(AC-6.5)*: iterates the set and removes each. Called from `ContentView.onChange(of: scenePhase)` on `.background` (component #1). Best-effort; if the app is killed before this fires, a zero-byte stub may remain on disk (EC-16, acceptable per AC-6.4).

### 7. `SaveStatusObserver.swift` *(simplified)*

With the migration to `UIDocument`, the observer can subscribe per-document: `NotificationCenter.default.addObserver(forName: UIDocument.stateChangedNotification, object: document, ...)`. The "global notification + single-document assumption" workaround from walking-skeleton-1 #11 is no longer required.

### 8. `DocumentView.swift` *(small modification)*

- Accepts a `MarkdownDocument` (now a `UIDocument` instance) directly via init.
- The toolbar back chevron is **not** rendered by SwiftUI — the native `backBarButtonItem` on the wrapping `UIHostingController.navigationItem` provides it (component #2). Inside the SwiftUI view, no chevron is rendered.
- **New-document keyboard-up behavior** *(AC-4.4, final wording in third-pass requirements)*: the initial-mode decision in `.onAppear` is **session-provenance-based**, not byte-size-based. The logic is: if `UntouchedFileTracker.shared.isUntouched(url: document.fileURL)` returns true (the document was created via `CreateNewDocumentFlow` in this app session and has not yet received a keystroke), enter `.raw` mode and set the `@FocusState`-bound `TextEditor` to `true` (raising the keyboard, cursor at start). Otherwise, fall back to walking-skeleton-1 EC-2's byte-size default: `initialByteSize >= 500 * 1024` → `.raw` (no auto-focus); else `.rendered`. The byte-size branch is the path taken by browser-picked files, resumed files, share-imported files, and any zero-byte file that survived a force-quit and is being opened via the resume path (EC-23).

### 9. `Info.plist` updates

*Addresses adversarial F-002.*

- **`UIApplicationSupportsMultipleScenes = NO`** — explicit single-scene enforcement. Walking-skeleton-1 used `DocumentGroup` which typically enables multi-scene by default for iPad. This setting must be flipped to `NO` during the migration. Verify on an iPad simulator that App Switcher's "+New Window" action does not appear for Markus.
- Scene configuration: `UIApplicationSceneManifest` → `UISceneConfigurations` → one default config for the application role, with no `UISceneDelegateClassName` (we use SwiftUI scene lifecycle, no UIKit SceneDelegate).
- `UISupportsDocumentBrowser = YES` and `LSSupportsOpeningDocumentsInPlace = YES` (AC-5.4). Walking-skeleton-1 already set these via `DocumentGroup`; verify post-migration.
- UTType document-types entries (the markdown content types) carry over from walking-skeleton-1.

### 10. `PrivacyInfo.xcprivacy`

No new entries required. Walking-skeleton-1's declared categories (`FileTimestamp`, `UserDefaults`, `DiskSpace`) cover this feature's behaviors.

## Project layout

Additions and modifications to walking-skeleton-1's layout:

```
Markus_v3.xcodeproj/
Markus_v3/
  App/
    Markus_v3App.swift              [rewritten — pure SwiftUI App, no AppDelegate]
    ContentView.swift               [new — hosts BrowserHostView + lifecycle modifiers]
    Info.plist                      [updated — UIApplicationSupportsMultipleScenes=NO, no SceneDelegate]
    PrivacyInfo.xcprivacy           [unchanged]
  DocumentBrowser/                  [new directory]
    BrowserHostView.swift           [new — UIViewControllerRepresentable + Coordinator]
    MarkusDocumentBrowserViewController.swift   [new]
    CreateNewDocumentFlow.swift     [new]
    UntitledNameResolver.swift      [new]
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
    DocumentView.swift              [updated — accepts UIDocument, no SwiftUI chevron]
    RenderedView.swift              [unchanged]
    RawEditorView.swift             [unchanged]
    DocumentLoadingView.swift       [unchanged]
    ToastModifier.swift             [unchanged]
Markus_v3Tests/                     (Swift Testing unit tests)
  ... existing walking-skeleton-1 tests, MarkdownDocument tests rewritten ...
  UntitledNameResolverTests.swift   [new — exhaustive collision matrix, no disk]
  LastDocumentStoreTests.swift      [new — bookmark roundtrip with temp files]
  UntouchedFileTrackerTests.swift   [new — register/touch/cleanup semantics]
  CreateNewDocumentFlowTests.swift  [new — directory-fallback + Untitled naming]
  MarkdownDocumentLifecycleTests.swift  [new — UIDocument open/close behavior, F-004 paths]
Markus_v3UITests/                   (XCUITest end-to-end)
  WalkingSkeletonFlowUITests.swift  [updated for new app shell]
  ResumeAndCreateFlowUITests.swift  [new — resume on relaunch, create-from-browser]
Package.resolved
```

## Dependencies

No new external dependencies.

## Contracts and seams

Mapping to declaration.md's Shape, updated for this feature:

| Seam | This-feature realization | Notes |
|---|---|---|
| Document browser entry | `MarkusDocumentBrowserViewController` via `BrowserHostView` representable | Pattern 2 hybrid: SwiftUI App owns the window, UIKit provides the controller |
| File access layer | `LastDocumentStore` (bookmarks via NSUserActivity) + `MarkdownDocument` (UIDocument) + `CreateNewDocumentFlow` + `UntouchedFileTracker` | First-class file lifecycle now exists |
| Document model | `MarkdownDocument` (UIDocument) | Same responsibilities, different base class; lifecycle explicit per F-004 |
| Rendered view | `RenderedView` | Unchanged |
| Raw editor | `RawEditorView` | Unchanged; gains `@FocusState` for keyboard-up on new files |
| Mode switcher | `@State mode: DocumentMode` in `DocumentView` | Initial-mode logic will be revised after F-001 requirements pass |
| Conflict & lifecycle UI | `DocumentError` + alert surface | Reused for EC-12 "couldn't create" error and the open-failure paths in F-004 |

## Build agent must know

- **Pattern 2 app entry — do not introduce a SceneDelegate.** SwiftUI's `App` + `WindowGroup` + `UIViewControllerRepresentable` is the canonical hybrid. Adding a SceneDelegate creates competing scene ownership.
- **Single-scene enforcement is non-negotiable for this feature.** `UIApplicationSupportsMultipleScenes = NO`. If the iPad simulator shows a "+" in App Switcher for Markus, the setting is wrong.
- **Placeholder VC is invisible by design.** Do not give it content. Its only job is to provide a previous-page title for `backBarButtonItem`.
- **UIDocument open before present, close before dismiss.** Sequencing is in component #5's lifecycle subsection. Skipping this produces blank documents on open and lost edits on close.
- **MarkdownDocument migration breaks walking-skeleton-1 tests.** Rewrite `MarkdownDocumentTests.swift` against the new UIDocument lifecycle; keep the behaviors under test (UTF-8 decode failure, initialByteSize, dirty-on-edit, save-to-original-location).
- **Security scope is acquired by `LastDocumentStore.resolveLastDocumentURL()` / `CreateNewDocumentFlow` and released in `UIDocument` close lifecycle.** Forgetting `stopAccessing…` leaks file handles and causes the next resume to fail.
- **`UntouchedFileTracker.registerUntouched(url:)` is called by `CreateNewDocumentFlow` before the URL is returned to the browser.** Otherwise an immediate back-tap leaks a zero-byte file.
- **`LastDocumentStore.record(url:)` for newly-created documents is deferred until first keystroke**, not at creation time. Implementation: `MarkdownDocument`'s first-keystroke hook calls `record` only if the document is in the untouched-tracker set, which is the marker for "newly created this session."
- **`URL.bookmarkData` can throw — wrap in `try?` with a debug log** per component #3's silent-failure policy.
- **All UI work runs on `@MainActor`.** Inherited from walking-skeleton-1.

## Requirements implications

Fourth pass. All four RIs from prior passes are resolved:

- **RI-1** (DocumentGroup → UIDocumentBrowserViewController + ReferenceFileDocument → UIDocument migration) — resolved in second loop; explicitly approved by the user.
- **RI-2** (AC-3.3 edge-swipe mechanism — first revision) — resolved in second loop; superseded by RI-4.
- **RI-3** (zero-byte / new-file mode-default — initial clarification) — resolved in second loop; superseded by adversarial F-001's session-provenance refinement.
- **RI-4** (AC-3.3 edge-swipe mechanism — revert to native `interactivePopGestureRecognizer`) — **resolved this pass**. Requirements AC-3.3 has been rewritten to the proposed text; design component #2's placeholder-VC mechanism produces the native gesture for free.

Adversarial findings F-001 through F-006 are now all `addressed` in adversarial-review.md. Awaiting verification on the next `/t3-adversarial` run.

---

**Architecture stable — no requirements changes flagged.** Requirements ↔ architecture loop has converged. Ready for `/t3-adversarial` re-run to verify the addressed findings; on a clean pass, the feature is ready for `/t3-test-coach` and `/t3-generate-dag`.
