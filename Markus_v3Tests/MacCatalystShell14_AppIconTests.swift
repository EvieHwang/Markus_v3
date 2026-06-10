// MacCatalystShell14_AppIconTests.swift
// Mirror of features/mac-catalyst-shell-14/tests/MacRestorationTests.swift —
// `MacAppIconTests` suite only (T-007 / Component E — Mac app-icon slots).
//
// The reference IconCatalogProbe in the spec returns hardcoded post-build state;
// for a real test we read the live `AppIcon.appiconset/Contents.json` and assert
// the slot population observable directly.

import Testing
import Foundation

@Suite("US-6 — Mac icon slots populated; iOS/iPad icon not regressed")
struct MacCatalystShell14_AppIconTests {

    @Test("AC-6.1 / C-6.1: the 12 Mac icon slots are populated — no empty/placeholder remains")
    func macIconSlots_arePopulated() throws {
        let catalog = try AppIconCatalog.load()
        let macSlots = catalog.macSlots
        // Build deviation D-001: the live catalog has 10 mac slots, not 12 —
        // Apple's standard Mac iconset is 5 sizes (16/32/128/256/512) × 2 scales.
        // The "12" in design.md and the spec test was a ground-truth miscount.
        #expect(macSlots.count == 10,
                "C-6.1: AppIcon.appiconset must declare all 10 idiom:mac slots (5 sizes × 2 scales)")
        #expect(macSlots.allSatisfy { $0.filename != nil && $0.filename?.isEmpty == false },
                "AC-6.1 / C-6.1: every Mac slot must carry a non-empty filename")

        // Every referenced filename resolves to an actual file on disk in the asset folder.
        let folder = try AppIconCatalog.folderURL()
        for slot in macSlots {
            let filename = try #require(slot.filename)
            let url = folder.appendingPathComponent(filename)
            #expect(FileManager.default.fileExists(atPath: url.path),
                    "AC-6.1: the Mac slot file \(filename) must exist in AppIcon.appiconset")
        }
    }

    @Test("AC-6.2 / C-6.2 / FM-9: populating Mac slots does not regress the iOS/iPad icon")
    func macIconSlots_doNotRegressIOSIcon() throws {
        let catalog = try AppIconCatalog.load()
        // The iOS universal "light" slot retains its existing filename.
        let universalLightSlot = catalog.images.first { image in
            image.idiom == "universal" &&
            image.platform == "ios" &&
            image.appearances == nil
        }
        let slot = try #require(universalLightSlot, "the existing iOS universal slot must still exist")
        #expect(slot.filename == "Markus-app-icon.png",
                "AC-6.2 / FM-9: the iOS universal slot must still reference Markus-app-icon.png")

        // The dark and tinted universal slots remain (they retain their existing,
        // empty-filename declarations — we only assert their presence + absence of
        // a Mac-related filename swap).
        let darkSlot = catalog.images.first { image in
            image.idiom == "universal" &&
            image.appearances?.contains(where: { $0.value == "dark" }) == true
        }
        let tintedSlot = catalog.images.first { image in
            image.idiom == "universal" &&
            image.appearances?.contains(where: { $0.value == "tinted" }) == true
        }
        #expect(darkSlot != nil, "FM-9: the iOS dark slot must still exist")
        #expect(tintedSlot != nil, "FM-9: the iOS tinted slot must still exist")

        // The Mac slots are additive — none of the Mac filenames point at the
        // iOS universal asset.
        for mac in catalog.macSlots {
            #expect(mac.filename != "Markus-app-icon.png",
                    "C-6.2 / FM-9: Mac slots must not be wired to the iOS universal asset; Mac slots must be additive")
        }
    }
}

// MARK: - AppIconCatalog (test support — reads the bundled Contents.json)

private struct AppIconCatalog: Decodable {
    let images: [Image]

    var macSlots: [Image] { images.filter { $0.idiom == "mac" } }

    struct Image: Decodable {
        let idiom: String
        let filename: String?
        let platform: String?
        let scale: String?
        let size: String?
        let appearances: [Appearance]?
    }

    struct Appearance: Decodable {
        let appearance: String
        let value: String
    }

    /// Locates the asset catalog JSON on disk by walking up from the bundle to
    /// the source tree. Tests run from the source tree (Xcode test target with
    /// access to the project layout), so we resolve via `#filePath`.
    static func folderURL() throws -> URL {
        // This file lives at .../Markus_v3Tests/MacCatalystShell14_AppIconTests.swift.
        // The catalog folder lives at .../Markus_v3/Assets.xcassets/AppIcon.appiconset/.
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()  // Markus_v3Tests/
            .deletingLastPathComponent()  // project root
        return projectRoot
            .appendingPathComponent("Markus_v3")
            .appendingPathComponent("Assets.xcassets")
            .appendingPathComponent("AppIcon.appiconset")
    }

    static func load() throws -> AppIconCatalog {
        let url = try folderURL().appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AppIconCatalog.self, from: data)
    }
}
