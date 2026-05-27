// NativePolish6_LineBreakNormalizerTests.swift
// Wave-1 T-002 tests for native-polish-6 — NP-3 + C2 seam:
// MarkdownLineBreakNormalizer single-newline hard-line-break behavior.
// Mirrors features/native-polish-6/tests/{BehavioralTests,SeamTests}.swift
// NP3 / C2 suites.

import Testing
import Foundation
@testable import Markus_v3

// MARK: - Behavioral (NP-3) — single-newline becomes hard line break

@Suite("NP-3 — MarkdownLineBreakNormalizer: single-newline hard line break")
struct NP3_LineBreakNormalizerTests {

    // NP-3.1 — single bare newline gets two trailing spaces injected
    @Test("Single bare newline is normalized to two-trailing-spaces + newline")
    func singleNewlineGetsTrailingSpaces() {
        let output = MarkdownLineBreakNormalizer.normalize("line one\nline two")
        #expect(output.contains("line one  \nline two"),
                "Got: \(output)")
    }

    // NP-3.2 — blank line preserved as paragraph break, not converted
    @Test("Blank line (\\n\\n) is preserved, not converted to hard line break")
    func blankLinePreservedAsParagraphBreak() {
        let output = MarkdownLineBreakNormalizer.normalize("para one\n\npara two")
        #expect(output.contains("para one\n\npara two"), "Got: \(output)")
        #expect(!output.contains("para one  \n\n"),
                "Must not inject trailing spaces before a blank line. Got: \(output)")
    }

    // NP-3.3 — normalization applies inside list items (list continuation)
    @Test("Single newline inside a list item is normalized")
    func singleNewlineInListItemNormalized() {
        let output = MarkdownLineBreakNormalizer.normalize("- first line\n  second line of item")
        #expect(output.contains("first line  \n"), "Got: \(output)")
    }

    // NP-3.3 — normalization applies inside blockquotes
    @Test("Single newline inside a blockquote is normalized")
    func singleNewlineInBlockquoteNormalized() {
        let output = MarkdownLineBreakNormalizer.normalize("> line one\n> line two")
        #expect(output.contains("line one  \n"), "Got: \(output)")
    }

    // NP-3.4 / NP-16 — backtick fenced code block NOT normalized
    @Test("Single newlines inside a backtick fenced code block are NOT normalized")
    func fencedCodeBlockNotNormalized_backtick() {
        let output = MarkdownLineBreakNormalizer.normalize("```\ncode line one\ncode line two\n```")
        #expect(output.contains("code line one\ncode line two"), "Got: \(output)")
        #expect(!output.contains("code line one  \n"),
                "Must NOT inject trailing spaces inside fenced code block. Got: \(output)")
    }

    // NP-3.4 / NP-16 — tilde fenced code block NOT normalized
    @Test("Single newlines inside a tilde fenced code block are NOT normalized")
    func fencedCodeBlockNotNormalized_tilde() {
        let output = MarkdownLineBreakNormalizer.normalize("~~~\ncode line one\ncode line two\n~~~")
        #expect(output.contains("code line one\ncode line two"), "Got: \(output)")
        #expect(!output.contains("code line one  \n"),
                "Must NOT inject trailing spaces inside tilde-fenced code block. Got: \(output)")
    }

    // NP-3.4 — multi-line fenced code block entirely unchanged
    @Test("Multi-line fenced code block is entirely left unchanged")
    func multiLineFencedCodeBlockUnchanged() {
        let input = """
        ```swift
        func foo() {
            let x = 1
            return x
        }
        ```
        """
        let output = MarkdownLineBreakNormalizer.normalize(input)
        #expect(output.contains("func foo() {\n    let x = 1\n    return x\n}"),
                "Got: \(output)")
    }

    // NP-3.5 / NP-17 — inline code span: rendered output is correct (F-005 known gap)
    @Test("Inline code span content renders correctly (F-005 known gap)")
    func inlineCodeSpanNotAffectedInOutput() {
        let output = MarkdownLineBreakNormalizer.normalize("Use `code` in prose")
        #expect(output.contains("`code`"), "Got: \(output)")
    }

    // NP-3.5 / NP-17 — multi-line inline code span does not crash
    @Test("Multi-line inline code span does not crash the normalizer (F-005)")
    func multiLineInlineCodeSpanNoCrash() {
        let output = MarkdownLineBreakNormalizer.normalize("Use `foo\nbar` in prose")
        #expect(!output.isEmpty)
    }

    // NPC-6 — two consecutive newlines produce exactly \n\n
    @Test("Two consecutive newlines produce exactly \\n\\n")
    func twoConsecutiveNewlinesUnchanged() {
        let output = MarkdownLineBreakNormalizer.normalize("first\n\nsecond")
        #expect(output.contains("\n\n"), "Got: \(output)")
        #expect(!output.contains("  \n\n"),
                "Must not inject trailing spaces before the first \\n of a blank line. Got: \(output)")
    }

    // NP-3.1 — line already ending in two spaces is not double-modified
    @Test("Line already ending in two trailing spaces is not further modified")
    func alreadyNormalizedLineNotDoubleModified() {
        let output = MarkdownLineBreakNormalizer.normalize("line one  \nline two")
        #expect(!output.contains("line one    \n"),
                "Must not double-modify already-normalized line. Got: \(output)")
    }

    // Pure function
    @Test("Normalizer is a pure function (same input → same output)")
    func normalizerIsPureFunction() {
        let input = "line one\nline two\n\npara two"
        let a = MarkdownLineBreakNormalizer.normalize(input)
        let b = MarkdownLineBreakNormalizer.normalize(input)
        #expect(a == b)
    }

    // Empty input
    @Test("Normalizer handles empty string")
    func normalizerHandlesEmptyString() {
        #expect(MarkdownLineBreakNormalizer.normalize("") == "")
    }

    // NP-16 — fenced code block interior verbatim
    @Test("NP-16: Fenced code block interior newlines are not modified")
    func fencedCodeBlockInteriorsUnchanged() {
        let output = MarkdownLineBreakNormalizer.normalize("```\nfirst\nsecond\nthird\n```")
        #expect(output.contains("first\nsecond\nthird"), "Got: \(output)")
    }

    // NP-17 — multi-line inline code span (also covered above, edge case framing)
    @Test("NP-17: Multi-line inline code span does not crash")
    func multiLineInlineCodeNoCrash() {
        let output = MarkdownLineBreakNormalizer.normalize("See `foo\nbar` for details")
        #expect(!output.isEmpty)
    }
}

