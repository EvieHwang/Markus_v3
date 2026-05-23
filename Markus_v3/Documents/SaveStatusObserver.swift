import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SaveStatusObserver {
    var lastSaveError: DocumentError?
    var isDownloadingFromiCloud: Bool = false

    @ObservationIgnored private var token: NSObjectProtocol?

    init() {
        self.token = NotificationCenter.default.addObserver(
            forName: UIDocument.stateChangedNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handle(notification: notification)
            }
        }
    }

    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func handle(notification: Notification) {
        guard let doc = notification.object as? UIDocument else { return }
        let state = doc.documentState
        if state.contains(.savingError) {
            lastSaveError = .saveFailed(underlying: NSError(
                domain: "UIDocument.savingError",
                code: 0,
                userInfo: nil
            ))
        }
        isDownloadingFromiCloud = state.contains(.editingDisabled)
    }
}
