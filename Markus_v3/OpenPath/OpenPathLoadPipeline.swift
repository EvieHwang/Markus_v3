import Foundation

/// Pure classification + failure shim for the open-path pipeline. The
/// integration that wires these to the live security-scoped read lives
/// in `BrowserHostController` (T-005). Keeping classification side-effect
/// free is what lets DC-4's size-first ordering be tested without touching
/// the file system.
enum OpenPathLoadPipeline {

    /// One of three terminal classifications the pre-decode gate emits.
    /// `.tooLarge` short-circuits before the decode probe is inspected
    /// (DC-4) — size-first ordering means an oversized binary file never
    /// reaches the decode stage and therefore cannot OOM the open path.
    enum Classification: Equatable {
        case ok
        case tooLarge
        case invalidEncoding
    }

    /// DC-4 / DC-5 — size precedes decode. When `byteSize > maxBytes` the
    /// result is `.tooLarge` and `bytesForDecodeProbe` is never inspected
    /// (callers may pass empty `Data` when they only have the size). When
    /// size is admitted, the bytes are strict-UTF-8-decoded; failure
    /// returns `.invalidEncoding`. Otherwise `.ok`.
    static func classify(byteSize: Int, bytesForDecodeProbe: Data) -> Classification {
        guard OpenPathSizeCeiling.admits(byteSize: byteSize) else {
            return .tooLarge
        }
        // A leading UTF-8 BOM is valid input; the BOM bytes are stripped
        // before the strict-UTF-8 decode probe so `String(data:.utf8)`'s
        // BOM handling (which strips silently) doesn't mask a non-UTF-8
        // tail. (Buffer-level BOM retention is MarkdownDocument's job.)
        let probe: Data = bytesForDecodeProbe.starts(with: [0xEF, 0xBB, 0xBF])
            ? bytesForDecodeProbe.dropFirst(3)
            : bytesForDecodeProbe
        if String(data: probe, encoding: .utf8) == nil {
            return .invalidEncoding
        }
        return .ok
    }

    /// Convenience that returns a `.alert(...)` `OpenPathLoadResult` for
    /// any error, so the caller can wire `do { ... } catch` cleanly
    /// without re-implementing the BR-3.5 invariant at each site.
    static func failureResult(for error: Error) -> OpenPathLoadResult {
        .alert(OpenPathFailureMapper.alert(for: error))
    }
}
