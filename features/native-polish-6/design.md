# Design — Native Polish

*Architecture for `native-polish-6`. Source of truth for intent: `features/native-polish-6/declaration.md`; behavior: `features/native-polish-6/requirements.md`. Every constraint below (NPC-n) is phrased as an observable property of the running system, not a call signature.*

---

## Existing codebase: the seams we attach to

The app's current structure after features 1–5:

- **`BrowserHostController`** (`Host/`) is the `UIDocumentBrowserViewController`-backed scene root. It owns `presentDocument(at:)`, the `ChangeDetector`, and the `MarkdownDocumentSaveBridge`. It already installs a `UIScreenEdgePanGestureRecognizer` on the presented navigation controller's view for the L→R edge-swipe-to-dismiss path (design DC-14), but only on the screen edge — this is the precedent we extend.
- **`DocumentView`** (`Views/DocumentView.swift`) switches between `.rendered` and `.raw` modes, owns the toolbar items, and drives the `NavigationStack` title. Its `.toolbar` block currently shows a "Show rendered" eye-button when in `.raw` mode. No toolbar button exists for sharing or for a swipe-driven transition.
- **`MarkdownEditorTextView`** (`Editor/`) is a `UITextView` subclass. Its `configureAppearance()` currently sets `UIFont.monospacedSystemFont(ofSize: bodySize, weight: .regular)` — a size that adapts with Dynamic Type but uses the system-default monospace, not explicitly SF Mono.
- **`RenderedView`** (`Views/RenderedView.swift`) renders GFM via the `swift-markdown-ui` `Markdown` view (v2.4.1, backed by `swift-cmark`). It currently has no `.textSelection`, no share button, and no swipe gesture recognizer. Its `onTap` closure drives the rendered → raw transition. The `Markdown` view uses its library defaults for typography.
- **`LaunchResumeBranch`** (`Resume/`) calls `host.presentDocument(at:url, animated:false)`. That call fires `didOpenDocument`, which `DocumentOpenObserver` routes into `LastFileStore.recordLastOpened`. Recents registration is not currently performed.

---

## Components and responsibilities

### C0 — MarkdownEditorTextView (raw editor text view)

Uphold: every character displayed or typed in the raw editor is rendered in SF Mono at a size appropriate for prose editing, regardless of text origin (initial load, user typing, paste, programmatic replacement by list-continuation). No portion of the editing surface uses SF Pro or any other typeface. The font is not influenced by the user's Dynamic Type size setting; SF Mono is applied unconditionally for technical legibility (requirement NP-1; OOS-2 exempts it from Dynamic Type).

Today `configureAppearance()` calls `UIFont.monospacedSystemFont(ofSize:weight:)` which resolves to SF Mono on Apple hardware but whose documented contract does not guarantee it. The change specifies `UIFont(name: "SFMono-Regular", size:)` with a fixed prose point size (17 pt is the established iOS body baseline; the final value is implementation latitude within "legible prose size") and falls back to `UIFont.monospacedSystemFont` only if the named font cannot be loaded. This makes the behavioral guarantee — SF Mono — explicit rather than inferred.

The `configureAppearance()` method also sets `typingAttributes` so newly typed text picks up the same font, and `linkTextAttributes` is irrelevant here (the raw editor is plain-text). No other behavior in `MarkdownEditorTextView` changes.

**Behavioral constraint NPC-1:** The raw editor surface never displays body text in SF Pro.

### C1 — RenderedView typography (rendered view body text)

Uphold: the rendered view uses the system default typeface (SF Pro) at Dynamic Type body sizes, so text scales when the user changes their preferred text size. Headings scale proportionally following the standard typographic hierarchy.

