import Foundation
import UIKit

/// Resume-vs-browser decision at scene activation (design C2 / DC-3, DC-4).
///
/// Called from `SceneDelegate.scene(_:willConnectTo:options:)` *before* the
/// browser is made the visible top view controller. If `LastFileStore`
/// resolves a reachable last-opened file, we present that file's editor as
/// the scene's first content via `BrowserHostController.presentDocument`
/// with `animated: false`, so the browser is never the visible top screen
/// on a successful resume.
///
/// If no reference resolves (first-ever launch, stale bookmark,
/// unreachable file), the branch does nothing — the browser is the
/// natural landing screen (DC-4). No error UI is shown either way.
///
/// Also handles deterministic UI-test launch state via `-uitest-*`
/// launch arguments so XCUITest can seed the store before the resume
/// decision runs.
enum LaunchResumeBranch {

    static let resetArg = "-uitest-reset-last-file"
    static let staleArg = "-uitest-stale-last-file"
    static let seedArg = "-uitest-seed-last-file"
    /// external-change-5: open a freshly-seeded sample as the open document so the
    /// external-change UI tests have a known file behind the editor.
    static let openSeedArg = "-uitest-open-seed-file"

    // MARK: - mac-catalyst-shell-14 T-006 launch-arg handlers
    //
    // The Catalyst restoration / menu / open XCUITests need to seed a named
    // fixture and to drive deterministic resume-store state across a relaunch.
    // These args are camelCase to match the spec in
    // features/mac-catalyst-shell-14/tests/MacMenuBarUITests.swift. They are
    // siblings of the iOS-side `-uitest-*` flags above, not replacements —
    // each owns a different fixture path so the iOS tests are unaffected.

    /// Seed a named markdown fixture into the app's Documents directory and
    /// record it as last-opened so the resume branch lands directly in the
    /// editor. Reads the fixture name from the argument *following* this flag
    /// (so the launch args read `-UITest-SeedFixture mac-fixture.md`).
    static let seedFixtureArg = "-UITest-SeedFixture"

    /// Reset the resume store (no seed). Equivalent to `resetArg` but named to
    /// match the Catalyst test spec.
    static let resetResumeStoreArg = "-UITest-ResetResumeStore"

    /// Plant a resume reference that fails closed (no bookmark resolution, no
    /// reachable path). Equivalent to `staleArg` but named to match the spec.
    static let resumeFileUnreachableArg = "-UITest-ResumeFileUnreachable"

    /// Apply UI-test launch overrides to `LastFileStore` if any are
    /// present in `arguments`. Idempotent; safe to call on every scene
    /// activation.
    static func applyTestOverrides(_ arguments: [String], store: LastFileStore = LastFileStore()) {
        if arguments.contains(resetArg) || arguments.contains(resetResumeStoreArg) {
            UserDefaults.standard.removeObject(forKey: LastFileStore.defaultBookmarkKey)
            UserDefaults.standard.removeObject(forKey: LastFileStore.defaultPathKey)
            // Also remove any seed file the previous test left behind so
            // collision-naming tests start clean.
            removeSeededSample()
            removeAllSeededFixtures()
        }
        if arguments.contains(staleArg) || arguments.contains(resumeFileUnreachableArg) {
            // Plant a bookmark Data value that won't resolve, plus a
            // recorded path that does not exist on disk. Both halves of
            // the resolve check fail closed (DC-4 / BR-5 / BR-19).
            UserDefaults.standard.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: LastFileStore.defaultBookmarkKey)
            UserDefaults.standard.set("/var/empty/never-exists.md", forKey: LastFileStore.defaultPathKey)
        }
        if arguments.contains(seedArg) || arguments.contains(openSeedArg) {
            // Reset any stale store/seed first so the open file is deterministic.
            if arguments.contains(openSeedArg) {
                removeSeededSample()
            }
            seedSampleAndRecord(store: store)
        }
        if let fixtureName = namedFixtureArgument(in: arguments) {
            seedNamedFixtureAndRecord(named: fixtureName, store: store)
        }
    }

    /// Read the argument *following* `seedFixtureArg`. Returns nil when the
    /// flag is absent or has no following value.
    private static func namedFixtureArgument(in arguments: [String]) -> String? {
        guard let idx = arguments.firstIndex(of: seedFixtureArg) else { return nil }
        let next = arguments.index(after: idx)
        guard next < arguments.endIndex else { return nil }
        let value = arguments[next]
        // Guard against the value being another flag (shouldn't happen, but
        // tolerate it rather than create a file named "-foo").
        if value.hasPrefix("-") { return nil }
        return value
    }

    /// Decide whether to present a resumed file as the scene's first
    /// content. Returns true if a file was presented (browser will be
    /// covered); false if the browser should be the landing screen.
    @MainActor
    @discardableResult
    static func resume(into host: BrowserHostController,
                       store: LastFileStore = LastFileStore()) -> Bool {
        guard let url = store.resolveLastOpened() else { return false }
        host.presentDocument(at: url, animated: false)
        return true
    }

    // MARK: - UI-test seeding helpers

    private static let seededSampleName = "sample.md"
    private static let seededSampleBody = "# Resumed sample\n\nThis file is the seed for resume UI tests.\n"

    private static func seedSampleAndRecord(store: LastFileStore) {
        guard let docs = appDocumentsDirectory() else { return }
        let url = docs.appendingPathComponent(seededSampleName)
        try? seededSampleBody.write(to: url, atomically: true, encoding: .utf8)
        store.recordLastOpened(url)
    }

    private static func removeSeededSample() {
        guard let docs = appDocumentsDirectory() else { return }
        let url = docs.appendingPathComponent(seededSampleName)
        try? FileManager.default.removeItem(at: url)
    }

    /// mac-catalyst-shell-14 T-006 — seed a named markdown fixture into the
    /// app's Documents directory and record it as last-opened so the resume
    /// branch lands directly in the editor. The fixture body is a single-line
    /// marker that distinguishes it from the default seed sample.
    private static func seedNamedFixtureAndRecord(named name: String, store: LastFileStore) {
        guard let docs = appDocumentsDirectory() else { return }
        let url = docs.appendingPathComponent(name)
        let body = "# Mac fixture — \(name)\n\nSeeded by -UITest-SeedFixture for Catalyst UI tests.\n"
        try? body.write(to: url, atomically: true, encoding: .utf8)
        store.recordLastOpened(url)
    }

    /// mac-catalyst-shell-14 T-006 — remove every previously seeded `.md`
    /// fixture from the Documents directory so reset cases start clean. Only
    /// touches files whose names begin with `mac-fixture` to avoid wiping
    /// genuine user documents in the same directory.
    private static func removeAllSeededFixtures() {
        guard let docs = appDocumentsDirectory() else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: docs,
                                                        includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("mac-fixture") {
            try? fm.removeItem(at: url)
        }
    }

    /// App-container Documents directory used by these two UI-test seed
    /// helpers. See build-deviations.md D-1 for the history of the inlining.
    private static func appDocumentsDirectory() -> URL? {
        try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
}
