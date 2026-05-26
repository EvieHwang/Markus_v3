import Foundation

/// Nonisolated `NSFilePresenter` bridge for the change detector (DC-1/DC-2).
///
/// `NSFilePresenter` callbacks arrive on `presentedItemOperationQueue` (off the
/// main actor), so the presenter cannot itself be `@MainActor`. This shim is a
/// thin nonisolated forwarder: it owns the presented URL and hops each filesystem
/// event onto the main actor, where `ChangeDetector` does coordinated reads and
/// classification. Detection is therefore grounded in coordinated file access and
/// presenter callbacks (BR-10) — never in interpreting `UIDocument.documentState`.
final class FilePresenterShim: NSObject, NSFilePresenter, @unchecked Sendable {
    private let url: URL
    let presentedItemOperationQueue: OperationQueue

    var onChange: (@Sendable () -> Void)?
    var onMove: (@Sendable (URL) -> Void)?
    var onDelete: (@Sendable () -> Void)?

    init(url: URL) {
        self.url = url
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.presentedItemOperationQueue = queue
        super.init()
    }

    var presentedItemURL: URL? { url }

    func register() {
        NSFileCoordinator.addFilePresenter(self)
    }

    func unregister() {
        NSFileCoordinator.removeFilePresenter(self)
    }

    func presentedItemDidChange() {
        onChange?()
    }

    func presentedItemDidMove(to newURL: URL) {
        onMove?(newURL)
    }

    func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        onDelete?()
        completionHandler(nil)
    }
}