The `swift-markdown-ui` `Markdown` view applies its own default theme. To guarantee SF Pro and Dynamic Type rather than relying on library defaults, a `.markdownTheme(.gitHub)` or a custom `Theme` is applied that maps body text to `.body` Dynamic Type style (via `UIFont.preferredFont(forTextStyle: .body)` or SwiftUI's `.font(.body)`), and headings to `.title`, `.title2`, `.title3` respectively. No fixed point sizes are used for body text.

**Behavioral constraint NPC-2:** The rendered view never hard-codes a point size for body text.

**Behavioral constraint NPC-3 (Dynamic Type extremes):** At the "Accessibility XL" Dynamic Type size, body text in the rendered view does not clip, overlap, or produce illegible layout. This is satisfied by using the system `.body` style (which the system itself designed to be safe at all sizes) and by the `ScrollView` wrapper in `RenderedView` already ensuring content is scrollable rather than fixed-height.

### C2 — GFM line-break preprocessor

Uphold: a single newline (`\n`) in raw source (one that is not part of a blank line and not trailing two or more spaces) produces a visible new line in rendered output. A blank line (`\n\n`) produces a paragraph break. Code block content is rendered verbatim without injected line breaks.

CommonMark spec — which `swift-cmark` implements — treats a single `\n` as a soft line break that renders as a space, not a line break. NP-3 requires hard-line-break behavior for every single `\n` in body text. The standard CommonMark mechanism for a hard line break is two trailing spaces before `\n` (or a backslash before `\n`). Injecting two trailing spaces before every bare `\n` in a pre-render pass is one approach, but it must be code-block–aware.

**Design choice:** A lightweight `MarkdownLineBreakNormalizer` transform is applied to the raw source string *before* it is passed to the `Markdown` view in `RenderedView`. This transform:

1. Parses block-level structure using a pass that recognizes fenced code blocks (` ``` ` or `~~~` open/close fences) and HTML blocks only. Indented-code-block detection (4-space / 1-tab) is intentionally excluded: in CommonMark, 4-space-indented text inside a list item is list-continuation body, not a code block, and a naïve indent-based heuristic would misclassify those lines and suppress the required hard-line-break injection inside list items (NP-3.3). Since the app's target user is a prose writer who is unlikely to author indented code blocks, omitting indented-code-block exemption is the correct trade-off. *Addresses adversarial F-001.*
2. Within any recognized fenced code region, leaves content entirely unchanged.
3. Outside code regions: for every `\n` that is not preceded by two or more spaces and is not a blank line (i.e. not `\n\n`), appends two spaces before the `\n` to convert it to a CommonMark hard line break. Single newlines inside list continuation lines are normalized by this step, satisfying NP-3.3.
4. Is a pure function of its input string (no state, no side effects); safe to call on every re-render.

The transform is a standalone struct/function in a new file `Editor/MarkdownLineBreakNormalizer.swift` with a single entry point that takes and returns a `String`. The `RenderedView` calls it on `text` before passing the result to `Markdown(...)`. No change to `MarkdownDocument`, `DocumentView`, or `swift-markdown-ui`.

**Behavioral constraint NPC-4 (code block safety):** A fenced code block (delimited by ` ``` ` or `~~~`) whose interior lines contain single `\n` separators is rendered with exactly the newlines the author wrote — the preprocessor injects nothing inside fence markers. Indented code blocks are not exempted (see design choice above); they are treated as ordinary text, with single newlines normalized to hard line breaks. *Addresses adversarial F-001.*

**Behavioral constraint NPC-5 (inline code):** An inline code span that happens to contain a newline is passed through unchanged; the preprocessor does not inspect or modify inline code span content.

**Behavioral constraint NPC-6 (paragraph breaks preserved):** A blank line (`\n\n` with no intervening content) continues to produce a paragraph break in the rendered view, not a line break. The preprocessor's trailing-space injection applies only to non-blank-line `\n`s.

### C3 — SwipeNavigationCoordinator (swipe gesture wiring)

Uphold: swipe gestures on the raw editor and rendered view trigger the correct mode transitions without conflicting with native iOS gestures (text selection, vertical scroll, horizontal content scroll, system interactive pop).

**Gesture inventory:**

| Surface | Direction | Effect |
|---------|-----------|--------|
| Raw editor | R→L (leading-to-trailing) | Raw → Rendered |
| Raw editor | L→R (trailing-to-leading) | Raw → File browser (dismiss) |
| Rendered view | L→R (trailing-to-leading) | Rendered → Raw |

**Conflict avoidance:**

- The existing `UIScreenEdgePanGestureRecognizer` in `BrowserHostController.installEdgeSwipeDismiss` already handles the L→R edge-swipe-to-browser for the presented navigation controller. For NP-5 (L→R on raw), the design extends or reuses that existing recognizer rather than adding a second competing gesture on the same view. Specifically, the existing edge-pan recognizer is already on the navigation controller's *view*, not on the UITextView — so it fires even when the text view is first responder. NP-5 is therefore already partially addressed by the existing edge recognizer; the design confirms it fires correctly and is consistent with NP-5.2/NP-5.4, requiring no new gesture for the dismiss direction. **Implementation note:** if the existing `UIScreenEdgePanGestureRecognizer` already satisfies NP-5 in all tested scenarios (including keyboard-up state, NP-20), no second recognizer is added for that direction.

- The R→L (raw → rendered) swipe and the L→R (rendered → raw) swipe are new `UIPanGestureRecognizer` instances added to the relevant UIKit views. They must:
  - Require a minimum velocity/translation threshold before they are recognized, so that a short drag (as occurs when extending text selection) does not trigger a mode switch.
  - Implement `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` to allow co-recognition with scroll view pan recognizers, relying on the velocity angle to differentiate: recognizers that have a dominant vertical or small-horizontal component fail gracefully.
  - For the rendered-view L→R swipe (NP-6.4): when the `WKWebView` or `ScrollView` inside `RenderedView` reports a non-zero horizontal scroll offset at the gesture's start location, the pan recognizer fails, yielding to horizontal content scroll.
  - For the raw-editor R→L swipe (NP-4.5 / NP-4.6): the `UITextView` is a scroll view; the pan recognizer should require the UITextView's scroll recognizer to fail (via `require(toFail:)`) before triggering — or alternatively, succeed only when the UITextView reports zero horizontal content offset and the gesture's horizontal component substantially exceeds its vertical component.

**Where gesture recognizers live:** Because `DocumentView` is a SwiftUI view hosted by `UIHostingController`, and because the raw editor (`MarkdownEditorTextView`) and the scroll view in `RenderedView` are UIKit internals, the gesture wiring is most reliably done in UIKit rather than in SwiftUI gesture modifiers. Two approaches are viable:

1. Add `UIGestureRecognizer` instances directly onto the `UIHostingController`'s `view` (which wraps `DocumentView`), pointing their actions at `DocumentView`'s mode-switch mechanism via a callback. This keeps the recognizer above the text view and scroll view in hit-test order.
2. Wire SwiftUI `.simultaneousGesture` or `.highPriorityGesture` on `RenderedView` and `RawEditorView` with a `DragGesture` configured for minimum distance and angle discrimination.

Approach 2 (SwiftUI-side `DragGesture`) is preferred because `RenderedView` and `RawEditorView` are already SwiftUI views and because `DragGesture` with `.minimumDistance` and explicit direction checking (comparing `translation.width` vs `translation.height` magnitudes) maps cleanly to the conflict-avoidance constraints. The gesture is `.simultaneousGesture` (not `.gesture`) so it does not preempt scroll. For the raw editor, the SwiftUI gesture wraps the `MarkdownTextViewBridge`, which wraps the `UITextView`; the `.simultaneousGesture` modifier can detect the drag and cancel itself if it is not sufficiently horizontal or sufficiently far from the start.

**Callback contract:** `DocumentView` exposes the mode-switch logic in its existing `switchTo(_:target:)` method. Gesture callbacks call `switchTo(.raw, target: .rendered)` (R→L on raw) and `switchTo(.rendered, target: .raw)` (L→R on rendered). For the L→R-on-raw→browser path, the callback is the existing `onBack` closure.

**Behavioral constraint NPC-7 (swipe does not lose edits):** Swiping from raw to rendered triggers `triggerSave()` (same as the toolbar eye button), ensuring the buffer is submitted for autosave. The swipe does not silently discard the buffer.

**Behavioral constraint NPC-8 (keyboard dismissal on swipe):** Swiping R→L on the raw editor while the keyboard is up (NP-20) results in the keyboard dismissing as part of the animated mode transition. The transition animation naturally removes the raw editor from the screen, which causes the keyboard to resign. The gesture must not deadlock against the keyboard's gesture recognizers. Testing this path is required before the task is marked complete.

**Behavioral constraint NPC-9 (no double-gesture conflict):** When the system interactive-pop gesture (the existing `UIScreenEdgePanGestureRecognizer`) fires on L→R from the raw editor, the SwiftUI `DragGesture` on `RawEditorView` does not also fire. Because the `UIScreenEdgePanGestureRecognizer` starts from the screen edge (first 20 pt), and the `DragGesture` covers the full view, either: (a) `DragGesture` is configured to require the recognizer to fail (achievable by wrapping in `UIViewRepresentable` with a `require(toFail:)` call), or (b) the design relies on the fact that the existing edge recognizer fires first (being more specific), causing the `DragGesture` to cancel. The chosen implementation must verify that only one fires.

**Behavioral constraint NPC-22 (screen-edge priority on rendered view):** When a L→R drag on the rendered view begins near the leading screen edge (within the `UIScreenEdgePanGestureRecognizer` recognition zone, approximately the first 20 pt), the `UIScreenEdgePanGestureRecognizer` takes priority over the SwiftUI `DragGesture` — so a near-edge L→R drag on the rendered view navigates to the file browser, not to raw mode. A L→R drag starting from outside the edge zone navigates to raw mode as intended. *Addresses adversarial F-004.*

### C4 — RenderedView text selection (long-press system text menu)

Uphold: a long press on text in the rendered view presents the standard iOS system text menu containing at minimum Copy and Select All. The menu is the system control, not a custom action sheet. Long-pressing a hyperlink does not inadvertently trigger the text menu.

`RenderedView` uses the `swift-markdown-ui` `Markdown` view, which renders inside a SwiftUI `ScrollView`. The rendered content is pure SwiftUI (via `TextRenderer` in the library), not `WKWebView`. SwiftUI `Text` views do not expose text selection by default; text selection in SwiftUI requires `.textSelection(.enabled)` on the text content.

Applying `.textSelection(.enabled)` to the `Markdown` view (or to its containing `ScrollView`) enables the system long-press → select → Copy / Select All flow natively, via SwiftUI's built-in text selection mechanism, which uses the standard iOS callout menu. This satisfies NP-7.1 through NP-7.4 and NP-7.7 without any custom gesture recognizer.

For NP-7.5 (link conflict): `swift-markdown-ui` renders links via SwiftUI `Text` with `Link` or via `openURL`; the existing `RenderedView` already intercepts the `openURL` environment to redirect link taps to `onTap`. `.textSelection(.enabled)` and link taps coexist via UIKit's standard gesture precedence for long-press (which initiates text selection) vs. tap (which fires the link). This is standard iOS behavior and requires no additional disambiguation.

For NP-7.6 (empty content): if the document is empty, the `Markdown` view renders no text. `.textSelection(.enabled)` on an empty `Text` produces no selection UI and no crash, by the same mechanism as any empty SwiftUI `Text` with text selection enabled.

**Behavioral constraint NPC-10:** `.textSelection(.enabled)` is applied at the `Markdown(text)` level (or its container), not to the outermost `ScrollView` that includes layout geometry readers, so that only the markdown text content is selectable, not incidental geometry proxies.

### C5 — Share button in rendered view navigation bar

Uphold: the rendered view navigation bar contains a `square.and.arrow.up` share button that, when tapped, presents a `UIActivityViewController` with the file's on-disk URL. The share always uses the last-saved disk copy; unsaved in-memory edits are neither force-saved nor lost. The app does not crash if the file has been deleted.

**Where it lives:** The share button is added to `DocumentView`'s `.toolbar` block, conditioned on `mode == .rendered` (symmetric with the existing "Show rendered" eye button being conditioned on `mode == .raw`). It is placed in `.topBarTrailing`.

**The activity item:** The `UIActivityViewController` is initialized with `[fileURL]` (the `URL?` passed into `DocumentView`) as the activity items. This is the on-disk file URL; it shares the file as it exists on disk at the moment of tapping. The in-memory buffer is not consulted (NP-8.4, NP-8.5).

**Deleted-file guard (NP-8.6):** Before presenting, the share handler checks `FileManager.default.fileExists(atPath: fileURL.path)`. If the file does not exist, the handler silently returns without presenting the `UIActivityViewController`. This is a no-op from the user's perspective — the share sheet simply does not appear — and the editing session is uninterrupted.

**`UIActivityViewController` presentation from SwiftUI:** SwiftUI does not have a native first-class `UIActivityViewController` wrapper in all supported iOS versions. The presentation is performed via a `UIViewControllerRepresentable` trampoline or, on iOS 16+, via `ShareLink`. Because the app targets iOS 16+ (using `ScrollPosition` API present only in iOS 17+, per `RenderedView`), `ShareLink(item: fileURL)` is the idiomatic choice — it uses `transferRepresentation` via `Transferable` for `URL`, which on iOS 16+ presents the system share sheet. However, `ShareLink` shares a copy-by-value `URL`; for iPad popover anchoring (NP-8.8), `ShareLink` handles anchor presentation automatically when placed in a `ToolbarItem`. This satisfies all NP-8 criteria.

**If `ShareLink` cannot guarantee disk-file-only sharing** (i.e., if `ShareLink(item: fileURL)` opens the file via a coordinator and reads the in-memory buffer rather than the disk file), the implementation falls back to a `UIActivityViewController` presented via a `UIViewControllerRepresentable` sheet that is presented imperatively on button tap. The distinction is detectable in testing: share the file with unsaved edits active, then inspect the shared content. This is an implementation-latitude choice; the behavioral constraint is NP-8.4/NP-8.5.

**Behavioral constraint NPC-11:** The share button is not present in the raw editor's toolbar (`mode == .raw`).

**Behavioral constraint NPC-12:** Tapping share when `fileURL` is `nil` (which should not occur in normal operation, since `DocumentView` receives a URL when opened from the host) is a no-op. The guard covers both `nil` URL and missing file.

### C6 — HIG semantic colors and `.bar` material

Uphold: no color value in the app's UI is hard-coded. All text, background, and icon colors are HIG semantic system colors. Navigation bars and toolbars use the standard `.bar` material.

**Audit scope:** The components modified by this feature — `MarkdownEditorTextView`, `RenderedView`, `DocumentView`, and the conflict/deletion surfaces in `DetectorSurfaces` — are all audited for hard-coded color values.

Current state:
- `MarkdownEditorTextView.configureAppearance()` sets only the font; background and text colors are inherited from the system `UITextView` defaults (`.label` and `.systemBackground`), so no change is needed for colors in the text view.
- `RenderedView` does not set explicit colors; the `Markdown` view's default theme uses system semantic colors. The `Markdown` typography change in C1 should continue to use `.label` for body text.
- `DocumentView`'s toolbar buttons use the default `.tint` / `.accentColor` — semantic.
- `DetectorSurfaces` applies `.thinMaterial` to the deletion banner background, which is the `.bar`-family material (already correct).

**Navigation bar `.bar` material (NP-9.2, NP-9.5):** SwiftUI's `NavigationStack` / `UINavigationController` uses an opaque background for the navigation bar by default. The `.bar` material (blur over content) is achieved by setting the `UINavigationBar` appearance. This is best done at the `UINavigationController` creation point in `BrowserHostController.presentDocument`, where the navigation controller is instantiated: `nav.navigationBar.scrollEdgeAppearance` and `nav.navigationBar.standardAppearance` should use `UINavigationBarAppearance()` configured with `.configureWithDefaultBackground()` (which gives the `.bar` blur). Alternatively, a SwiftUI `.toolbarBackground(.bar, for: .navigationBar)` modifier on `DocumentView` achieves the same via the SwiftUI toolbar API. The SwiftUI modifier is preferred as it keeps the configuration colocated with `DocumentView`.

**Behavioral constraint NPC-13:** After switching between Light and Dark Mode, the navigation bar and toolbar remain visually correct and no text or icon becomes invisible.

**Behavioral constraint NPC-14:** With Increase Contrast enabled, all text remains legible (satisfied automatically by using `.label` and other semantic colors, which have high-contrast variants built in).

### C7 — Recents registration after bookmark-based open

Uphold: every file opened via a security-scoped bookmark (i.e., via `LaunchResumeBranch`) registers with the document browser's Recents section. Recents reflect access order. Failure to register does not crash the app or surface an error.

**Current state:** `LaunchResumeBranch.resume(into:)` calls `host.presentDocument(at: url, animated: false)`. This fires `didOpenDocument`, which calls `LastFileStore.recordLastOpened`. The `UIDocumentBrowserViewController` tracks Recents for files opened *through its own delegate callbacks* (`didPickDocumentsAt`, `didImportDocumentAt`) but does not automatically register files presented programmatically via `present(_:animated:)`.

**Registration mechanism:** `UIDocumentBrowserViewController` exposes `recentDocumentURLs` — a read-only property — but does not have a public `registerRecentDocument(at:)` method. The correct UIKit API for registering a URL with the document browser's Recents is `UIDocumentBrowserViewController`'s `documentBrowser(_:applicationActivitiesForDocumentURLs:)` delegate (which is about activities, not registration), and the `NSDocumentInteractionController` registration path, which is also not directly applicable.

The correct mechanism is `NSFileCoordinator` or, more directly, the fact that iOS tracks "recent documents" via the `NSMetadataQuery` / Spotlight index only for files opened through the system `UIDocumentBrowserViewController` delegate callbacks. For programmatic opens, the canonical Apple mechanism to register a document as recently used is to call `(browserViewController as UIDocumentBrowserViewController).importDocument(at: url, nextToDocumentAt: url, mode: .move, completionHandler:)` — which is not appropriate here.

After research, the correct API is `UIDocumentBrowserViewController`'s `revealDocument(at:importIfNeeded:completion:)` — but this is also a reveal/import function, not a pure Recents registration.

**The actual API:** On iOS 13+, `NSDocumentController` is macOS-only. The iOS mechanism for "tell the document browser this file was recently opened" is implicit in `UIDocument` lifecycle, but the app does not use `UIDocument`. For apps using `UIDocumentBrowserViewController` without `UIDocument`, the Recents section is populated via `UIDocumentBrowserViewController.recentDocumentURLs` which is populated when the browser itself performs the open. For programmatic opens, the mechanism is to call `applicationActivities` or to rely on `NSMetadataQuery`-based Spotlight indexing.

**Practical resolution:** The most reliable mechanism is to call `(host as UIDocumentBrowserViewController).recentDocumentURLs` — this is read-only. Apple's documentation for `UIDocumentBrowserViewController` states that the system tracks recent files via `NSMetadataQuery`/iCloud metadata; for security-scoped external files, the browser's Recents are populated by the system when the file is *accessed through the security scope*, not merely when it is presented programmatically. The act of calling `url.startAccessingSecurityScopedResource()` (which `BrowserHostController.loadMarkdownDocument` already does) combined with a `UIDocument`-based open is what triggers the system Recents update.

Since the app does not use `UIDocument`, and Apple has not documented a public API for non-UIDocument apps to explicitly register Recents, the design uses the closest available mechanism: after a successful bookmark-based open, call `NSWorkspace` — no, that is macOS. On iOS, the approach is:

- Call `UIDocumentBrowserViewController`'s `importDocument(at:nextToDocumentAt:mode:completionHandler:)` with `.copy` mode pointing at the same URL — this is wrong (it copies).

After careful analysis: the correct iOS API is to use `UIDocumentBrowserViewController`'s delegate method that is called by the system when it wants to open a document. For programmatic opens, the standard pattern recommended in WWDC sessions is to call `(controller as UIDocumentBrowserViewController).importDocument(at: url, nextToDocumentAt: url, mode: .move, completionHandler:)` — also not appropriate.

**Final resolution for NP-10:** The available public API for registering a file with `UIDocumentBrowserViewController` Recents outside the delegate-open path is `UIDocumentBrowserViewController`'s `revealDocument(at:importIfNeeded:completion:)`. However, this is a reveal-and-potentially-import call, not a pure registration.

The design therefore uses the following approach: a new method `RecentsRegistrar.register(url:in:)` is added. It wraps a `UIDocumentBrowserViewController` method call to register the URL. The concrete API it uses is determined at build time by testing which of these mechanisms correctly populates Recents without side effects:
1. `host.revealDocument(at: url, importIfNeeded: false) { _, _ in }` — reveals without import for in-place files.
2. Direct filesystem access: opening the file via security scope and immediately closing it, which signals to the OS that the file was recently accessed and may update Spotlight/Recents.
3. `NSFileCoordinator` read — similarly signals access.

If no public API reliably registers Recents for programmatic opens, the design notes this as a build deviation: the requirement NP-10 is correct and important, but its implementation may require a UIKit trick that is verified at build time rather than specified at design time.

**Behavioral constraint NPC-15:** Recents registration is attempted on every bookmark-based open, including when the document browser is not the active view controller (NP-10.5). The call is made from `BrowserHostController.presentDocument(at:)` (or from `LaunchResumeBranch` after a successful present), which always has access to the `BrowserHostController` instance regardless of whether it is currently visible.

**Behavioral constraint NPC-16:** A registration failure (whatever API is used) is caught as a no-op — the file still opens, the user sees no error, and the session is unaffected (NP-10.6).

**Behavioral constraint NPC-17:** Files opened via the browser's own delegate callbacks already populate Recents via the system mechanism and must not be double-registered or disrupted (NP-10.3). The registration call is conditioned on the open path: only `presentDocument` calls that originate from `LaunchResumeBranch` (bookmark-based) trigger the registration step.

---

## Seam relationships

**C0 (MarkdownEditorTextView) ↔ MarkdownTextViewBridge / RawEditorView.** The font change is entirely internal to `MarkdownEditorTextView.configureAppearance()`. `MarkdownTextViewBridge` constructs the text view and sets `tv.text`; since font is set in `init` and applies to all text, no change to the bridge's `makeUIView` or `updateUIView` is needed. The existing list-continuation path in the coordinator also receives the correct font because it inserts text via `UITextView.replace(_:withText:)`, which inherits the current typing attributes.

**C1 (typography) ↔ RenderedView.** The `Markdown` view call site in `RenderedView.body` adds a `.markdownTheme` or `.environment` modifier after the existing `Markdown(text)` call. The `pendingScrollAnchor` logic, `scrollPosition`, and `onTapGesture` are unaffected.

**C2 (MarkdownLineBreakNormalizer) ↔ RenderedView.** The `text` parameter passed to `Markdown(...)` is replaced with `MarkdownLineBreakNormalizer.normalize(text)`. The `RenderedView` struct gains a dependency on the normalizer. The normalizer is a pure function; it is safe to call on every SwiftUI render pass. `DocumentView` passes `document.text` to `RenderedView.text`; the normalizer runs inside `RenderedView`, not at the `DocumentView` level, so `DocumentView`'s `switchTo` and autosave logic remain unaware of the normalization.

**C3 (SwipeNavigationCoordinator) ↔ DocumentView / RawEditorView / RenderedView.** Mode-switch swipe gestures are added to `RawEditorView` (R→L) and `RenderedView` (L→R) as SwiftUI `.simultaneousGesture(DragGesture(...))` modifiers. The `onEnded` handler of each gesture checks translation direction (|width| > |height| and width exceeds threshold) and calls back into `DocumentView`'s mode-switch logic via closures passed at the call site. `DocumentView.body` passes an `onSwipeToRendered` closure to `RawEditorView` and an `onSwipeToRaw` closure to `RenderedView`. These closures call the existing `switchTo` / `triggerSave` logic — no duplication. The L→R-on-raw-to-browser swipe is handled by the existing `UIScreenEdgePanGestureRecognizer` in `BrowserHostController`; no change is needed there unless testing reveals it does not fire reliably with the keyboard up (NP-20 scenario).

**C4 (text selection) ↔ RenderedView.** `.textSelection(.enabled)` is added as a modifier on `Markdown(text)` (or its enclosing view). No other component is affected. The existing `onTapGesture` on the outer `ScrollView` continues to function; the text selection system gesture (long-press) is distinct from the tap.

**C5 (share button) ↔ DocumentView.** The share button is a new `ToolbarItem` in `DocumentView`'s `.toolbar` block, conditioned on `mode == .rendered`. It reads `fileURL` (already available in `DocumentView`'s stored property). No new state is added; the `ShareLink` or imperative `UIActivityViewController` presentation is self-contained. `MarkdownDocument` and `MarkdownDocumentSaveBridge` are not touched.

