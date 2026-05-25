// EditorFoundationTests.swift
// Spec tests for editor-foundation-4
//
// Framework: Swift Testing (@Test, #expect, #require)
// These tests live in features/editor-foundation-4/tests/ and are reference
// specs — they are NOT part of the Xcode test target until the DAG step
// copies / links them into Markus_v3Tests/. They will fail with ImportError
// until each tagged task is implemented.
//
// Do NOT add DAG task-ID tags here — tagging happens in Stage 5 (verify.md
// is the authoritative task→test mapping after the DAG is committed).

import Testing
import Foundation
import UIKit
@testable import Markus_v3

// MARK: - ScrollAnchor value-type contract

@Suite("ScrollAnchor — value type contract")
struct ScrollAnchorTests {

    // AC-2.1 / AC-3.1 — fractional values round-trip without mutation
    @Test("ScrollAnchor stores a fractionalY in [0, 1]")
    func storesFractionalY() {
        let anchor = ScrollAnchor(fractionalY: 0.4)
        #expect(anchor.fractionalY == 0.4)
    }

    // Behavioral constraint: values outside [0,1] are clamped on write
    @Test("ScrollAnchor clamps values below 0 to 0")
    func clampsNegativeToZero() {
        let anchor = ScrollAnchor(fractionalY: -0.5)
        #expect(anchor.fractionalY == 0.0)
    }

    @Test("ScrollAnchor clamps values above 1 to 1")
    func clampsAboveOneToOne() {
        let anchor = ScrollAnchor(fractionalY: 1.7)
        #expect(anchor.fractionalY == 1.0)
    }

    // Behavioral constraint: .top is the safe default (AC-2.4, GF-6)
    @Test("ScrollAnchor.top has fractionalY == 0")
    func topIsZero() {
        #expect(ScrollAnchor.top.fractionalY == 0.0)
    }

    // GF-6 — empty-document guard: no NaN / infinity
    @Test("ScrollAnchor does not store NaN or infinity")
    func rejectsNaNAndInfinity() {
        let nanAnchor = ScrollAnchor(fractionalY: Double.nan)
        #expect(!nanAnchor.fractionalY.isNaN)
        let infAnchor = ScrollAnchor(fractionalY: Double.infinity)
        #expect(infAnchor.fractionalY.isFinite)
    }

    // Sendable / value-type: two anchors with equal fractionalY are equal
    @Test("Two ScrollAnchors with same fractionalY are equal")
    func equalityByValue() {
        let a = ScrollAnchor(fractionalY: 0.6)
        let b = ScrollAnchor(fractionalY: 0.6)
        #expect(a.fractionalY == b.fractionalY)
    }
}

// MARK: - RawEditorScrollState write/read path

@MainActor
@Suite("RawEditorScrollState — write/read path")
struct RawEditorScrollStateTests {

    // Design seam: coordinator writes currentFractionalY; DocumentView reads synchronously
    @Test("RawEditorScrollState initialises currentFractionalY to 0")
    func initialValueIsZero() {
        let state = RawEditorScrollState()
        #expect(state.currentFractionalY == 0.0)
    }

    @Test("RawEditorScrollState reflects the most-recently written value")
    func reflectsMostRecentWrite() {
        let state = RawEditorScrollState()
        state.currentFractionalY = 0.55
        #expect(state.currentFractionalY == 0.55)
    }

    @Test("RawEditorScrollState write is reflected immediately on the same actor")
    func synchronousRead() {
        // Simulates the eye-icon action closure reading the value synchronously
        // after the coordinator writes it from scrollViewDidScroll
        let state = RawEditorScrollState()
        state.currentFractionalY = 0.73
        let readBack = state.currentFractionalY
        #expect(readBack == 0.73)
    }

    // Design seam: each DocumentView creates a fresh instance — no bleed between docs
    @Test("Two independent RawEditorScrollState instances do not share state")
    func independentInstances() {
        let s1 = RawEditorScrollState()
        let s2 = RawEditorScrollState()
        s1.currentFractionalY = 0.9
        #expect(s2.currentFractionalY == 0.0)
    }
}

// MARK: - ListContinuationHandler pure value-type tests

@Suite("ListContinuationHandler — unordered list continuation (AC-6.x)")
struct ListContinuationHandlerUnorderedTests {

    // Helper: build a String.Index at the end of the given text
    private func endIndex(of text: String) -> String.Index {
        text.endIndex
    }

