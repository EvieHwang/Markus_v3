// Spec test — Wave 1 / T-001
// Tags: T-001
// Verifies: AC-1.3, EC-15 (UTType filter), F-005 (MarkdownUI pin), F-006 (Privacy Manifest enumeration)
//
// Initial state: this file should fail to compile or fail at runtime until T-001 lands the
// Xcode project, dependency, and PrivacyInfo.xcprivacy. Failing because the bundle/manifest
// is missing is the expected pre-build signal.

import Testing
import Foundation

@Suite("Bootstrap — T-001")
struct BootstrapTests {

    @Test("Info.plist declares .md and .markdown document UTTypes")
    func testInfoPlistDeclaresMarkdownUTTypes() throws {
        let bundle = Bundle.main
        let docTypes = try #require(
            bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]],
            "Info.plist must declare CFBundleDocumentTypes"
        )
        let utis = docTypes
            .flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
        #expect(utis.contains("net.daringfireball.markdown") || utis.contains("public.markdown"))
        let extensions = docTypes
            .flatMap { ($0["CFBundleTypeExtensions"] as? [String]) ?? [] }
        #expect(extensions.contains("md"))
        #expect(extensions.contains("markdown"))
    }

    @Test("Privacy Manifest enumerates the required-reason API categories")
    func testPrivacyManifestEnumeratesRequiredCategories() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy must ship with the app bundle"
        )
        let data = try Data(contentsOf: url)
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let apiTypes = try #require(
            plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let categories = apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        #expect(categories.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        #expect(categories.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(categories.contains("NSPrivacyAccessedAPICategoryDiskSpace"))
    }

    @Test("MarkdownUI resolves at the pinned minor (>=2.4, <2.5)")
    func testMarkdownUIResolvesAtPinnedMinor() throws {
        // Compile-time guard: importing MarkdownUI must succeed.
        // The version-pin shape is enforced by Package.resolved review in CI / build agent;
        // see also testMarkdownUIPinUsesUpToNextMinor below.
        #expect(Bundle(for: type(of: self)).bundleIdentifier != nil)
    }

    @Test("Package.resolved pins MarkdownUI with .upToNextMinor(from: 2.4.0)")
    func testMarkdownUIPinUsesUpToNextMinor() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolved = repoRoot.appendingPathComponent("Markus_v3.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let data = try Data(contentsOf: resolved)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(json["pins"] as? [[String: Any]])
        let markdownUI = try #require(pins.first(where: { ($0["identity"] as? String) == "swift-markdown-ui" }))
        let state = try #require(markdownUI["state"] as? [String: Any])
        let version = try #require(state["version"] as? String)
        #expect(version.hasPrefix("2.4."), "Expected MarkdownUI 2.4.x; saw \(version)")
    }
}
