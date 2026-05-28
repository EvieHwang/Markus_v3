# DAG: resume-and-detector-hardening-11

Two independent, surgical changes — one to `LastFileStore`, one to `ChangeDetector` — in the File access layer. They share no files, share no runtime dependency, and can land in either order.

Generated: 2026-05-28

Drives `/build`. Wave N starts only after Wave N-1 completes. Tasks within a wave run in parallel.

---

## Wave 1 — Bookmark fallback + ordered start (parallel, independent)

### T-001 — `LastFileStore.resolveLastOpened()` bookmark fallback
**Description:** Modify `Markus_v3/Resume/LastFileStore.swift`. When the stored bookmark resolves but the recorded path string is missing on disk, do not return nil; instead probe the bookmark-resolved URL by calling `FileManager.default.fileExists(atPath: url.path)` inside a `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource` bracket on that URL, and return the URL on success (mirroring the existing "no recorded path" branch). On probe failure, return nil. Never rewrite the persisted recorded path string from inside the resolver (DC-4); the existing `recordLastOpened(_:)` funnel remains the only writer. Preserve RETAIN-on-failure unconditionally: `hasRecord` stays true through every failure branch.
**Inputs:** design.md DC-1/DC-2/DC-3/DC-4/DC-5/DC-6; requirements BR-1, BR-2, BR-3, BR-4, BR-5, BR-6, BR-7, BR-14, BR-15, BR-16; existing `LastFileStore.swift` (current "no recorded path" fallback branch is the prototype for the new branch).
**Outputs:** `Markus_v3/Resume/LastFileStore.swift` (modified — single function `resolveLastOpened()`).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** All tests in `LastFileStoreBookmarkFallbackTests.swift` pass: `samePathResumeReturnsURL`, `movedFileResolvesViaBookmark`, `deletedFileReturnsNil`, `retainOnFailureAcrossFallback`, `recoveryAfterFailedResolve`, `recordedPathUnchangedAfterFallback`, `corruptBookmarkReturnsNil`. Existing `resume-and-create-2` tests continue to pass without modification.

### T-002 — `ChangeDetector.start()` ordered initial read
**Description:** Modify `Markus_v3/ExternalChange/ChangeDetector.swift`. In `start()`, perform a synchronous coordinated read of `displayURL` using the existing `coordinatedRead(_:)` helper **before** constructing or registering the `FilePresenterShim`. On read success, assign the decoded String to `document.lastKnownDiskContent`. On read failure (returns nil, or any other error), leave `document.lastKnownDiskContent` untouched at whatever the host seeded prior. Do not raise `activeSurface`, do not call `onInvalidEncoding`, do not throw. Only after this step has run does the existing presenter-construction-and-registration code execute. No other change to `start()`, `stop()`, or any handler.
**Inputs:** design.md DC-7/DC-8/DC-9/DC-10/DC-11; requirements BR-8, BR-9, BR-10, BR-11, BR-12, BR-13, BR-17, BR-18, BR-19; existing `ChangeDetector.swift` (`coordinatedRead` helper, `FilePresenterShim` registration block).
**Outputs:** `Markus_v3/ExternalChange/ChangeDetector.swift` (modified — single function `start()`).
**Dependencies:** none.
**Wave:** 1.
**Acceptance:** All tests in `ChangeDetectorOrderedStartTests.swift` pass: `initialReadSeedsLastKnownDiskBeforePresenterLive`, `handlersNeverObservePlaceholder`, `initialReadFailureFallsBackToHostSeeded`, `postStartWriteClassifiedAgainstSeed`, `displayURLUnchangedAcrossStart`. The complete `external-change-5` test suite continues to pass without modification (BR-12 / DC-11).

---

## Size check

Two tasks. Both atomic — one function each, in different files, no shared dependency. Both fit comfortably in a single build session with margin. The DAG is at the low end of the size guidance ("1–2 tasks total likely means too small"), but this is appropriate for a deliberate post-shipping hardening feature whose declaration explicitly scopes it to two audit findings; splitting further would yield no benefit. No new framework, no new dependency, no new deploy path.
