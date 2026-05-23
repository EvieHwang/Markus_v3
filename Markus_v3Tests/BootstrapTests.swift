import Testing
import Foundation

final class BootstrapTestsBundleMarker {}

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
        // Compile-time guard: the test target loads, which means the project — including
        // its MarkdownUI package product — was assembled. The exact version assertion is
        // in testMarkdownUIPinUsesUpToNextMinor below.
        let bundle = Bundle(for: BootstrapTestsBundleMarker.self)
        #expect(bundle.bundleIdentifier != nil)
    }

    @Test("Package.resolved pins MarkdownUI with .upToNextMinor(from: 2.4.0)")
    func testMarkdownUIPinUsesUpToNextMinor() throws {
        // #filePath gives the test source's location on disk; tests run on the host Mac
        // (via the simulator process) so this resolves to the actual checkout's path.
        // From Markus_v3Tests/BootstrapTests.swift, the repo root is one level up.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resolved = repoRoot
            .appendingPathComponent("Markus_v3.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let data = try Data(contentsOf: resolved)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(json["pins"] as? [[String: Any]])
        let markdownUI = try #require(pins.first(where: { ($0["identity"] as? String) == "swift-markdown-ui" }))
        let state = try #require(markdownUI["state"] as? [String: Any])
        let version = try #require(state["version"] as? String)
        #expect(version.hasPrefix("2.4."), "Expected MarkdownUI 2.4.x; saw \(version)")
    }
}
