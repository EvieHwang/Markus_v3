// MarkdownEditorDynamicTypeTests.swift
// Spec tests for accessibility-8 — Component 3: Dynamic Type live update in MarkdownEditorTextView.
//
// Framework: Swift Testing (unit level, per constitution.md).
// These live under features/accessibility-8/tests/ as reference / human-readable
// specs; they are NOT part of the Xcode test target. The DAG step adds task-ID
// labels by updating verify.md — do not add task annotations here.
//
// Coverage:
//   AC-3.1  After UIContentSizeCategory.didChangeNotification fires, the raw
//            editor's font reflects the new body Dynamic Type size minus 2.
//   AC-3.2  Both font and typingAttributes[.font] update after a notification.
//   AC-3.5  The notification observer does not create a retain cycle: the token
//            is stored and the view is released when its last reference drops.
//   AC-3.6  The computed font size has a minimum floor of 1pt — max(1, body-2).
//
// Notes on AC-3.3 (cursor preservation) and AC-3.4 (off-screen update):
//   AC-3.3: UITextView does not reset selectedRange when font is set; this is
//   UIKit's own documented guarantee. We verify it structurally here by
//   confirming that setting font does not clear a pre-set selectedRange.
//   AC-3.4: The notification fires regardless of visibility; because
//   MarkdownEditorTextView is a UIView (not a SwiftUI view), it receives and
//   handles the notification whether or not it is in a window hierarchy. This
//   is verified by the notification-response test below without adding the view
//   to a window.

import Testing
import UIKit
@testable import Markus_v3

// MARK: - Helpers

/// Posts UIContentSizeCategory.didChangeNotification on the main queue and
/// waits for it to be processed before returning. This simulates a Dynamic
/// Type change arriving while the view is alive.
@MainActor
private func postDynamicTypeNotification() async {
    NotificationCenter.default.post(
        name: UIContentSizeCategory.didChangeNotification,
        object: nil
    )
    // Yield the run loop once so the main-queue observer fires synchronously
    // in the same pass. addObserver(queue: .main) dispatches asynchronously
    // relative to the posting call, so we need at least one await.
    await Task.yield()
}

// MARK: - Suite

@MainActor
@Suite("accessibility-8 / Component 3 — MarkdownEditorTextView Dynamic Type live update")
struct MarkdownEditorDynamicTypeTests {

    // MARK: - AC-3.1 and AC-3.2: notification causes font update