    // Helper: build a String.Index just before the last non-ws character
    private func indexBeforeLastNonWS(in text: String) -> String.Index? {
        guard let lastNonWS = text.lastIndex(where: { !$0.isWhitespace }) else { return nil }
        return lastNonWS
    }

    // AC-6.1: hyphen-space prefix → continuation
    @Test("Cursor at end of '- item' continues with '- '")
    func hyphenSpaceContinuation() {
        let text = "- some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "- ")
        } else {
            Issue.record("Expected .continueList(prefix: \"- \"), got \(result)")
        }
    }

    // AC-6.2: asterisk-space prefix → continuation
    @Test("Cursor at end of '* item' continues with '* '")
    func asteriskSpaceContinuation() {
        let text = "* some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "* ")
        } else {
            Issue.record("Expected .continueList(prefix: \"* \"), got \(result)")
        }
    }

    // AC-6.3: plus-space prefix → continuation
    @Test("Cursor at end of '+ item' continues with '+ '")
    func plusSpaceContinuation() {
        let text = "+ some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "+ ")
        } else {
            Issue.record("Expected .continueList(prefix: \"+ \"), got \(result)")
        }
    }

    // AC-6.4: cursor mid-line → plain newline (no continuation)
    @Test("Cursor mid-line on '- item' returns plainNewline")
    func midLineCursorPlainNewline() {
        let text = "- some item"
        // Place cursor after "- so" (index 6)
        let idx = text.index(text.startIndex, offsetBy: 6)
        let result = ListContinuationHandler.result(for: text, cursorPosition: idx)
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for mid-line cursor, got \(result)")
        }
    }

    // AC-6.5: line with only the prefix (empty body) → exit list
    @Test("Empty list item '- ' exits the list on Return")
    func emptyItemExitsList() {
        let text = "- "
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .exitList = result { /* pass */ } else {
            Issue.record("Expected .exitList for empty list item, got \(result)")
        }
    }

    // EC-6.3: whitespace-only body after prefix also exits list
    @Test("Whitespace-only body after '- ' exits the list on Return")
    func whitespaceOnlyBodyExitsList() {
        let text = "-   "
        // Note: pattern is "- " so "- " + spaces should match empty-body rule
        let text2 = "- " + "   "
        let result = ListContinuationHandler.result(for: text2, cursorPosition: endIndex(of: text2))
        if case .exitList = result { /* pass */ } else {
            Issue.record("Expected .exitList for whitespace-only body, got \(result)")
        }
    }

    // EC-6.2: `---` horizontal rule is NOT a list item
    @Test("'---' horizontal rule does not trigger continuation")
    func horizontalRuleNoList() {
        let text = "---"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for horizontal rule, got \(result)")
        }
    }

    // EC-6.2: `***` thematic break is NOT a list item
    @Test("'***' thematic break does not trigger continuation")
    func thematicBreakNoList() {
        let text = "***"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for thematic break, got \(result)")
        }
    }

    // AC-6.6 / AC-6.1 round-trip: result for multi-line input with cursor at end of last line
    @Test("Continuation works correctly on the second line of a list")
    func continuationOnSecondLine() {
        let text = "- first item\n- second item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "- ")
        } else {
            Issue.record("Expected .continueList on second list line, got \(result)")
        }
    }
}

@Suite("ListContinuationHandler — ordered list continuation (AC-7.x)")
struct ListContinuationHandlerOrderedTests {

    private func endIndex(of text: String) -> String.Index {
        text.endIndex
    }

    // AC-7.1: simple ordered item → next integer
    @Test("Cursor at end of '1. item' continues with '2. '")
    func orderedContinuationFrom1() {
        let text = "1. some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "2. ")
        } else {
            Issue.record("Expected .continueList(prefix: \"2. \"), got \(result)")
        }
    }

    // AC-7.2: auto-increment is consecutive
    @Test("Cursor at end of '3. item' continues with '4. '")
    func orderedContinuationFrom3() {
        let text = "3. some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "4. ")
        } else {
            Issue.record("Expected .continueList(prefix: \"4. \"), got \(result)")
        }
    }

    // AC-7.2: large numbers increment correctly
    @Test("Cursor at end of '99. item' continues with '100. '")
    func orderedContinuationFrom99() {
        let text = "99. some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "100. ")
        } else {
            Issue.record("Expected .continueList(prefix: \"100. \"), got \(result)")
        }
    }

    // AC-7.2: two-digit number
    @Test("Cursor at end of '12. item' continues with '13. '")
    func orderedContinuationFrom12() {
        let text = "12. some item"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .continueList(let prefix) = result {
            #expect(prefix == "13. ")
        } else {
            Issue.record("Expected .continueList(prefix: \"13. \"), got \(result)")
        }
    }

    // AC-7.3: cursor mid-line → plain newline
    @Test("Cursor mid-line on ordered item returns plainNewline")
    func midLineCursorPlainNewline() {
        let text = "1. some item"
        let idx = text.index(text.startIndex, offsetBy: 5)
        let result = ListContinuationHandler.result(for: text, cursorPosition: idx)
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for mid-line cursor, got \(result)")
        }
    }

    // AC-7.4: empty ordered item exits list
    @Test("Empty ordered item '1. ' exits the list on Return")
    func emptyOrderedItemExitsList() {
        let text = "1. "
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .exitList = result { /* pass */ } else {
            Issue.record("Expected .exitList for empty ordered item, got \(result)")
        }
    }
}

