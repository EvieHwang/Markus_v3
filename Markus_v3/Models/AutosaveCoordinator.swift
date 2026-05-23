import Foundation
import Observation

@MainActor
@Observable
final class AutosaveCoordinator {
    static let idleDelay: Duration = .milliseconds(500)

    @ObservationIgnored private let onIdle: @MainActor () -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(onIdle: @escaping @MainActor () -> Void) {
        self.onIdle = onIdle
    }

    func textChanged() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.idleDelay)
                try Task.checkCancellation()
                self?.onIdle()
            } catch {
                // cancelled — superseded by a later textChanged()
            }
        }
    }
}
