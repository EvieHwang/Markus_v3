# Adversarial Review: resume-and-create-2

*Review based on requirements.md + design.md at commit `fef48d2`. No prior adversarial review exists for this feature; this is the first pass. No `Reuses pattern:` markers in design.md, so all surfaces received full-lens scrutiny.*

## Open findings

### F-001 — Zero-byte mode-default is ambiguous between "just created" and "any zero-byte file on disk"
- **Severity:** MEDIUM
- **Lens:** Integrity / Coverage
- **Finding.** Requirements AC-4.4 and EC-23 give conflicting guidance for the same file state:
  - **AC-4.4** says the zero-byte case overrides walking-skeleton-1 EC-2's mode-from-byte-size rule and opens in raw mode with keyboard active, "regardless of byte size."
  - **EC-23** says: "User creates a new file, app dies before any save. The new file (zero bytes) exists on disk… On next launch, resume attempts to open it; it **opens to an empty rendered view**, then the user is in the normal open-file flow."
  Design component #8 implements this in byte-size terms — *any* zero-byte document opened by `DocumentView` is forced to raw + focus. So the resumed zero-byte file would open in raw mode (matching the design + AC-4.4 byte-size reading) but contradicting EC-23's "empty rendered view."

  The intended semantics is probably session-scoped — "files created **this session** via the create flow open in raw + keyboard; resumed zero-byte files follow the normal mode-from-byte-size default" — but the requirements + design currently encode the byte-size reading. A build agent reading the design will produce one behavior; a test author reading EC-23 will assert the other.
- **Recommended action:** `t3-requirements` — rewrite AC-4.4 to make the trigger explicitly "newly created via the create flow this session," not "byte size = 0." Then design component #8 follows with a session-flag check (e.g., consult `UntouchedFileTracker.isUntouched(url:)` to decide the initial mode) rather than a byte-size check.
- **Status:** `open`

### F-002 — Multi-scene not explicitly disabled despite "single-scene only" being out-of-scope
- **Severity:** MEDIUM
- **Lens:** Scope drift / Failure modes
- **Finding.** The feature declaration's Out of scope section says: "iPad multi-window / multi-scene state restoration — single-scene only for now." But the design introduces a SceneDelegate without specifying `UIApplicationSupportsMultipleScenes = NO` in `Info.plist`. Walking-skeleton-1 used SwiftUI `DocumentGroup`, which typically enables multi-scene by default for iPad. If that Info.plist setting is inherited unchanged into this feature, the migration to UIKit scene delegate silently keeps multi-scene enabled.

  Concrete failure mode: on iPad, two scenes (two app windows) racing on the single `LastDocumentStore.bookmarkKey` UserDefault. Scene A persists URL_A → Scene B persists URL_B → next cold launch resumes URL_B regardless of which scene the user thought was "the one." The bookmark is a per-app global, not per-scene, which is wrong under multi-scene.
- **Recommended action:** `t3-architecture` — add an explicit Info.plist directive (`UIApplicationSupportsMultipleScenes = NO`) to design.md component #9, and add a one-line build-agent note that confirms the setting must be flipped if walking-skeleton-1 left it true.
- **Status:** `open`

### F-003 — App-entry pattern is hand-wavy; risks two competing root scenes
- **Severity:** MEDIUM
- **Lens:** Integrity
- **Finding.** Design component #1 specifies `Markus_v3App` as a SwiftUI `App` with `WindowGroup { EmptyView() }` plus `@UIApplicationDelegateAdaptor(AppDelegate.self)`, and says "the real UI is driven by the UIKit scene delegate." This conflates two app-shell patterns. SwiftUI's `App` with a `WindowGroup` creates and owns the scene; a separate UIKit `UISceneDelegate` cannot also own that scene without coordination. The likely outcomes if the build agent implements this literally:
  - SwiftUI's empty `WindowGroup` mounts a blank window as the actual scene root, and the UIKit `SceneDelegate` is never given a window to populate. App ships with a blank screen.
  - Or: scene config in `Info.plist` directs UIKit `SceneDelegate` to own the scene, and the SwiftUI `WindowGroup` is dead code that confuses readers.

  Three canonical hybrid patterns exist:
  1. **Pure UIKit lifecycle.** `@main class AppDelegate: UIResponder, UIApplicationDelegate` (no SwiftUI App), UIKit scene delegate owns the window, SwiftUI views are hosted via `UIHostingController` inside UIKit view controllers.
  2. **SwiftUI App owns the window; UIKit provides view controllers.** `@main struct App: App { var body: some Scene { WindowGroup { BrowserHostView() } } }` where `BrowserHostView` is a `UIViewControllerRepresentable` wrapping a `UINavigationController` whose root is `MarkusDocumentBrowserViewController`. No SceneDelegate at all (or only a minimal one for state restoration hooks).
  3. **SwiftUI App with custom Scene type that delegates to UIKit.** More complex; rarely worth it for this case.

  Design must pick one. The current "WindowGroup { EmptyView() } + SceneDelegate driving UIKit" is none of the three.
