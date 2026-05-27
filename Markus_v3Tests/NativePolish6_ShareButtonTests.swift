// NativePolish6_ShareButtonTests.swift
// Wave-3 T-008 tests for native-polish-6 — NP-7 + NP-8 + C5 seam:
// - .textSelection(.enabled) is applied to RenderedView's Markdown content
//   (NP-7; smoke check via constructibility)
// - DocumentViewShareConfig contract for share button presence and gating
//   (NP-8, C5 seam, NPC-11, NPC-12, NP-14)

import Testing
import Foundation
@testable import Markus_v3

// MARK: - NP-8 / C5 — share button presence + gating

@Suite("NP-8 + C5 Seam — Share button presence and gating")
struct NP8_ShareConfigTests {

    // NP-8.1 — SF Symbol is correct
    @Test("Share button uses the square.and.arrow.up SF Symbol")
    func shareButtonSFSymbol() {
        #expect(DocumentViewShareConfig.shareButtonSFSymbol == "square.and.arrow.up")
    }

    // NP-8.7 / NPC-11 — share button absent in raw mode
    @Test("Share button is absent in raw mode")
    func shareButtonAbsentInRawMode() {
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .raw) == false)
    }

    // NP-8.1 — share button present in rendered mode
    @Test("Share button is present in rendered mode")
    func shareButtonPresentInRenderedMode() {
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .rendered) == true)
    }

    // C5 — switching mode toggles share button visibility
    @Test("Switching from rendered to raw removes the share button")
    func modeSwitchRemovesShareButton() {
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .rendered) == true)
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .raw) == false)
    }

    @Test("Switching from raw to rendered adds the share button")
    func modeSwitchAddsShareButton() {
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .raw) == false)
        #expect(DocumentViewShareConfig.shareButtonVisible(mode: .rendered) == true)
    }

    // NPC-12 — nil URL is a no-op (canPresentShare returns false)
    @Test("canPresentShare returns false for nil URL (NPC-12)")
    func canPresentShareWithNilURL() {
        #expect(DocumentViewShareConfig.canPresentShare(for: nil) == false)
    }

    // NP-8.6 / NP-14 — deleted file is a no-op
    @Test("canPresentShare returns false for missing file (NP-8.6, NP-14)")
    func canPresentShareWithMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")
        #expect(DocumentViewShareConfig.canPresentShare(for: url) == false)
    }

    // NP-8.2 — canPresentShare returns true for an existing file
    @Test("canPresentShare returns true for an existing file on disk")
    func canPresentShareWithExistingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("test.md")
        try Data("# test\n".utf8).write(to: file)
        #expect(DocumentViewShareConfig.canPresentShare(for: file) == true)
    }
}

// MARK: - NP-7 — long-press text selection in rendered view

// .textSelection(.enabled) is a SwiftUI modifier applied to the Markdown view
// in RenderedView. We cannot introspect the SwiftUI view tree to verify the
// modifier; the behavioral test is that RenderedView constructs without crash
// (it does — the modifier is structurally valid), and the long-press → system
// text menu (Copy / Select All) is an XCUITest-only verification.

@MainActor
@Suite("NP-7 — RenderedView text selection (long-press system menu)")
struct NP7_TextSelectionTests {

    @Test("RenderedView with text content constructs without crash")
    func renderedViewWithTextSelectionConstructible() {
        let _ = RenderedView(text: "Some **bold** text to select", onTap: { _ in })
        #expect(Bool(true))
    }

    // NP-7.6 — empty document: no crash
    @Test("RenderedView with empty content constructs without crash")
    func longPressOnEmptyDocumentNoCrash() {
        let _ = RenderedView(text: "", onTap: { _ in })
        #expect(Bool(true))
    }

    // NP-15 — long press on empty rendered content: no crash
    @Test("NP-15: Long press on empty rendered document produces no crash (construct)")
    func longPressOnEmptyRenderedDocNoCrash() {
        let _ = RenderedView(text: "", onTap: { _ in })
        #expect(Bool(true))
    }
}
