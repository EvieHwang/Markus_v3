# Build deviations — resume-and-create-2

Records concrete deviations from `design.md` and the test-file shape in
`features/resume-and-create-2/tests/` made during the build. The canonical
behavioral spec (`requirements.md`) is unchanged.

---

## D-001 — Unit-test file split per component (Wave 1)

**What changed.** The canonical unit-test spec at
`features/resume-and-create-2/tests/unit/ResumeAndCreateTests.swift` bundles
four suites (`NameProbeTests`, `LocalDocumentsFallbackTests`,
`CreateTargetResolverTests`, `LastFileStoreTests`) into one file. Because the
file is copied/adapted into the `Markus_v3Tests` Xcode target (the synchronized
folder pattern used for actual test execution; the `features/` tree is *not* a
target), shipping it as a single file in Wave 1 would force a compile error:
`CreateTargetResolverTests` references `CreateTargetResolver` and
`LastDirectoryProviding`, which land in Wave 2 (T-004).

**What we did instead.** Split the file into one Swift Testing file per
component in `Markus_v3Tests/`:

- `Markus_v3Tests/LastFileStoreTests.swift` (T-001, Wave 1)
- `Markus_v3Tests/NameProbeTests.swift` (T-002, Wave 1)
- `Markus_v3Tests/LocalDocumentsFallbackTests.swift` (T-003, Wave 1)
- `Markus_v3Tests/CreateTargetResolverTests.swift` (T-004, Wave 2 — added in
  Wave 2)

The canonical spec file at `features/resume-and-create-2/tests/unit/...` is
left intact; it remains the human-readable reference for the contracts each
suite verifies. The split is organizational only — every test method, every
assertion, every `@Test` label, and every requirement coverage is preserved.

**Why.** Each wave can land its tests without referencing later-wave symbols,
so the per-wave `xcodebuild test` runs that `/next` performs are not blocked
by unrelated compile errors. This is the same precedent the
`editor-foundation-4` build set when it adapted spec tests into the Xcode
target (`build-deviations.md` D-001/D-002 there) — adopting the same shape
here keeps the test-target layout consistent across features.

**Impact on verify.md.** None. `verify.md` names test methods (e.g.
`LastFileStoreTests` → `recordAndResolve`), not files. The methods exist
under the same suite names with the same behavior, just in per-component
files.

---

## D-002 — UIKit App via AppDelegate, not SwiftUI App (Wave 3 / T-005)

**What design said.** `design.md` calls for a `UIDocumentBrowserViewController`-
backed host wrapped in `UIViewControllerRepresentable` and presented from
the app's `Scene` (i.e. inside a SwiftUI `App` shell).

**What we did instead.** Replaced the SwiftUI `App` entry point entirely
with a pure UIKit `@main` `AppDelegate` + `SceneDelegate`. The
`SceneDelegate` installs `BrowserHostController` (a
`UIDocumentBrowserViewController` subclass) directly as the window's
`rootViewController`. No `UIViewControllerRepresentable` wrapper, no
SwiftUI `App`/`WindowGroup`.

**Why.** Apple's `UIDocumentBrowserViewController` documentation specifies
that it "appears as the root view controller of the window" and cannot be
contained inside another view controller (such as a navigation controller,
tab bar controller, or — by extension — a SwiftUI hosting controller).
Embedding it inside a SwiftUI `WindowGroup` puts it several VCs deep
beneath the SwiftUI hosting chain, which (a) violates that documented
constraint and (b) breaks the very property the host swap is meant to give
us: frame-zero control over presentation order (DC-3). A pure UIKit App
avoids both issues and is also smaller and clearer than the SwiftUI-
wrapper alternative.

**Impact on requirements / design behavior.** None. The behavioral
contracts (BR-* / DC-*) are independent of whether the surrounding shell
is SwiftUI or UIKit; the design's named control points
(`documentBrowser(_:didRequestDocumentCreationWithHandler:)`, scene-
activation / `NSUserActivity` resume path) exist on the UIKit host
regardless. The hard-seam rule still holds: `MarkdownDocument` and
`DocumentView`'s mode-switch are untouched.

**Re-uses preserved.** `DocumentView` is still hosted via
`UIHostingController` (now wrapped in a `UINavigationController` for the
back chevron T-008 adds). `@Environment(\.scenePhase)` still works inside
`DocumentView` because it reads from the `UIWindowScene` state, which is
available equally under a UIKit shell.

