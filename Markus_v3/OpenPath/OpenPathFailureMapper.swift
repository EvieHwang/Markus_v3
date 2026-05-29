import Foundation

/// Maps an `Error` raised by the load pipeline to the `ActiveAlert` the
/// user sees (DC-8). Deterministic where the OS unambiguously names the
/// failure class; everything else falls into `.couldNotReadFile` so the
/// user is never left with a silent no-op.
enum OpenPathFailureMapper {
    static func alert(for error: Error) -> ActiveAlert {
        if let documentError = error as? DocumentError {
            switch documentError {
            case .invalidEncoding:
                return .invalidEncoding
            case .iCloudDownloadFailed:
                return .iCloudDownloadFailed
            case .fileMissing:
                return .fileMovedOrRemoved
            case .saveFailed:
                return .couldNotReadFile
            }
        }

        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError),
             (NSCocoaErrorDomain, NSFileWriteNoPermissionError):
            return .permissionDenied
        case (NSCocoaErrorDomain, NSFileReadNoSuchFileError),
             (NSCocoaErrorDomain, NSFileNoSuchFileError):
            return .fileMovedOrRemoved
        case (NSPOSIXErrorDomain, Int(EACCES)),
             (NSPOSIXErrorDomain, Int(EPERM)):
            return .permissionDenied
        case (NSPOSIXErrorDomain, Int(ENOENT)):
            return .fileMovedOrRemoved
        default:
            return .couldNotReadFile
        }
    }
}
