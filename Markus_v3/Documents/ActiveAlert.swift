enum ActiveAlert: Identifiable, Equatable {
    case saveFailed(DocumentError)
    case invalidEncoding
    case iCloudDownloadFailed

    // open-path-hardening-10 — four open-path failure surfaces share the
    // existing alert channel (DC-6, BR-5.1).
    case permissionDenied
    case fileMovedOrRemoved
    case couldNotReadFile
    case tooLarge

    var id: String {
        switch self {
        case .saveFailed: return "saveFailed"
        case .invalidEncoding: return "invalidEncoding"
        case .iCloudDownloadFailed: return "iCloudDownloadFailed"
        case .permissionDenied: return "permissionDenied"
        case .fileMovedOrRemoved: return "fileMovedOrRemoved"
        case .couldNotReadFile: return "couldNotReadFile"
        case .tooLarge: return "tooLarge"
        }
    }
}
