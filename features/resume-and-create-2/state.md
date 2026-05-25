# State: resume-and-create-2

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | `LastFileStore` (C1) — durable last-opened reference | 1 | complete | 51d7fc5 |
| T-002 | `NameProbe` (C5) — collision-free `Untitled` naming | 1 | complete | 51d7fc5 |
| T-003 | `LocalDocumentsFallback` (C7) — always-available create target | 1 | complete | 51d7fc5 |
| T-004 | `CreateTargetResolver` (C6) + `LastDirectoryProviding` — target directory + writability probe | 2 | complete | a3856ce |
| T-005 | `BrowserHost` (C0) — `UIDocumentBrowserViewController`-backed scene host | 3 | complete | c37ff6d — UIKit App via AppDelegate (D-002); save via MarkdownDocumentSaveBridge (D-003) |
| T-006 | `LaunchResumeBranch` (C2) — resume-vs-browser decision at scene activation | 4 | complete | PENDING_SHA — resume fires from host viewDidAppear; UI-test launch args wired |
| T-007 | `CreateDocumentHandler` (C4) — deferred-write new-file flow | 4 | complete | PENDING_SHA — D-007 additive params on DocumentView |
| T-008 | `DocumentOpenObserver` (C3) + `BackToBrowser` (C8) — record-on-open and leading back affordance | 4 | complete | PENDING_SHA — edge-swipe via D-006; back chevron via D-007 |
