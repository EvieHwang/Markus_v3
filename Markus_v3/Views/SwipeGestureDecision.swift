import Foundation
import CoreGraphics

/// Pure decision logic for swipe-to-mode-switch gestures on the raw editor and
/// rendered view (design C3 / NPC-9 / NPC-18 / NPC-19 / NPC-20 / NPC-22).
///
/// Encapsulates the conflict-avoidance heuristics so that gesture wiring in
/// SwiftUI views stays mechanical (just plumb the values through) and the
/// behavioral rules are testable as a pure function.
enum SwipeGestureDecision {

    enum Direction {
        /// Leading-to-trailing finger motion (positive `translation.width`).
        case leftToRight
        /// Trailing-to-leading finger motion (negative `translation.width`).
        case rightToLeft
    }

    /// Decides whether a gesture should be claimed as a mode-switch swipe.
    /// Returns `nil` when the gesture should be ignored (text selection,
    /// vertical scroll, content-scroll position, edge-pan zone, or below
    /// thresholds).
    static func detect(
        translation: CGSize,
        velocity: CGSize,
        startX: CGFloat,
        contentHorizontallyScrollable: Bool = false,
        edgeZone: CGFloat = 20,
        minTranslation: CGFloat = 50,
        minVelocity: CGFloat = 200
    ) -> Direction? {
        // NPC-22: near-edge L→R is claimed by the system edge-pan recognizer.
        if startX <= edgeZone && translation.width > 0 {
            return nil
        }
        // NPC-18: a dominantly vertical gesture is scroll, not a mode switch.
        guard abs(translation.width) > abs(translation.height) * 1.5 else {
            return nil
        }
        // NPC-19: horizontal scroll position takes priority over the swipe.
        if contentHorizontallyScrollable {
            return nil
        }
        // NPC-20: minimum thresholds suppress short / slow drags (selection extension).
        guard abs(translation.width) > minTranslation else { return nil }
        guard abs(velocity.width) > minVelocity else { return nil }
        return translation.width > 0 ? .leftToRight : .rightToLeft
    }
}