**C6 (colors + material) ↔ DocumentView / BrowserHostController.** The SwiftUI `.toolbarBackground(.visible, for: .navigationBar)` and `.toolbarColorScheme` modifiers, or equivalently a `UINavigationBarAppearance` configuration in `BrowserHostController.presentDocument`, ensure the `.bar` material. The audit of hard-coded colors in `DetectorSurfaces` and elsewhere is a read-only verification; no structural changes are expected.

**C7 (Recents) ↔ BrowserHostController / LaunchResumeBranch.** `BrowserHostController.presentDocument(at:)` is the single call site for all programmatic document opens. A `RecentsRegistrar` (new type, `Resume/RecentsRegistrar.swift`) is added whose `register(url:in:)` method is called from `presentDocument` when `animated == false` (the resume-path signal) or, more precisely, when the call originates from `LaunchResumeBranch`. The simplest discriminator is a boolean parameter `isResumeOpen: Bool = false` added to `presentDocument`; `LaunchResumeBranch.resume(into:)` passes `true`. `RecentsRegistrar` holds a weak reference to the `BrowserHostController` and calls the chosen Recents API (determined at build time, per NPC-15 / NPC-16).

---

## Behavioral constraints (full list)

**NPC-1** — The raw editor never displays any portion of its text in SF Pro. (NP-1.1, NP-1.4)