---

## D-003 — Save-back via `MarkdownDocumentSaveBridge`, not `UIDocument` (Wave 3 / T-005)

**What design said.** The design leaves save-back implicit, since under
`DocumentGroup` it was handled automatically by `ReferenceFileDocument`'s
`snapshot`/`fileWrapper` round-trip.

**What we did instead.** Added a lightweight
`MarkdownDocumentSaveBridge` (in `Markus_v3/Host/`) that subscribes to
`MarkdownDocument.$text` via Combine and writes the file atomically on a
500ms idle debounce — same cadence as the existing `AutosaveCoordinator`
inside `DocumentView`. The bridge is owned by `BrowserHostController` and
flushed synchronously from `SceneDelegate.sceneDidEnterBackground` /
`sceneWillResignActive`. We did **not** wrap `MarkdownDocument` in a
`UIDocument` subclass.

**Why.** Wrapping `MarkdownDocument` in a `UIDocument` looks clean on
paper (UIDocument provides auto-save and `UIDocument.stateChangedNotification`
that `SaveStatusObserver` already listens to), but it would require
`MarkdownDocument`'s `let initialByteSize` to be set *after* a
`UIDocument.load(fromContents:ofType:)` callback — which is impossible
without changing `MarkdownDocument`. Changing `MarkdownDocument` is a
hard-seam violation (design.md "Hard seam rule"). A separate Combine-
based bridge keeps the model untouched, and the save semantics observable
by the user (typing debounces to disk; background flushes; mode-switch
implicitly flushes via debounce of the prior edit) are equivalent for the
walking-skeleton loop.

**Impact on requirements.** None. The walking-skeleton save loop
continues to function. The full save lifecycle (background, mode-switch,
idle) is preserved.