- **Recommended action:** `t3-architecture` — choose pattern 1 or pattern 2 explicitly. My read: **pattern 2** is the cleanest for this app because it keeps `@main App` SwiftUI-flavored, hosts the browser as a representable, and lets `NSUserActivity` restoration flow through SwiftUI's `.onContinueUserActivity` and `.handlesExternalEvents` modifiers without a separate SceneDelegate. The "resume directly into a document on cold launch" path then becomes: on `body` evaluation, consult `LastDocumentStore.resolveLastDocumentURL()`; if non-nil, the representable triggers `browser.presentDocument(at:)` in its `updateUIViewController` or coordinator. Pattern 1 is also viable if pattern 2 turns out to have a corner case I'm missing.
- **Status:** `open`

### F-004 — UIDocument async open/close lifecycle is unspecified
- **Severity:** MEDIUM
- **Lens:** Coverage / Failure modes
- **Finding.** `UIDocument` requires `open(completionHandler:)` to be called before its contents are usable, and `close(completionHandler:)` to flush state before deallocation. Both are asynchronous. Design component #5 (`MarkdownDocument` migrated to `UIDocument`) describes the `contents(forType:)`/`load(fromContents:ofType:)` methods but never describes the open/close sequencing relative to the SwiftUI `DocumentView` lifecycle.

  Specific gaps the build agent could miss:
  - When does `document.open(completionHandler:)` get called — in `MarkusDocumentBrowserViewController.presentDocument(at:)` before wrapping in `UIHostingController`, or inside `DocumentView.onAppear`? If after the hosting controller is presented, the SwiftUI view tries to bind to `document.text` before `load(fromContents:)` has populated it. Visible failure: brief blank text editor before content appears.
  - What happens on `open` failure? Causes include: file deleted between bookmark resolution and open (race window EC-3 doesn't cover); EC-4 invalid-UTF-8 from walking-skeleton-1; iCloud download failure mid-open. Design component #2 says "On document open success, calls `LastDocumentStore.shared.record(url:)`" but never says what the failure path does. The user could see the zoom transition complete into a blank document with no error.
  - When does `document.close(completionHandler:)` get called on dismiss? The back-chevron and edge-swipe handlers in component #2 only mention "dismisses the modal." Forgetting `close` means changes may not flush and `stopAccessingSecurityScopedResource()` leaks.
- **Recommended action:** `t3-architecture` — add a `UIDocument` lifecycle subsection to component #5 spelling out: open is called in `presentDocument(at:)` before the hosting controller is shown (with a brief loading spinner if open is slow); on open failure, dismiss the modal and surface the existing `DocumentError` alert (`.invalidEncoding`, `.iCloudDownloadFailed`, or `.fileMissing`); on dismiss, call `close(completionHandler:)` and then `cleanupIfUntouched` and `stopAccessingSecurityScopedResource()` in that order. Then walking-skeleton-1's EC-4 / EC-13 behaviors will continue to apply through this feature's flow.
- **Status:** `open`

### F-005 — "Back chevron + 'Documents' label" is hard to render natively for a presented (not pushed) modal
- **Severity:** MEDIUM
- **Lens:** Standards compliance (HIG)
- **Finding.** Requirements AC-3.1 says "the standard back chevron in the top-left, labeled per system convention (chevron alone, or chevron + previous-screen title — whatever `UINavigationController` produces by default)." But because the document is **presented** modally (with the system zoom transition) rather than **pushed** onto a navigation stack, there is no `backBarButtonItem` to render. Design component #2 prescribes a "custom left bar button item" — but `UIBarButtonItem` does not natively render as the chevron-plus-previous-title compound that AC-3.1 references. Options:
  - **(a)** Use a custom `UIBarButtonItem(image: chevronImage, ...)` with title "Documents" — visible difference from a real `backBarButtonItem` in chevron-text spacing, font weight, and color tint. Diverges from Files / Pages / Numbers visually.
  - **(b)** Construct the presented stack as `[placeholderVC, documentVC]` so `documentVC` has a real `backBarButtonItem` whose title is the placeholder's title. Hacky but produces a native chevron.
  - **(c)** Accept just the chevron with no title (which is what some Apple apps do, e.g., Photos).
- **Recommended action:** `t3-architecture` to pick one of (a)/(b)/(c) and document it in component #2. If (a), AC-3.1 should be revised to accept the visual divergence. If (b), design adds the placeholder-stack mechanism. If (c), AC-3.1 should be revised to "chevron only."
- **Status:** `open`

### F-006 — `LastDocumentStore.record(url:)` failure path unspecified
- **Severity:** LOW
- **Lens:** Failure modes
- **Finding.** Design component #3 says `record(url:)` "creates a bookmark with `URL.bookmarkData(...)` and writes it to UserDefaults." `URL.bookmarkData` can throw — for example, on URLs that aren't bookmarkable (some share-extension inbox URLs, some sandboxed temp paths), or if security scope cannot be opened. Design doesn't say what happens on throw. The likely silent-failure mode: the bookmark is never persisted, so the next launch falls through to the browser (per AC-2.2). The user sees the document fine in the current session but cannot understand why "resume" didn't work next time. This is consistent with "no UI for stale-bookmark cases" in spirit, but the user's mental model breaks because the file *was* opened successfully.
- **Recommended action:** Either `t3-requirements` (add an EC documenting that bookmark-record failures are silent and resume falls through next launch) or `t3-architecture` (specify the catch behavior in component #3, even if it's `try? bookmarkData()` and a debug log). Build agent will otherwise probably implement `try!` and crash on a corner-case URL.
- **Location:** design.md component #3 (`LastDocumentStore.record(url:)`); requirements.md edge cases section.
- **Status:** `open`

## Resolved findings

*None yet — first review.*
