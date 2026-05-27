import Foundation

/// Pre-render transform that converts every single newline in body text to a
/// CommonMark hard line break (two trailing spaces + `\n`). Fenced code block
/// interiors are passed through verbatim; blank lines (paragraph breaks) are
/// preserved as-is.
///
/// Pure function — no state, no side effects. Safe to call on every render pass.
///
/// Algorithm (design C2):
/// 1. Tokenize input by `\n` into lines and classify each line as inside or
///    outside a fenced code block (` ``` ` / `~~~` openers and closers, with
///    optional info string).
/// 2. For each inter-line newline outside a fenced region, append two trailing
///    spaces to the prior line unless:
///    - The next line is empty (blank line / paragraph break — NPC-6).
///    - The line already ends in two or more trailing spaces (already
///      normalized — must not double-modify).
///    - The line is empty (the blank line itself).
///    - The line ends in a backslash (CommonMark backslash hard break).
///
/// Indented code blocks are *not* exempted by design — inside list continuation,
/// 4-space indentation is list body, not code, so a naïve indent heuristic
/// would suppress required hard-break injection inside list items (NP-3.3 /
/// adversarial F-001).
///
/// Known gap: F-005 (LOW, open). The algorithm operates at block level; it does
/// not detect inline code spans (`` `...` ``). A newline inside an inline code
/// span receives trailing-space injection at the byte level. Current swift-cmark
/// renders inline code span content verbatim and ignores the injected spaces,
/// so observable output is correct, but byte identity of inline-span interiors
/// is not preserved.
enum MarkdownLineBreakNormalizer {

    static func normalize(_ input: String) -> String {
        if input.isEmpty { return input }

        let lines = input.components(separatedBy: "\n")
        let insideFenceFlags = Self.classifyFenceMembership(lines)

        var result = ""
        for i in 0..<lines.count {
            var line = lines[i]
            let isLast = i == lines.count - 1
            if !isLast {
                let nextLine = lines[i + 1]
                let lineInsideFence = insideFenceFlags[i]
                let isBlankBreak = nextLine.isEmpty
                let alreadyHasTrailingSpaces = line.hasSuffix("  ")
                let endsWithBackslash = line.hasSuffix("\\")
                let lineIsEmpty = line.isEmpty

                if !lineInsideFence
                    && !isBlankBreak
                    && !alreadyHasTrailingSpaces
                    && !endsWithBackslash
                    && !lineIsEmpty {
                    line += "  "
                }
                result += line + "\n"
            } else {
                result += line
            }
        }
        return result
    }

    /// Marks each line as inside (true) or outside (false) a fenced code block.
    /// A fence opener/closer line is itself marked inside the fence so the
    /// newline that ends it is also treated as part of the code region.
    private static func classifyFenceMembership(_ lines: [String]) -> [Bool] {
        var flags = [Bool](repeating: false, count: lines.count)
        var insideFence = false
        var fenceMarker: Character? = nil
        var fenceLength = 0

        for (i, line) in lines.enumerated() {
            let trimmed = line.drop(while: { $0 == " " })
            if !insideFence {
                if let first = trimmed.first, first == "`" || first == "~" {
                    let runLength = trimmed.prefix(while: { $0 == first }).count
                    if runLength >= 3 {
                        insideFence = true
                        fenceMarker = first
                        fenceLength = runLength
                        flags[i] = true
                        continue
                    }
                }
                flags[i] = false
            } else {
                flags[i] = true
                if let first = trimmed.first, first == fenceMarker {
                    let runLength = trimmed.prefix(while: { $0 == first }).count
                    if runLength >= fenceLength {
                        // Closer (info string forbidden on closers, but length match suffices for our purposes).
                        insideFence = false
                        fenceMarker = nil
                        fenceLength = 0
                    }
                }
            }
        }
        return flags
    }
}
