# State: restore-system-create-7

| ID | Description | Wave | Status | Notes |
|----|-------------|------|--------|-------|
| T-001 | Delete C5 `NameProbe` (source + unit tests) | 1 | pending | |
| T-002 | Delete C6 `CreateTargetResolver` (source + unit tests, incl. writability probe) | 1 | pending | |
| T-003 | Delete C7 `LocalDocumentsFallback` (source + unit tests) | 1 | pending | |
| T-004 | Reduce C4 to template-only delegate on `BrowserHostController`; strip deferred-write from `BrowserHostController` / `MarkdownDocumentSaveBridge`; remove `SceneDelegate.createHandler` | 2 | pending | |
| T-005 | Content-based initial-mode rule in `DocumentView.onAppear` (empty → raw + keyboard); strip create-path `initialMode` threading | 2 | pending | |
| T-006 | Final sweep: delete `Markus_v3/Create/` + Xcode group; mirror `SystemCreateUITests`; prune obsolete `ResumeAndCreateUITests` create-flow assertions; full suite green | 3 | pending | |