**NPC-2** — The rendered view's body text scales with the user's Dynamic Type setting; no fixed point size is used for body text. (NP-2.1, NP-2.3)

**NPC-3** — At Accessibility XL Dynamic Type, the rendered view does not clip, overlap, or produce illegible layout. (NP-21)

**NPC-4** — Fenced code block content is rendered verbatim; no additional line breaks are injected by the preprocessor inside fenced code regions (` ``` ` or `~~~` delimiters). Indented code blocks are not exempted — single newlines inside indented text are normalized to hard line breaks, consistent with list-continuation behavior. (NP-3.4, NP-16) *Addresses adversarial F-001.*

**NPC-5** — Inline code span content is untouched by the preprocessor. (NP-3.5, NP-17)

**NPC-6** — A blank line in raw source produces a paragraph break (not a line break) in rendered output. (NP-3.2)

**NPC-7** — Swiping from raw to rendered submits the buffer for autosave (same as the existing toolbar button), preserving unsaved edits. (NP-4.3)

**NPC-8** — When the keyboard is up in the raw editor, a R→L swipe triggers the transition without deadlock; the keyboard dismisses as part of the transition. (NP-20)

**NPC-9** — On the raw editor, only one gesture recognizer fires per swipe; the SwiftUI DragGesture and the UIScreenEdgePanGestureRecognizer do not both trigger for the same L→R gesture. (NP-5.4)

**NPC-10** — `.textSelection(.enabled)` is applied to the markdown content, not to the layout geometry readers or outer scroll view. (NP-7.1)

**NPC-11** — The share button is absent from the raw editor's toolbar. (NP-8.7)

**NPC-12** — Tapping share when the file does not exist on disk produces no crash; the share sheet simply does not present. (NP-8.6, NP-14)

**NPC-13** — Switching between Light and Dark Mode does not produce invisible text or icons. (NP-9.3)

**NPC-14** — With Increase Contrast enabled, all UI text remains legible. (NP-9.4)

**NPC-15** — Recents registration is attempted on every bookmark-based open, even when the document browser is not the active view controller. (NP-10.4, NP-10.5, NP-18)

**NPC-16** — A Recents registration failure does not crash the app, surface an error, or prevent the file from opening. (NP-10.6)

**NPC-17** — Files opened via the browser's own delegate callbacks continue to populate Recents via the system mechanism, unchanged. (NP-10.3)

**NPC-18** — A swipe gesture on the raw editor that has a dominant vertical component (scroll) does not trigger a mode switch. (NP-4.6, NP-5.6)

**NPC-19** — A swipe gesture on the rendered view that occurs at a horizontally-scrollable content position (e.g., a wide code block) yields to horizontal content scroll rather than triggering a mode switch. (NP-6.4, NP-11)

**NPC-20** — A horizontal drag gesture on the raw editor that the system text engine interprets as selection-extension does not simultaneously trigger a mode switch (minimum velocity / translation distance threshold enforced). (NP-4.5, NP-5.5, NP-12)

**NPC-21** — If the document browser is not in the navigation stack when L→R fires (NP-19), the app does not crash; the swipe is a no-op or navigates to the nearest valid parent.

**NPC-22** — A L→R drag on the rendered view that begins within the leading screen-edge zone (approx. first 20 pt) is claimed by the `UIScreenEdgePanGestureRecognizer` (navigating to the file browser), not by the SwiftUI `DragGesture` (raw mode). The `DragGesture` fires only for drags starting outside the edge zone. (NP-6.5) *Addresses adversarial F-004.*

---

## Implementation notes (not behavioral constraints)

- `MarkdownLineBreakNormalizer` is a new file in `Editor/`. Its single entry point takes and returns `String`. It is unit-tested as a pure function against the cases in NP-3.1–NP-3.5 and NP-16/NP-17.
- `RecentsRegistrar` is a new file in `Resume/`. It is intentionally thin; its implementation details are resolved at build time by empirical testing of which UIKit API correctly populates Recents for programmatic opens without side effects.
- No changes to `MarkdownDocument`, `AutosaveCoordinator`, `ChangeDetector`, or any `ExternalChange/` component.
- The hard seam rule from prior features applies: `DocumentView`'s rendering, autosave, mode-switch, and save-back paths are not structurally altered. Mode-switch swipes call the same `switchTo` method the toolbar button already calls.

---

## Requirements change assessment

**NP-10 implementation gap:** NP-10.1/NP-10.2 require reliable Recents registration for bookmark-based opens. Public UIKit APIs for non-`UIDocument` apps to register Recents with `UIDocumentBrowserViewController` are not explicitly documented. The design identifies `revealDocument(at:importIfNeeded:completion:)` and security-scoped access as candidate mechanisms. If empirical testing at build time confirms no public API reliably updates Recents without importing or moving the file, NP-10 may need to be narrowed to a best-effort statement ("Recents registration is attempted via the best available mechanism; behavior depends on OS Recents indexing"). This is flagged as a potential requirements refinement, not a requirements change at this stage. No requirement text needs to change prior to the build step; the builder should note the finding.

---

Architecture stable — no requirements changes flagged
