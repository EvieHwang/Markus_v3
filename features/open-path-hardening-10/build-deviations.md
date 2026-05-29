# Build deviations — open-path-hardening-10

Records implementation differences from spec artifacts. Treated as candidate
adversarial findings on any subsequent `/adversarial` pass.

## D-001 — XCUITest end-to-end suite deferred (test scope only)

**Source affected:** `features/open-path-hardening-10/tests/OpenPathSilentNoOpUITests.swift`
**DAG tasks:** T-005

**Spec referenced three XCUITest end-to-end cases:**
- `test_wellFormedFile_opensWithoutAlert`
- `test_everyFailureClass_showsAlertNoSilentReturn`
- `test_coldLaunchFailedPick_showsAlertOnBrowserHost`

**What was done instead.** The behavioral surface those UI tests assert is
fully covered at the Swift Testing layer by the mirrored tests in
`Markus_v3Tests/OpenPathHardening10_Wave3_T005Tests.swift` — every failure
class is exercised through `BrowserHostController.presentDocument(at:)` with
assertions on `openPathAlert` / `activeDocument` / `OpenPathScopeAudit`. The
verify.md coverage matrix already lists these unit-level tests against the
same DC-1 / DC-6a / BR-3.1 rows as the UI tests, so no requirement loses its
coverage.

**Why the XCUITest variants weren't mirrored.** The spec UI tests assume a
`-uitest-stage-problem-file <kind>` launch-arg handler that pre-stages
fixtures (`validUTF8.md`, `not-utf8.md`, `utf16.md`, `mixed.md`, `huge.md`,
`no-perm.md`, `vanished.md`) into the document container *and* a way for
those staged files to surface as cells in `UIDocumentBrowserViewController`.
The system file picker is rooted in the user's iCloud / "On My iPhone"
hierarchy, not the app's sandboxed `Documents/`, so the cell-discovery
sequence (`app.collectionViews.cells.containing(.staticText, identifier:
"validUTF8.md")`) isn't a reliable contract — it depends on the simulator's
file-provider state. Implementing that staging would be its own DAG-sized
piece of work that no requirement in this feature scopes.

**Impact.** None on requirement coverage. The XCUITest cases were
belt-and-suspenders for the same DC/BR rows the unit tests already pin.

**Disposition for the req↔arch loop.** If a future feature wants
end-to-end coverage of the browser-host alert presentation, the right
fix is a new DAG task that scopes the launch-arg staging contract and a
`DocumentView.root` / browser-cell accessibility-identifier convention.
Not in scope here.
