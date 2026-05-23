enum ActiveAlert: Identifiable {
    case saveFailed(DocumentError)
    case invalidEncoding
    case iCloudDownloadFailed

    var id: String {
        switch self {
        case .saveFailed: return "saveFailed"
        case .invalidEncoding: return "invalidEncoding"
        case .iCloudDownloadFailed: return "iCloudDownloadFailed"
        }
    }
}