// MARK: - Seam (C2) — input/output contract

@Suite("C2 Seam — MarkdownLineBreakNormalizer input/output contract")
struct C2_NormalizerSeamTests {

    // Fenced (backtick) pass-through
    @Test("C2: Fenced code block (backtick) interior passes through verbatim")
    func fencedCodeBacktickPassThrough() {
        let output = MarkdownLineBreakNormalizer.normalize("```\nline_a\nline_b\n```")
        #expect(output.contains("line_a\nline_b"), "Got: \(output)")
    }

    // Fenced (tilde) pass-through
    @Test("C2: Fenced code block (tilde) interior passes through verbatim")
    func fencedCodeTildePassThrough() {
        let output = MarkdownLineBreakNormalizer.normalize("~~~\nline_a\nline_b\n~~~")
        #expect(output.contains("line_a\nline_b"), "Got: \(output)")
    }

    // Info-string fenced
    @Test("C2: Info-string fenced code block passes through verbatim")
    func infoStringFencedCodePassThrough() {
        let output = MarkdownLineBreakNormalizer.normalize("```swift\nlet x = 1\nlet y = 2\n```")
        #expect(output.contains("let x = 1\nlet y = 2"), "Got: \(output)")
    }

    // Bare newline normalization
    @Test("C2: Bare newline in body text becomes two-trailing-spaces + newline")
    func bareNewlineBecomesTwoTrailingSpaces() {
        let output = MarkdownLineBreakNormalizer.normalize("first\nsecond")
        #expect(output == "first  \nsecond", "Got: \(output)")
    }

    // List continuation
    @Test("C2: Bare newline in list continuation line is normalized")
    func listContinuationNewlineNormalized() {
        let output = MarkdownLineBreakNormalizer.normalize("- item one\n- item two")
        #expect(output.contains("item one  \n"), "Got: \(output)")
    }

    // Blank line preserved
    @Test("C2: Blank line (\\n\\n) is preserved unchanged")
    func blankLinePreserved() {
        let output = MarkdownLineBreakNormalizer.normalize("paragraph one\n\nparagraph two")
        #expect(output.contains("paragraph one\n\n"), "Got: \(output)")
        #expect(!output.contains("paragraph one  \n\n"), "Got: \(output)")
    }

    // Paragraph-break preservation (NPC-6)
    @Test("C2: A\\n\\nB stays A\\n\\nB exactly")
    func doubleNewlineStaysParagraphBreak() {
        let output = MarkdownLineBreakNormalizer.normalize("A\n\nB")
        #expect(output == "A\n\nB", "Got: \(output)")
    }

    // Already-normalized line untouched
    @Test("C2: Line already ending in two spaces is not further modified")
    func alreadyNormalizedNotDoubleModified() {
        let output = MarkdownLineBreakNormalizer.normalize("first  \nsecond")
        #expect(!output.contains("first    \n"), "Got: \(output)")
    }

    // Body text after code block is normalized
    @Test("C2: Body text after a fenced code block is normalized normally")
    func bodyTextAfterCodeBlockNormalized() {
        let output = MarkdownLineBreakNormalizer.normalize("```\ncode\n```\nbody line one\nbody line two")
        #expect(output.contains("code\n"), "Got: \(output)")
        #expect(output.contains("body line one  \nbody line two"), "Got: \(output)")
    }

    // Empty
    @Test("C2: Empty input produces empty output")
    func emptyInputProducesEmptyOutput() {
        #expect(MarkdownLineBreakNormalizer.normalize("") == "")
    }

    // Single line
    @Test("C2: Single-line input with no newline is returned unchanged")
    func singleLineUnchanged() {
        #expect(MarkdownLineBreakNormalizer.normalize("hello world") == "hello world")
    }

    // Blockquote (NP-3.3)
    @Test("C2: Single newline inside a blockquote is normalized")
    func blockquoteNewlineNormalized() {
        let output = MarkdownLineBreakNormalizer.normalize("> first line\n> second line")
        #expect(output.contains("first line  \n"), "Got: \(output)")
    }

    // Deterministic
    @Test("C2: Deterministic — same input → same output")
    func normalizerIsDeterministic() {
        let input = "line one\nline two\n\nparagraph two\nline three\n```\ncode\n```\nafter"
        let first = MarkdownLineBreakNormalizer.normalize(input)
        let second = MarkdownLineBreakNormalizer.normalize(input)
        #expect(first == second)
    }

    // No state
    @Test("C2: Normalizer has no state — independent calls do not affect each other")
    func normalizerHasNoState() {
        let firstA = MarkdownLineBreakNormalizer.normalize("a\nb")
        let firstX = MarkdownLineBreakNormalizer.normalize("x\ny")
        let secondX = MarkdownLineBreakNormalizer.normalize("x\ny")
        let secondA = MarkdownLineBreakNormalizer.normalize("a\nb")
        #expect(firstA == secondA)
        #expect(firstX == secondX)
    }
}
