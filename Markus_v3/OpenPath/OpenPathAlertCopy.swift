import Foundation

/// User-facing copy for the open-path alert surfaces (DC-7).
///
/// Each of the five cases the open path can surface returns a distinct,
/// human-actionable string. The encoding-error case reuses the existing
/// `ActiveAlert.invalidEncoding` and is included here so the alert host
/// can resolve every open-path alert through one mapping; cases outside
/// the open-path set (`.saveFailed`, `.iCloudDownloadFailed`) are not
/// resolved here and the caller falls back to its own copy.
enum OpenPathAlertCopy {
    static func message(for alert: ActiveAlert) -> String {
        switch alert {
        case .invalidEncoding:
            return String(localized: "This file isn't UTF-8 and can't be opened in Markus.")
        case .permissionDenied:
            return String(localized: "Markus doesn't have permission to read this file. Re-pick it from the browser to grant access.")
        case .fileMovedOrRemoved:
            return String(localized: "This file is no longer at the location you picked.")
        case .couldNotReadFile:
            return String(localized: "Markus couldn't read this file.")
        case .tooLarge:
            return String(localized: "This file is too large for Markus to open.")
        case .saveFailed, .iCloudDownloadFailed:
            return ""
        }
    }
}
