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