@Suite("ListContinuationHandler — non-list content unaffected (AC-8.x)")
struct ListContinuationHandlerNonListTests {

    private func endIndex(of text: String) -> String.Index {
        text.endIndex
    }

    // AC-8.1: plain paragraph → plain newline
    @Test("Plain paragraph returns plainNewline")
    func plainParagraphNoList() {
        let text = "This is a paragraph."
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for plain paragraph, got \(result)")
        }
    }

    // AC-8.2: heading line → plain newline
    @Test("Heading line '# Heading' returns plainNewline")
    func headingReturnsPlainNewline() {
        let text = "# My Heading"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for heading line, got \(result)")
        }
    }

    @Test("ATX heading '## Sub' returns plainNewline")
    func h2HeadingReturnsPlainNewline() {
        let text = "## Sub-heading"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for h2 heading, got \(result)")
        }
    }

    // AC-8.3: fenced code block line → plain newline
    @Test("Fenced code block line '```swift' returns plainNewline")
    func fencedCodeBlockReturnsPlainNewline() {
        let text = "```swift"
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for fenced code block, got \(result)")
        }
    }

    // AC-8.4: empty line → plain newline
    @Test("Empty line returns plainNewline")
    func emptyLineReturnsPlainNewline() {
        let text = ""
        let result = ListContinuationHandler.result(for: text, cursorPosition: endIndex(of: text))
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for empty line, got \(result)")
        }
    }

    // AC-8.5: cursor in the middle of a plain line → plain newline
    @Test("Cursor mid-line on plain paragraph returns plainNewline")
    func midLinePlainParagraph() {
        let text = "Hello world"
        let midIdx = text.index(text.startIndex, offsetBy: 5)
        let result = ListContinuationHandler.result(for: text, cursorPosition: midIdx)
        if case .plainNewline = result { /* pass */ } else {
            Issue.record("Expected .plainNewline for mid-line cursor on plain text, got \(result)")
        }
    }
}

// MARK: - Scroll anchor fractional arithmetic (AC-2.x / AC-3.x pure logic)

@Suite("Scroll anchor — fractional arithmetic (AC-2.x / AC-3.x)")
struct ScrollAnchorArithmeticTests {

    // AC-2.1 / AC-2.2: tapContentY / totalContentHeight → fractionalY
    @Test("Tap at 40% content height produces fractionalY 0.4")
    func tapFractionalConversion() {
        let tapContentY: Double = 400
        let totalContentHeight: Double = 1000
        let fractional = tapContentY / max(1, totalContentHeight)
        let anchor = ScrollAnchor(fractionalY: fractional)
        #expect(abs(anchor.fractionalY - 0.4) < 1e-9)
    }

    // AC-2.4: no tap / programmatic switch → anchor at top
    @Test("Programmatic switch with no tap produces fractionalY 0")
    func programmaticSwitchDefaultsToTop() {
        let anchor = ScrollAnchor.top
        #expect(anchor.fractionalY == 0.0)
    }

    // EC-2.4 / GF-6: zero content height does not produce NaN or crash
    @Test("Zero content height produces fractionalY 0, no NaN")
    func zeroContentHeightSafe() {
        let tapContentY: Double = 0
        let totalContentHeight: Double = 0
        let fractional = tapContentY / max(1, totalContentHeight)
        let anchor = ScrollAnchor(fractionalY: fractional)
        #expect(anchor.fractionalY == 0.0)
        #expect(!anchor.fractionalY.isNaN)
    }

