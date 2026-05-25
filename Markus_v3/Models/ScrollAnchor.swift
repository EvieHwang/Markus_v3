import Foundation

struct ScrollAnchor: Sendable, Equatable {
    nonisolated static let top = ScrollAnchor(fractionalY: 0)

    let fractionalY: Double

    nonisolated init(fractionalY: Double) {
        if fractionalY.isNaN || !fractionalY.isFinite {
            self.fractionalY = 0
        } else {
            self.fractionalY = min(1, max(0, fractionalY))
        }
    }
}
