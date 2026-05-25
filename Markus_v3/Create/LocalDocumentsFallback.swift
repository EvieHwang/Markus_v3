import Foundation

/// Vends the app container's local Documents directory as the guaranteed-writable
/// fallback target for new-file creation (design C7 / DC-12).
///
/// Behavioral contract:
/// - Returns the URL of `FileManager`'s `.documentDirectory` in `.userDomainMask`.
/// - Creates the directory if it does not yet exist; the returned URL is guaranteed
///   to exist on disk and be writable.
enum LocalDocumentsFallback {

    static func documentsDirectory() throws -> URL {
        let fm = FileManager.default
        let url = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return url
    }
}