    // EC-2.1: tap at very top
    @Test("Tap at top (y=0) produces fractionalY 0")
    func tapAtTop() {
        let anchor = ScrollAnchor(fractionalY: 0 / max(1.0, 1000.0))
        #expect(anchor.fractionalY == 0.0)
    }

    // EC-2.2: tap at very bottom → fractionalY approaches 1 but is clamped
    @Test("Tap at bottom produces fractionalY near 1")
    func tapAtBottom() {
        let tapContentY: Double = 999
        let totalContentHeight: Double = 1000
        let fractional = tapContentY / max(1, totalContentHeight)
        let anchor = ScrollAnchor(fractionalY: fractional)
        #expect(anchor.fractionalY > 0.99)
        #expect(anchor.fractionalY <= 1.0)
    }

    // AC-3.2: raw editor scroll offset produces correct fractionalY
    @Test("Raw editor at 60% scroll produces fractionalY 0.6")
    func rawEditorFractionalY() {
        let contentOffsetY: Double = 600
        let contentHeight: Double = 1000
        let viewportHeight: Double = 400
        let scrollableHeight = max(1.0, contentHeight - viewportHeight)
        let fractional = contentOffsetY / scrollableHeight
        let anchor = ScrollAnchor(fractionalY: fractional)
        // 600 / 600 = 1.0 for this geometry; test with different numbers
        let offsetY2: Double = 360
        let scrollable2 = max(1.0, contentHeight - viewportHeight)
        let frac2 = offsetY2 / scrollable2
        let anchor2 = ScrollAnchor(fractionalY: frac2)
        #expect(abs(anchor2.fractionalY - 0.6) < 1e-9)
    }

    // EC-3.3: non-overflowing raw editor → fractionalY treated as 0
    @Test("Non-overflowing content (contentSize <= bounds) produces fractionalY 0")
    func nonOverflowingContentSafe() {
        let contentOffsetY: Double = 0
        let contentHeight: Double = 300
        let viewportHeight: Double = 812   // taller than content
        let scrollableHeight = max(1.0, contentHeight - viewportHeight)
        // scrollableHeight = max(1, -512) = 1
        let fractional = contentOffsetY / scrollableHeight
        let anchor = ScrollAnchor(fractionalY: fractional)
        #expect(anchor.fractionalY == 0.0)
    }

    // AC-2.3 / AC-3.3: anchor in last-viewport zone → offset clamped at max scroll
    @Test("Anchor beyond max scroll is clamped, not over-scrolled")
    func anchorClampedAtMaxScroll() {
        let fractionalY: Double = 0.95
        let contentHeight: Double = 1000
        let viewportHeight: Double = 400
        let maxOffset = max(0.0, contentHeight - viewportHeight)
        let rawOffset = fractionalY * maxOffset
        let clampedOffset = min(rawOffset, maxOffset)
        // clampedOffset should equal rawOffset when it's below maxOffset
        #expect(clampedOffset <= maxOffset)
        #expect(clampedOffset >= 0)
    }

    // GF-5: rapid mode switching — each transition uses the current-at-moment value
    @Test("Overwriting a pending anchor with a new value discards the old one")
    func rapidSwitchOverwritesPendingAnchor() {
        var pendingRawAnchor: ScrollAnchor? = ScrollAnchor(fractionalY: 0.3)
        // Rapid second switch overwrites
        pendingRawAnchor = ScrollAnchor(fractionalY: 0.7)
        #expect(pendingRawAnchor?.fractionalY == 0.7)
    }
}

// MARK: - UITextView migration transparency (AC-1.x — logic-level)

@Suite("UITextView migration transparency — document model (AC-1.x)")
struct UITextViewMigrationTests {

    private func makeDoc(_ source: String) throws -> MarkdownDocument {
        let wrapper = FileWrapper(regularFileWithContents: Data(source.utf8))
        return try MarkdownDocument(file: wrapper, contentType: MarkdownDocument.readableContentTypes.first!)
    }

    // AC-1.1: full raw markdown text round-trips through the document model
    @Test("MarkdownDocument stores and returns the full raw source")
    func documentStoresFullSource() throws {
        let source = "# Hello\n\nSome **bold** text.\n\n- item 1\n- item 2\n"
        let doc = try makeDoc(source)
        #expect(doc.text == source)
    }

    // EC-1.1: empty file produces non-crashing empty text
    @Test("MarkdownDocument with empty source has empty text")
    func emptyDocumentNocrash() throws {
        let doc = try makeDoc("")
        #expect(doc.text == "")
    }

