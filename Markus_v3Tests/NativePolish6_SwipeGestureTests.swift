// NativePolish6_SwipeGestureTests.swift
// Wave-3 T-007 tests for native-polish-6 — NP-4 / NP-5 / NP-6 / C3 seam:
// SwipeGestureDecision pure-function contract.
//
// The decision function is the testable core of the swipe-to-mode-switch
// behavior. The UIKit/SwiftUI wiring in RawEditorView/RenderedView plumbs
// DragGesture values into this function; conflict-avoidance rules
// (NPC-9 / NPC-18 / NPC-19 / NPC-20 / NPC-22) are all expressed here.

import Testing
import Foundation
import CoreGraphics
@testable import Markus_v3

@Suite("NP-4/5/6 — SwipeGestureDecision contract")
struct SwipeGestureDecisionTests {

    // MARK: NP-4 — R→L swipe on raw editor (caller filters to .rightToLeft)

    @Test("Clear R→L drag returns .rightToLeft direction")
    func clearRightToLeftDrag() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: -120, height: 10),
            velocity: CGSize(width: -500, height: 0),
            startX: 200
        )
        #expect(dir == .rightToLeft)
    }

    // MARK: NP-6 — L→R swipe on rendered (caller filters to .leftToRight)

    @Test("Clear L→R drag outside edge zone returns .leftToRight direction")
    func clearLeftToRightDragMidScreen() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: 120, height: 10),
            velocity: CGSize(width: 500, height: 0),
            startX: 200
        )
        #expect(dir == .leftToRight)
    }

    // MARK: NPC-22 — edge zone: edge-pan takes priority, swipe yields

    @Test("L→R drag in edge zone (startX <= 20) returns nil")
    func leftToRightInEdgeZoneSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: 150, height: 8),
            velocity: CGSize(width: 600, height: 0),
            startX: 10
        )
        #expect(dir == nil, "Edge-pan zone L→R must yield to system edge recognizer (NPC-22)")
    }

    // Important: R→L starting near the leading edge is still legal (the edge
    // recognizer only fires L→R), so a negative-translation drag starting at
    // startX=10 is still a normal R→L swipe.
    @Test("R→L drag at edge zone is NOT suppressed (edge recognizer only owns L→R)")
    func rightToLeftAtEdgeNotSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: -120, height: 5),
            velocity: CGSize(width: -500, height: 0),
            startX: 10
        )
        #expect(dir == .rightToLeft)
    }

    // MARK: NPC-18 — vertical scroll dominates

    @Test("Dominantly vertical drag returns nil")
    func verticalDragSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: 20, height: 200),
            velocity: CGSize(width: 50, height: 800),
            startX: 200
        )
        #expect(dir == nil, "Vertical drag must yield to scroll (NPC-18)")
    }

    @Test("Vertical drag with mild horizontal component is still suppressed")
    func mildlyHorizontalVerticalSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: 40, height: 100),
            velocity: CGSize(width: 100, height: 400),
            startX: 200
        )
        #expect(dir == nil, "|dx|=40 < |dy|*1.5=150, must be suppressed")
    }

    // MARK: NPC-19 — horizontal content scroll yields

    @Test("Horizontal content scroll position suppresses swipe")
    func horizontallyScrollableContentSuppresses() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: 120, height: 5),
            velocity: CGSize(width: 500, height: 0),
            startX: 200,
            contentHorizontallyScrollable: true
        )
        #expect(dir == nil, "Horizontal content scroll takes priority (NPC-19)")
    }

    // MARK: NPC-20 — minimum velocity/translation thresholds

    @Test("Below translation threshold returns nil (selection-extension drag)")
    func belowTranslationThresholdSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: -30, height: 5),
            velocity: CGSize(width: -300, height: 0),
            startX: 200
        )
        #expect(dir == nil, "|dx|=30 < 50pt threshold (NPC-20)")
    }

    @Test("Below velocity threshold returns nil (slow drag)")
    func belowVelocityThresholdSuppressed() {
        let dir = SwipeGestureDecision.detect(
            translation: CGSize(width: -120, height: 5),
            velocity: CGSize(width: -80, height: 0),
            startX: 200
        )
        #expect(dir == nil, "|vx|=80 < 200pt/s threshold (NPC-20)")
    }

    @Test("Exactly at threshold (boundary)")
    func atThresholdBoundary() {
        // strictly greater than → 51, 201 should pass
        let pass = SwipeGestureDecision.detect(
            translation: CGSize(width: -51, height: 5),
            velocity: CGSize(width: -201, height: 0),
            startX: 200
        )
        #expect(pass == .rightToLeft)
        // exactly at threshold should fail
        let fail = SwipeGestureDecision.detect(
            translation: CGSize(width: -50, height: 5),
            velocity: CGSize(width: -200, height: 0),
            startX: 200
        )
        #expect(fail == nil)
    }
}
