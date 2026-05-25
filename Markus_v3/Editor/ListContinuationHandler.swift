import Foundation

enum ListContinuationResult: Equatable {
    case plainNewline
    case continueList(prefix: String)
    case exitList(stripPrefix: String)
}

struct ListContinuationHandler {

    static func result(for text: String, cursorPosition: String.Index) -> ListContinuationResult {
        let (lineStart, lineEnd) = lineRange(in: text, around: cursorPosition)
        let line = String(text[lineStart..<lineEnd])

        guard let match = matchListPrefix(line: line) else {
            return .plainNewline
        }

        let prefixEndInLine = line.index(line.startIndex, offsetBy: match.prefix.count)
        let body = line[prefixEndInLine...]

        let bodyIsEmptyOrWhitespace = body.allSatisfy { $0.isWhitespace }
        if bodyIsEmptyOrWhitespace {
            return .exitList(stripPrefix: match.prefix)
        }

        guard let lastNonWS = line.lastIndex(where: { !$0.isWhitespace }) else {
            return .plainNewline
        }
        let cursorOffsetInLine = text.distance(from: lineStart, to: cursorPosition)
        let lastNonWSOffset = line.distance(from: line.startIndex, to: lastNonWS)
        if cursorOffsetInLine <= lastNonWSOffset {
            return .plainNewline
        }

        switch match.kind {
        case .unordered(let marker):
            return .continueList(prefix: "\(marker) ")
        case .ordered(let n):
            return .continueList(prefix: "\(n + 1). ")
        }
    }

    private enum PrefixKind {
        case unordered(Character)
        case ordered(Int)
    }

    private struct PrefixMatch {
        let prefix: String
        let kind: PrefixKind
    }

    private static func matchListPrefix(line: String) -> PrefixMatch? {
        if let first = line.first, "-*+".contains(first) {
            let afterFirst = line.index(after: line.startIndex)
            if afterFirst < line.endIndex, line[afterFirst] == " " {
                return PrefixMatch(prefix: "\(first) ", kind: .unordered(first))
            }
        }

        var digitEnd = line.startIndex
        while digitEnd < line.endIndex, line[digitEnd].isASCII, line[digitEnd].isNumber {
            digitEnd = line.index(after: digitEnd)
        }
        if digitEnd > line.startIndex,
           digitEnd < line.endIndex,
           line[digitEnd] == ".",
           line.index(after: digitEnd) < line.endIndex,
           line[line.index(after: digitEnd)] == " ",
           let n = Int(line[line.startIndex..<digitEnd]) {
            let prefix = String(line[line.startIndex...line.index(after: digitEnd)])
            return PrefixMatch(prefix: prefix, kind: .ordered(n))
        }

        return nil
    }

    private static func lineRange(in text: String, around index: String.Index) -> (String.Index, String.Index) {
        var start = index
        while start > text.startIndex {
            let prev = text.index(before: start)
            if text[prev] == "\n" { break }
            start = prev
        }
        var end = index
        while end < text.endIndex, text[end] != "\n" {
            end = text.index(after: end)
        }
        return (start, end)
    }
}
