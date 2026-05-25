# State: resume-and-create-2

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | `LastFileStore` (C1) — durable last-opened reference | 1 | complete | 51d7fc5 |
| T-002 | `NameProbe` (C5) — collision-free `Untitled` naming | 1 | complete | 51d7fc5 |
| T-003 | `LocalDocumentsFallback` (C7) — always-available create target | 1 | complete | 51d7fc5 |
| T-004 | `CreateTargetResolver` (C6) + `LastDirectoryProviding` — target directory + writability probe | 2 | complete | a3856ce |
| T-005 | `BrowserHost` (C0) — `UIDocumentBrowserViewController`-backed scene host | 3 | pending | |
| T-006 | `LaunchResumeBranch` (C2) — resume-vs-browser decision at scene activation | 4 | pending | |
| T-007 | `CreateDocumentHandler` (C4) — deferred-write new-file flow | 4 | pending | |
| T-008 | `DocumentOpenObserver` (C3) + `BackToBrowser` (C8) — record-on-open and leading back affordance | 4 | pending | |
