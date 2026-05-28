# Verify — Resume and Detector Hardening

*Human-readable coverage map: each requirement (BR-n) and each design seam (DC-n) → the test(s) that verify it. Task ID labels (T-001 / T-002) are applied in Stage 5 below.*

Tests live in `features/resume-and-detector-hardening-11/tests/unit/` as Swift Testing reference specs. They are not in the Xcode test target; they are the authoritative behavioral specification and will fail (ImportError) until the corresponding implementation lands.

---

## Test files

| File | Subject |
|---|---|
| `tests/unit/LastFileStoreBookmarkFallbackTests.swift` | C1 — `LastFileStore.resolveLastOpened()` bookmark-fallback branch |
| `tests/unit/ChangeDetectorOrderedStartTests.swift` | C2 — `ChangeDetector.start()` ordered initial read |

---

## Requirement coverage (BR → tests)

| BR | Subject | Test(s) |
|---|---|---|
| BR-1 | Bookmark is authoritative resume target | `movedFileResolvesViaBookmark` |
| BR-2 | Fall back to bookmark when recorded path is gone | `movedFileResolvesViaBookmark` |
| BR-3 | No regression when recorded path still resolves | `samePathResumeReturnsURL` |
| BR-4 | Bookmark-resolved URL must itself be reachable | `deletedFileReturnsNil` |
| BR-5 | RETAIN-on-failure preserved end-to-end | `retainOnFailureAcrossFallback`, `recoveryAfterFailedResolve`, `corruptBookmarkReturnsNil` |
| BR-6 | Silent resume on bookmark-fallback (no UI) | covered by absence — no UI assertions; resolver contract is URL-or-nil only |
| BR-7 | Stale-bookmark handling unchanged | `corruptBookmarkReturnsNil` (stale-throw subset) |
| BR-8 | Initial coordinated read precedes live presenter callbacks | `initialReadSeedsLastKnownDiskBeforePresenterLive`, `handlersNeverObservePlaceholder` |
| BR-9 | External change landing during start is not lost | `initialReadSeedsLastKnownDiskBeforePresenterLive`, `postStartWriteClassifiedAgainstSeed` |
| BR-10 | No callback handler runs against placeholder | `handlersNeverObservePlaceholder` |
| BR-11 | `start()` idempotent / single-call pattern | covered by all `ChangeDetectorOrderedStartTests` (single start/stop cycle each) |
| BR-12 | No regression to steady-state detector behavior | `postStartWriteClassifiedAgainstSeed`, `displayURLUnchangedAcrossStart`, plus inherited external-change-5 suite (unmodified) |
| BR-13 | Initial read failure is non-fatal | `initialReadFailureFallsBackToHostSeeded` |
| BR-14 | Bookmark in different security scope than recorded path | `movedFileResolvesViaBookmark` (in-place move within scope is the testable subset; cross-container moves require sandbox fixture, deferred to build manual QA) |
| BR-15 | Path + bookmark agree (steady state) | `samePathResumeReturnsURL` |
| BR-16 | Path exists, bookmark throws | `corruptBookmarkReturnsNil` |
| BR-17 | Presenter callback cannot arrive before `start()` | covered by design (no public mutator for displayURL before start, DC-9); enforced by `displayURLUnchangedAcrossStart` |
| BR-18 | Callback during initial read is not racing | `initialReadSeedsLastKnownDiskBeforePresenterLive` (vacuous gap argument: no presenter live before initial read returns) |
| BR-19 | Sync-vs-async start — main-actor program order | `@MainActor` annotation on `ChangeDetectorOrderedStartTests`; all assertions run on main actor turn |

---

## Design seam coverage (DC → tests)

| DC | Subject | Test(s) |
|---|---|---|
| DC-1 | Bookmark identity, path as hint | `movedFileResolvesViaBookmark` |
| DC-2 | No regression in steady-state branch | `samePathResumeReturnsURL` |
| DC-3 | Bookmark-fallback reachability probe | `movedFileResolvesViaBookmark`, `deletedFileReturnsNil`, `corruptBookmarkReturnsNil` |
| DC-4 | Recorded path not rewritten on fallback | `recordedPathUnchangedAfterFallback` |
| DC-5 | Stale bookmark handling unchanged | `corruptBookmarkReturnsNil` (stale-throw subset) |
| DC-6 | RETAIN-on-failure end-to-end | `retainOnFailureAcrossFallback`, `recoveryAfterFailedResolve` |
| DC-7 | Initial read precedes presenter registration | `initialReadSeedsLastKnownDiskBeforePresenterLive`, `handlersNeverObservePlaceholder` |
| DC-8 | Initial-read failure is non-fatal | `initialReadFailureFallsBackToHostSeeded` |
| DC-9 | `displayURL` is init-only before start | `displayURLUnchangedAcrossStart` |
| DC-10 | Idempotency / second-start unchanged | not exercised by new tests (BR-11 explicitly out of scope for new tests) |
| DC-11 | No regression to steady-state detector | `postStartWriteClassifiedAgainstSeed`, plus inherited external-change-5 suite |

---

## Task → test mapping (authoritative, applied by /dag in Stage 5)

| Task | Tests verifying acceptance |
|---|---|
| T-001 — `LastFileStore.resolveLastOpened()` bookmark fallback | All tests in `LastFileStoreBookmarkFallbackTests.swift`: `samePathResumeReturnsURL`, `movedFileResolvesViaBookmark`, `deletedFileReturnsNil`, `retainOnFailureAcrossFallback`, `recoveryAfterFailedResolve`, `recordedPathUnchangedAfterFallback`, `corruptBookmarkReturnsNil` |
| T-002 — `ChangeDetector.start()` ordered initial read | All tests in `ChangeDetectorOrderedStartTests.swift`: `initialReadSeedsLastKnownDiskBeforePresenterLive`, `handlersNeverObservePlaceholder`, `initialReadFailureFallsBackToHostSeeded`, `postStartWriteClassifiedAgainstSeed`, `displayURLUnchangedAcrossStart` |

Every task in `dag.md` has at least one corresponding test in this map.
