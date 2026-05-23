import Foundation

enum DocumentError: Error, Equatable {
    case invalidEncoding
    case saveFailed(underlying: Error)
    case fileMissing
    case iCloudDownloadFailed

    static func == (lhs: DocumentError, rhs: DocumentError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidEncoding, .invalidEncoding),
             (.fileMissing, .fileMissing),
             (.iCloudDownloadFailed, .iCloudDownloadFailed):
            return true
        case let (.saveFailed(l), .saveFailed(r)):
            return (l as NSError) == (r as NSError)
        default:
            return false
        }
    }
}
