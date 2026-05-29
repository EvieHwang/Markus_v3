import Foundation

/// Caller-facing seam for the open path (BR-3.5, DC-1).
///
/// Two-case sum proves at the type level that there is no third
/// "silent return" branch: every open attempt terminates either in a
/// `MarkdownDocument` for the editor to present or in an `ActiveAlert`
/// for the host to surface.
enum OpenPathLoadResult {
    case document(MarkdownDocument)
    case alert(ActiveAlert)
}
