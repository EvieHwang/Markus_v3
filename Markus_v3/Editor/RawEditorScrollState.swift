import Combine
import Foundation

@MainActor
final class RawEditorScrollState: ObservableObject {
    var currentFractionalY: Double = 0
}