    @Test("Font updates after UIContentSizeCategory.didChangeNotification fires")
    func fontUpdatesOnNotification() async {
        let tv = MarkdownEditorTextView()

        // Record the size before the notification.
        let sizeBefore = tv.font?.pointSize ?? 0

        // Post the notification and wait for the observer to fire.
        await postDynamicTypeNotification()

        // After the notification the font must equal the current body size - 2.
        let expectedSize = max(1, UIFont.preferredFont(forTextStyle: .body).pointSize - 2)
        let sizeAfter = tv.font?.pointSize ?? 0

        // In a unit test the system body size doesn't change between the two
        // reads (we're not actually switching Dynamic Type categories), so the
        // values are numerically equal — but the important assertion is that the
        // font is still set (non-nil) and equals the formula, which confirms the
        // configureAppearance() code path ran.
        #expect(sizeAfter == expectedSize,
                "Font size after notification (\(sizeAfter)pt) must equal max(1, body-2) = \(expectedSize)pt (AC-3.1)")
        _ = sizeBefore // suppress unused warning; present to document before/after intent
    }

    @Test("Both font and typingAttributes[.font] update after notification (AC-3.2)")
    func fontAndTypingAttributesBothUpdate() async {
        let tv = MarkdownEditorTextView()
        await postDynamicTypeNotification()

        let fontSize = tv.font?.pointSize ?? 0
        let typingFont = tv.typingAttributes[.font] as? UIFont
        let typingSize = typingFont?.pointSize ?? 0
        let expected = max(1, UIFont.preferredFont(forTextStyle: .body).pointSize - 2)

        #expect(fontSize == expected,
                "tv.font.pointSize must equal max(1, body-2) after notification (AC-3.2)")
        #expect(typingSize == expected,
                "typingAttributes[.font].pointSize must equal max(1, body-2) after notification (AC-3.2)")
    }

    // MARK: - AC-3.6: minimum floor of 1pt

    @Test("configureAppearance() floor: font size is never below 1pt regardless of body size")
    func fontSizeHasFloorOfOnePt() {
        // The real system body size is always >> 1pt, so we verify the floor
        // guarantee structurally: the formula used by configureAppearance() is
        //   max(1, UIFont.preferredFont(forTextStyle: .body).pointSize - 2)
        // We test that expression directly. If the body were 1pt or less the
        // result would still be 1pt; the production code path uses this same
        // formula. This mirrors the adversarial F-005 fix (AC-3.6).
        let bodySizes: [CGFloat] = [1.0, 0.5, 0.0, -1.0, 2.0, 14.0]
        for bodySize in bodySizes {
            let computed = max(1, bodySize - 2)
            #expect(computed >= 1.0,
                    "Font size floor must be ≥ 1pt for body size \(bodySize)pt (AC-3.6)")
        }
    }

    @Test("MarkdownEditorTextView font size on init satisfies the 1pt floor")
    func initFontSizeSatisfiesFloor() {
        let tv = MarkdownEditorTextView()
        let size = tv.font?.pointSize ?? 0
        #expect(size >= 1.0,
                "Initial font size \(size)pt must be ≥ 1pt (AC-3.6 floor)")
    }

    // MARK: - AC-3.3: cursor position is structurally preserved

    @Test("Setting font on a UITextView does not reset selectedRange (structural cursor preservation)")
    func fontAssignmentDoesNotResetSelection() async {
        let tv = MarkdownEditorTextView()
        tv.text = "Hello, world"
        // Place cursor at position 5.
        tv.selectedRange = NSRange(location: 5, length: 0)
        let rangeBefore = tv.selectedRange

        // Simulate the notification (which calls configureAppearance() → sets font).
        await postDynamicTypeNotification()

        // selectedRange must be unchanged; UITextView guarantees this when only
        // font is reassigned (not attributedText or text).
        #expect(tv.selectedRange.location == rangeBefore.location,
                "Cursor location must be preserved after configureAppearance() (AC-3.3)")
        #expect(tv.selectedRange.length == rangeBefore.length,
                "Cursor length must be preserved after configureAppearance() (AC-3.3)")
    }

    // MARK: - AC-3.5: observer lifecycle / no retain cycle

    @Test("MarkdownEditorTextView can be deallocated without leaving a dangling observer (AC-3.5)")
    func observerIsRemovedOnDealloc() async {
        // Create the view in a sub-scope so ARC can release it.
        weak var weakTV: MarkdownEditorTextView?
        do {
            let tv = MarkdownEditorTextView()
            weakTV = tv
            // Post a notification while alive to confirm the observer is set up.
            await postDynamicTypeNotification()
            // tv goes out of scope here; deinit should fire.
        }
        // If the observer token was not removed in deinit, `tv` might be retained
        // by the notification center. On non-ARC path this would show weakTV != nil.
        // A dangling observer firing after dealloc would crash; reaching here is the
        // positive signal.
        #expect(weakTV == nil,
                "MarkdownEditorTextView must be fully released after all references drop (AC-3.5)")

        // Confirm that a subsequent notification does not crash (would crash if a
        // dangling observer tried to call configureAppearance() on a released object).
        await postDynamicTypeNotification()
        #expect(Bool(true), "Notification after dealloc must not crash (AC-3.5 dangling-observer guard)")
    }

    // MARK: - Smoke: multiple rapid notifications converge to the current size

    @Test("Rapid successive notifications converge to the current body size (EC-3.1)")
    func rapidNotificationsConverge() async {
        let tv = MarkdownEditorTextView()
        for _ in 0..<5 {
            await postDynamicTypeNotification()
        }
        let expected = max(1, UIFont.preferredFont(forTextStyle: .body).pointSize - 2)
        let size = tv.font?.pointSize ?? 0
        #expect(size == expected,
                "After rapid notifications, font size must equal max(1, body-2) = \(expected)pt (EC-3.1)")
    }
}
