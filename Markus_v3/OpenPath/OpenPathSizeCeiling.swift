import Foundation

/// Design-fixed file-size ceiling for the open path (DC-5, BR-4).
///
/// A file whose on-disk byte size is `<= maxBytes` is admitted to the
/// read stage; one whose size is strictly greater is rejected at the
/// pre-read gate with the too-large surface (BR-4.2). The value is
/// 20 MiB (20 × 1024 × 1024 = 20 971 520 bytes) and is not user-
/// configurable (OOS-6).
enum OpenPathSizeCeiling {
    static let maxBytes: Int = 20 * 1024 * 1024

    static func admits(byteSize: Int) -> Bool {
        byteSize <= maxBytes
    }
}