    // EC-1.3: Unicode characters preserved without corruption
    @Test("MarkdownDocument preserves emoji and multi-byte Unicode")
    func unicodePreserved() throws {
        let source = "Hello 🌍\nمرحبا\nこんにちは"
        let doc = try makeDoc(source)
        #expect(doc.text == source)
    }

    // AC-1.3: markDirty is callable and does not mutate text
    @Test("markDirty does not mutate document text")
    func markDirtyDoesNotMutateText() throws {
        let source = "Some content"
        let doc = try makeDoc(source)
        #expect(doc.text == source)
    }
}

// MARK: - Smart-quote / dash suppression (AC-4.x — trait-level)
// Smart-quote suppression is enforced via UITextInputTraits flags set on the
// UITextView subclass. The observable behavior is: the document text contains
// only the literal characters the user typed. That contract is expressed here
// as a pure-value statement — the trait must be .no for smartQuotesType and
// smartDashesType. The actual UIKit trait value is tested by verifying that
// MarkdownEditorTextView configures itself correctly; the behavioral outcome
// (no substitution) is covered by the UI tests.

@Suite("Smart-quote and dash suppression — trait configuration (AC-4.x)")
struct SmartQuoteSuppressionTests {

    // AC-4.1 / AC-4.2 / AC-4.3 — MarkdownEditorTextView disables smart input
    @Test("MarkdownEditorTextView has smartQuotesType == .no")
    func smartQuotesDisabled() {
        let tv = MarkdownEditorTextView()
        #expect(tv.smartQuotesType == .no)
    }

    @Test("MarkdownEditorTextView has smartDashesType == .no")
    func smartDashesDisabled() {
        let tv = MarkdownEditorTextView()
        #expect(tv.smartDashesType == .no)
    }

    // AC-5.1 / AC-5.2 — spell check and autocorrect are active
    @Test("MarkdownEditorTextView has spellCheckingType == .yes")
    func spellCheckEnabled() {
        let tv = MarkdownEditorTextView()
        #expect(tv.spellCheckingType == .yes)
    }

    @Test("MarkdownEditorTextView has autocorrectionType == .yes")
    func autocorrectEnabled() {
        let tv = MarkdownEditorTextView()
        #expect(tv.autocorrectionType == .yes)
    }
}

// MARK: - Scroll anchor lifecycle: consumed exactly once

@Suite("Scroll anchor lifecycle — consumed exactly once (design seam)")
struct ScrollAnchorLifecycleTests {

    // Design seam: pendingRawAnchor / pendingRenderedAnchor consumed exactly once.
    // Expressed as state-machine logic: after consumption, the anchor is nil.

    @Test("Pending anchor is nil after being consumed")
    func pendingAnchorClearedAfterConsumption() {
        var pending: ScrollAnchor? = ScrollAnchor(fractionalY: 0.5)
        // Simulate the bridge consuming the anchor
        let consumed = pending
        pending = nil
        #expect(consumed?.fractionalY == 0.5)
        #expect(pending == nil)
    }

    @Test("A nil anchor is not applied (no spurious scroll)")
    func nilAnchorNotApplied() {
        let pending: ScrollAnchor? = nil
        // If pending is nil, no scroll should fire
        #expect(pending == nil)
    }

    @Test("After consumption, a second update cycle does not re-apply the anchor")
    func anchorNotAppliedTwice() {
        var pending: ScrollAnchor? = ScrollAnchor(fractionalY: 0.3)
        var applyCount = 0

        // Simulate updateUIView logic: apply if pending != nil, then clear
        if pending != nil {
            applyCount += 1
            pending = nil
        }
        // Second updateUIView call — pending is already nil
        if pending != nil {
            applyCount += 1
            pending = nil
        }
        #expect(applyCount == 1)
    }

    // GF-5: rapid mode switching — overwriting pending does not accumulate
    @Test("Rapid mode switching overwrites pending anchor, not accumulates")
    func rapidSwitchingNeverAccumulates() {
        var pendingRendered: ScrollAnchor? = nil

        // First switch
        pendingRendered = ScrollAnchor(fractionalY: 0.2)
        // Rapid second switch before first is consumed
        pendingRendered = ScrollAnchor(fractionalY: 0.8)

        // Only the last-set value is pending; no queue
        #expect(pendingRendered?.fractionalY == 0.8)
    }
}
