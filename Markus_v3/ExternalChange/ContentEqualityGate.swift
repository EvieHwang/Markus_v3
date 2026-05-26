import Foundation

/// DC-11 — the single content-equality gate behind absorb-vs-collision (detector)
/// and clean-vs-dirty (document model).
///
/// Two contents are *equal* iff they are byte-identical OR equal after newline
/// normalization (CRLF/CR → LF). Any difference beyond newline encoding is
/// "material": empty↔non-empty is always material, and trailing-whitespace
/// differences are material (the gate is newline-only, not whitespace-insensitive).
enum ContentEqualityGate {
    nonisolated static func equal(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        return normalizeNewlines(a) == normalizeNewlines(b)
    }

    /// Normalize CRLF and bare CR to LF. Order matters: collapse CRLF first so a
    /// CRLF does not become two LFs.
    nonisolated static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
    }
}
