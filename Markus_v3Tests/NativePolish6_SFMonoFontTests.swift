// NativePolish6_SFMonoFontTests.swift
// Wave-1 T-001 tests for native-polish-6 — NP-1 SF Mono font in raw editor.
// Mirrors features/native-polish-6/tests/BehavioralTests.swift NP1 suite.
//
// See features/native-polish-6/build-deviations.md (BD-1) for why the
// fontName prefix accepts ".AppleSystemUIFontMonospaced-" in addition to
// "SFMono-": on iOS, `UIFont(name: "SFMono-Regular", ...)` returns nil and
// `UIFont.monospacedSystemFont(...)` is the documented public API for SF Mono.

import Testing
import UIKit
@testable import Markus_v3

private func isSFMonoFont(_ font: UIFont?) -> Bool {
    guard let font else { return false }
    let name = font.fontName
    // Either the named SFMono face (currently not exposed to apps on iOS) or
    // the documented `monospacedSystemFont` fallback whose internal name is
    // `.AppleSystemUIFontMonospaced-Regular` — both ARE SF Mono.
    return name.hasPrefix("SFMono-")
        || name.hasPrefix(".AppleSystemUIFontMonospaced-")
}

private func isMonospaced(_ font: UIFont?) -> Bool {
    guard let font else { return false }
    return font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
}

@MainActor
@Suite("NP-1 — SF Mono font in raw editor")
struct NP1_SFMonoFontTests {

    // NP-1.1 — text view is using SF Mono (named face or monospacedSystemFont)
    @Test("MarkdownEditorTextView uses SF Mono typeface")
    func rawEditorUsesSFMono() {
        let tv = MarkdownEditorTextView()
        #expect(isSFMonoFont(tv.font),
                "Expected SF Mono (SFMono- or .AppleSystemUIFontMonospaced- prefix), got '\(tv.font?.fontName ?? "nil")'")
        #expect(isMonospaced(tv.font),
                "Font must be monospaced (traitMonoSpace)")
    }

    // NP-1.1 / behavioral: the font name is the SF Mono face name on this platform
    @Test("MarkdownEditorTextView font name is SF Mono (either named or system-monospace internal name)")
    func rawEditorFontNameIsSFMono() {
        let tv = MarkdownEditorTextView()
        #expect(isSFMonoFont(tv.font),
                "Expected SF Mono font name prefix, got '\(tv.font?.fontName ?? "nil")'")
    }

    // NP-1.2 — fixed prose-appropriate size in [14, 20]
    @Test("MarkdownEditorTextView has fixed prose size in [14, 20]")
    func rawEditorFontSizeIsProseSize() {
        let tv = MarkdownEditorTextView()
        let size = tv.font?.pointSize ?? 0
        #expect(size >= 14 && size <= 20,
                "Expected prose size in [14, 20], got \(size)")
    }

    // NP-1.3 — typing attributes carry SF Mono so newly typed text inherits it
    @Test("MarkdownEditorTextView typingAttributes carry SF Mono font")
    func rawEditorTypingAttributesCarrySFMono() {
        let tv = MarkdownEditorTextView()
        let typingFont = tv.typingAttributes[.font] as? UIFont
        #expect(typingFont != nil, "typingAttributes must contain a font key")
        #expect(isSFMonoFont(typingFont),
                "typingAttributes font must be SF Mono, got '\(typingFont?.fontName ?? "nil")'")
        #expect(isMonospaced(typingFont),
                "typingAttributes font must be monospaced")
    }

    // NP-1.3 — text set programmatically keeps SF Mono (not overridden by UITextView defaults)
    @Test("Text set on MarkdownEditorTextView retains SF Mono after assignment")
    func rawEditorTextAssignmentRetainsSFMono() {
        let tv = MarkdownEditorTextView()
        tv.text = "# hello\nsome content"
        #expect(isSFMonoFont(tv.font),
                "Font must remain SF Mono after text assignment, got '\(tv.font?.fontName ?? "nil")'")
        #expect(isMonospaced(tv.font),
                "Font must remain monospaced after text assignment")
    }

    // NP-1.4 — must not use SF Pro for any portion of the editing surface
    @Test("MarkdownEditorTextView does not use SF Pro")
    func rawEditorDoesNotUseSFPro() {
        let tv = MarkdownEditorTextView()
        let fontName = tv.font?.fontName ?? ""
        // SF Pro manifests as .SFUI-Regular, .SFProText-Regular, etc.
        // The monospaced face is `.AppleSystemUIFontMonospaced-` (not SF Pro),
        // so the prefix-check for `.SF` would over-match — narrow to SF Pro families.
        let isSFPro = fontName.hasPrefix(".SFUI")
            || fontName.hasPrefix("SFPro")
            || fontName.hasPrefix(".SFPro")
            || fontName.hasPrefix(".SFProText")
        #expect(!isSFPro, "Raw editor must not use SF Pro; got '\(fontName)'")
    }
}
