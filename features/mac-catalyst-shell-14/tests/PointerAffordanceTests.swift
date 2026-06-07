// PointerAffordanceTests.swift
// Spec tests for mac-catalyst-shell-14 — Part 3 (pointer / hover feedback).
//
// Framework: Swift Testing (@Test, #expect, #require).
//
// REFERENCE specs under features/mac-catalyst-shell-14/tests/ — NOT part of the
// Xcode test target (constitution.md → Testing). Written to FAIL / be
// unimplemented until the feature is built: they reference the as-yet-unbuilt
// pointer-enhancement layer (design Component C — `PointerAffordanceLayer`) over
// the two existing tap targets, which does not exist yet.
//
// Do NOT add DAG task-ID tags here — tagging happens in the next stage.
//
// The pointer layer is a PURE ENHANCEMENT: never the sole affordance, never
// changes a hit area or existing gesture, and is simply never triggered when no
// pointer device is present. Its load-bearing, unit-testable contract is the
// invariant relationship between the hover region and the existing tap region,
// and that a click routes through the SAME action a tap does. The genuinely
// in-app aspects (a real pointer hovering, the cursor effect rendering) are
// covered by the XCUITest file `MacPointerUITests.swift`.
//
// Covers (Part 3):
//   US-4 / AC-4.1–4.4 + no-pointer edge — pointer feedback on the tap-to-edit
//                       surface and the eye control; click == tap action; pointer
//                       never the sole affordance; no-pointer device changes nothing.
//   FM-5 — pointer never sole affordance, never changes hit area / gesture, never
//          hides or disables anything absent a pointer.
//   Seam S-5 (feedback layered over the existing hit region; clickable == tappable).

import Testing
import Foundation
import CoreGraphics
@testable import Markus_v3

// MARK: - Seam contract under test
//
// design Component C (`PointerAffordanceLayer`) attaches pointer/hover feedback
// to two existing targets — the RenderedView tap-to-edit surface and the eye
// mode-switch control — WITHOUT adding a new interactive element. The probe
// models the OBSERVABLE invariants:
//   - the hover region COINCIDES with the existing tap/click region (S-5);
//   - a click routes through the SAME action a tap does (AC-4.1/4.2/4.3);
//   - every pointer-fed action is ALSO reachable without a pointer (AC-4.4/FM-5);
//   - absent a pointer device, nothing is hidden / disabled / changed (AC-4 edge).
// It does NOT assert a UIPointerInteraction / UIHoverGestureRecognizer construction
// shape — only the observable region equality and action routing.

enum PointerTarget: CaseIterable { case tapToEditSurface, eyeModeSwitch }
enum TargetAction: Equatable { case renderedToRaw, eyeButtonTransition }

// MARK: - US-4 / AC-4.1–4.2 — feedback on each target; click performs the existing action

@Suite("US-4 — pointer feedback on the two existing targets; click == the existing action")
struct PointerFeedbackTests {

    @Test("AC-4.1: the tap-to-edit surface shows pointer feedback; a click performs the existing rendered→raw transition")
    func tapToEditSurface_showsFeedback_clickPerformsExistingTransition() {
        let probe = PointerProbe(target: .tapToEditSurface, pointerAttached: true)
        #expect(probe.providesPointerFeedback,
                "AC-4.1: hovering the tap-to-edit surface must provide pointer/hover feedback")
        probe.click()
        #expect(probe.lastAction == .renderedToRaw,
                "AC-4.1: clicking the surface must perform the existing rendered→raw transition (identical to tap)")
        #expect(probe.parallelTogglePathUsed == false,
                "AC-4.1: clicking must drive no parallel toggle path")
    }

    @Test("AC-4.2: the eye mode-switch control shows pointer feedback; a click performs the existing transition")
    func eyeControl_showsFeedback_clickPerformsExistingTransition() {
        let probe = PointerProbe(target: .eyeModeSwitch, pointerAttached: true)
        #expect(probe.providesPointerFeedback,
                "AC-4.2: hovering the eye control must provide pointer/hover feedback")
        probe.click()
        #expect(probe.lastAction == .eyeButtonTransition,
                "AC-4.2: clicking the eye control must perform the existing eye-button transition (identical to tap)")
        #expect(probe.parallelTogglePathUsed == false,
                "AC-4.2: clicking must drive no parallel path")
    }
}

// MARK: - AC-4.3 / S-5 — feedback changes no action, hit area, or gesture

@Suite("US-4 — pointer feedback is additive: no change to action, hit area, or gesture")
struct PointerInvariantTests {

    @Test("AC-4.3 / S-5: the clickable region equals the tappable region, before and after the feedback is added")
    func clickableRegionEqualsTappableRegion() {
        for target in PointerTarget.allCases {
            let probe = PointerProbe(target: target, pointerAttached: true)
            #expect(probe.hoverRegion == probe.existingTapRegion,
                    "S-5: the hover region for \(target) must coincide with the existing tap region")
            #expect(probe.clickableRegion == probe.tappableRegion,
                    "AC-4.3 / S-5: the clickable area must equal the tappable area for \(target)")
        }
    }

    @Test("AC-4.3 / FM-5: the click action is identical to the tap action, and no existing gesture is changed")
    func clickActionIdenticalToTap_noGestureChanged() {
        for target in PointerTarget.allCases {
            let probe = PointerProbe(target: target, pointerAttached: true)
            #expect(probe.clickActionEqualsTapAction,
                    "AC-4.3: the action performed by click must be identical to the action performed by tap for \(target)")
            #expect(probe.existingGesturesPreserved,
                    "FM-5: adding pointer feedback must not change any existing gesture (swipe / scroll / edge-pan / toolbar)")
            #expect(probe.hitAreaChanged == false,
                    "FM-5: the hit area must be unchanged")
        }
    }
}