**Deferred follow-up.** `SaveStatusObserver` currently observes
`UIDocument.stateChangedNotification`, which is no longer fired (no
`UIDocument` in the new host). Save failures from the bridge are
currently silently swallowed; the existing `activeAlert = .saveFailed`
SwiftUI alert path in `DocumentView` is therefore not exercised under
host-driven saves. This is acceptable for Wave 3 (the walking-skeleton
acceptance is about the success path), but a follow-up should wire the
bridge's write errors back into the existing alert surface — either by
having the bridge post a `Notification` that `SaveStatusObserver` learns
to listen for, or by adding a SwiftUI callback parameter to
`DocumentView` that the bridge invokes on failure. Tracking this here so
the next iteration on lifecycle UI (Roadmap #3) picks it up.

---

## D-004 — UI tests target identifier via wildcard, not `.otherElements` (Wave 4 / T-006–T-008)

**What spec said.** The canonical UI spec at
`features/resume-and-create-2/tests/ui/ResumeAndCreateUITests.swift`
queries `RenderedView` via `app.otherElements["RenderedView"]`.

**What we did instead.** In the adapted
`Markus_v3UITests/ResumeAndCreateUITests.swift`, we changed every
occurrence to
`app.descendants(matching: .any).matching(identifier: "RenderedView").firstMatch`.

**Why.** `RenderedView` (`Markus_v3/Views/RenderedView.swift`) is a
SwiftUI `ScrollView` with `.accessibilityIdentifier("RenderedView")`.
XCUITest exposes it as element type **ScrollView**, not `Other`. The
spec's `app.otherElements["RenderedView"]` query never matches because
of the type predicate, even though the element with the right
identifier IS in the hierarchy (verified directly from the test-run
UI-snapshot attachment). The behavioral contract — "the rendered view
is the first interactive screen on resume" — is satisfied; only the
XCUITest matcher was over-specific. The wildcard matcher is the
minimum change to assert the contract; alternative would be to wrap
the ScrollView in another `Other`-type element solely to satisfy the
matcher, which adds view-hierarchy weight for no behavioral benefit.

**Impact on requirements.** None. The same accessibility identifier
(`"RenderedView"`) is asserted; only the XCUITest query is broader.

---

## D-005 — `testBackThenRelaunchStillResumes` re-seeds on relaunch (Wave 4 / T-008)

**What spec said.** The canonical spec calls
`launch(["-uitest-seed-last-file"])` for both the first launch and the
relaunch — already correct in the spec. The adapted test in
`Markus_v3UITests` originally did `launch([])` for the relaunch (a
divergence introduced while adapting), which then failed because
XCUITest does not preserve `NSUserDefaults` across
`XCUIApplication.launch()` invocations (Apple docs: "Application state
may be lost if state restoration is not implemented").

**What we did instead.** Restored the relaunch arg to
`["-uitest-seed-last-file"]` to match the spec, and added an explanatory
comment in the test about XCUITest's NSUserDefaults non-persistence so
future agents don't introduce the same divergence.

**Why.** The behavioral contract under test is the back-tap → terminate
→ seed-relaunch → resume CHAIN (specifically, that the back tap doesn't
crash the resume path on the next launch). The pure cross-launch
bookmark-persistence question that the divergence appeared to test is
not actually testable at the XCUITest level — it is covered at the
logic level by `LastFileStoreTests.readsAreNonDestructive`.

**Impact on requirements.** None — the test now matches the canonical
spec and asserts the behavioral contract the spec was designed to
assert.

---

## D-006 — Edge-swipe-back via `UIScreenEdgePanGestureRecognizer`, not `UINavigationController`'s built-in (Wave 4 / T-008)

**What design said.** "The standard edge-swipe-back returns to the
browser as the standard interactive pop" (DC-14). The seam description
says "The interactive edge-swipe-pop comes free with that
presentation/navigation controller."

**What we did instead.** Installed a dedicated
`UIScreenEdgePanGestureRecognizer` on the modally-presented navigation
controller's view, with `.edges = .left`, that calls
`dismissPresentedEditor()` on `.ended`.

**Why.** `UINavigationController.interactivePopGestureRecognizer` only
fires when the stack has more than one view controller — i.e. it pops
*within* the nav stack. In our case the editor is the root of the
modally-presented nav controller (only one VC on the stack), so the
built-in gesture is a no-op. The presented nav controller is dismissed
via `dismiss(animated:)`, which is not a nav-pop. To preserve the user
expectation that an edge-swipe returns to the browser (DC-14), we
install a custom edge-pan recognizer that triggers the same dismiss
path the back chevron uses (so the contract that the back path does
not clear the last-opened reference, DC-15, holds equally for both
affordances).

**Impact on requirements.** None — DC-14's observable ("Edge-swipe-back
must reveal the browser") is satisfied. The mechanism is different
from the seam description's wording but matches the underlying user-
visible behavior.

---

## D-007 — `DocumentView` gains additive parameters; `RawEditorView` / `MarkdownTextViewBridge` thread `focusOnAppear` (Wave 4 / T-007–T-008)

**What design said.** "DocumentView itself is reused essentially intact
as the editor surface; the change is *underneath* it... and *around*
it (launch branch, create handler, leading back affordance)."

**What we did instead.** Added three new init parameters to
`DocumentView` (all with defaults that match prior behavior, so
existing call sites compile unchanged):

- `initialMode: DocumentMode?` — overrides the size-based initial mode
  decision in `onAppear`. Used by the create flow to request `.raw`
  (DC-8).
- `focusEditorOnAppear: Bool` — when true, the raw editor's
  `UITextView` becomes first responder on first appearance, so the
  keyboard is active (BR-12 / DC-8). Threaded down through
  `RawEditorView` → `MarkdownTextViewBridge` → its `UIViewRepresentable`.
- `onBack: (() -> Void)?` — when non-nil, `DocumentView` adds a leading
  toolbar back chevron whose tap saves and invokes the closure (DC-13).

The hard-seam protected logic (`switchTo`, `toolbarContent`'s rendered
↔ raw transition rule, `MarkdownDocument` itself, the mode-switch
behavior) is untouched. The new parameters are *additive* — the
existing `init(configuration:)` path keeps working with the new
defaults.

**Why.** The Wave-4 behaviors require:
- new file → `.raw` on first appearance (DC-8)
- new file → keyboard active on first appearance (BR-12 / DC-8)
- both modes expose a leading back chevron (DC-13)

None of these can be expressed by host-side wiring alone — they have
to manifest inside the SwiftUI view that owns the editor. Threading
narrow, default-valued parameters into `DocumentView`/`RawEditorView`/
`MarkdownTextViewBridge` is the minimum change. The alternative — a
side-channel like a `NotificationCenter` or a static flag —
introduces hidden coupling between unrelated subsystems for no
behavioral gain.

**Impact on requirements.** None — the contracts the parameters
enable are exactly those BR-12 / DC-8 / DC-13 specify.