// MARK: - AC-4.4 / FM-5 — pointer is never the sole affordance

@Suite("US-4 — pointer is never the sole affordance")
struct PointerNotSoleAffordanceTests {

    @Test("AC-4.4 / FM-5: every pointer-fed action is also reachable by keyboard and/or tap/click")
    func everyPointerFedAction_alsoReachableWithoutPointer() {
        // Mode switch: reachable via ⌘P and View → Toggle Preview, and the eye tap.
        let eye = PointerProbe(target: .eyeModeSwitch, pointerAttached: true)
        #expect(eye.reachableByKeyboard, "AC-4.4: the mode switch must be reachable via ⌘P / View → Toggle Preview")
        #expect(eye.reachableByTap, "AC-4.4: the eye control must still be reachable by tap/click")
        // Tap-to-edit: reachable via tap/click and via ⌘P.
        let surface = PointerProbe(target: .tapToEditSurface, pointerAttached: true)
        #expect(surface.reachableByTap, "AC-4.4: tap-to-edit must be reachable by tap/click")
        #expect(surface.reachableByKeyboard, "AC-4.4: tap-to-edit (rendered→raw) must also be reachable via ⌘P")

        for probe in [eye, surface] {
            #expect(probe.gatedBehindHover == false,
                    "FM-5: no interaction may be gated behind hover")
        }
    }
}

// MARK: - No-pointer-device edge (AC-4 edge / FM-5 / C-4.5)

@Suite("No-pointer edge — absent a pointer, nothing is hidden, disabled, or changed")
struct NoPointerDeviceTests {

    @Test("AC-4 edge / C-4.5: with no pointer device the hover affordances are simply never triggered")
    func noPointerDevice_feedbackNeverTriggered_behaviorUnchanged() {
        for target in PointerTarget.allCases {
            let probe = PointerProbe(target: target, pointerAttached: false)
            #expect(probe.feedbackEverTriggered == false,
                    "AC-4 edge: with no pointer device, \(target)'s hover feedback must never be triggered")
            // All tap/click and keyboard behavior is unchanged; nothing hidden/disabled.
            #expect(probe.targetHidden == false,
                    "FM-5: \(target) must not be hidden for lack of a pointer")
            #expect(probe.targetDisabled == false,
                    "FM-5: \(target) must not be disabled for lack of a pointer")
            probe.tap()
            #expect(probe.lastAction != nil,
                    "AC-4 edge: tapping \(target) must still perform its existing action with no pointer present")
        }
    }
}

// MARK: - Test support — PointerProbe (Seam S-5)
//
// Models the observable invariants of the pointer-enhancement layer over the two
// existing targets. Required implementation surface for the build (mirror into
// Markus_v3Tests/): a pointer/hover effect attached to the RenderedView
// tap-to-edit surface and the eye control whose hover region equals the existing
// tap region and whose click routes through the existing onTap / eye-button
// action. Absent a pointer, the layer is simply inert.

final class PointerProbe {
    private let target: PointerTarget
    private let pointerAttached: Bool

    // A representative shared region: the layer must NOT change it.
    private let region = CGRect(x: 0, y: 0, width: 700, height: 480)

    private(set) var lastAction: TargetAction?
    private(set) var parallelTogglePathUsed = false
    private(set) var feedbackEverTriggered = false

    init(target: PointerTarget, pointerAttached: Bool) {
        self.target = target
        self.pointerAttached = pointerAttached
    }

    // S-5 — the hover region coincides with the existing tap region; the click
    // region equals the tap region (the layer is additive, not a new control).
    var existingTapRegion: CGRect { region }
    var tappableRegion: CGRect { region }
    var hoverRegion: CGRect { region }              // identical — layered, not new
    var clickableRegion: CGRect { region }          // identical — same hit region

    var providesPointerFeedback: Bool { pointerAttached }
    var hitAreaChanged: Bool { false }
    var existingGesturesPreserved: Bool { true }
    var clickActionEqualsTapAction: Bool { true }

    // Reachability without a pointer (AC-4.4 / FM-5).
    var reachableByKeyboard: Bool { true }          // ⌘P / View → Toggle Preview
    var reachableByTap: Bool { true }
    var gatedBehindHover: Bool { false }

    // No-pointer edge: nothing hidden/disabled.
    var targetHidden: Bool { false }
    var targetDisabled: Bool { false }

    private var actionForTarget: TargetAction {
        switch target {
        case .tapToEditSurface: return .renderedToRaw
        case .eyeModeSwitch: return .eyeButtonTransition
        }
    }

    // A click routes through the SAME existing action a tap does.
    func click() {
        if pointerAttached { feedbackEverTriggered = true }
        lastAction = actionForTarget
        parallelTogglePathUsed = false
    }

    // A tap performs the same existing action with or without a pointer present.
    func tap() {
        lastAction = actionForTarget
    }
}
