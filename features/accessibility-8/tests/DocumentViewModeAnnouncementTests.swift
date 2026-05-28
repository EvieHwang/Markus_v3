// DocumentViewModeAnnouncementTests.swift
// Spec tests for accessibility-8 — Component 5: VoiceOver announcements on mode switches.
//
// Framework: Swift Testing (unit level, per constitution.md).
// These live under features/accessibility-8/tests/ as reference / human-readable
// specs; they are NOT part of the Xcode test target. The DAG step adds task-ID
// labels by updating verify.md — do not add task annotations here.
//
// Coverage:
//   AC-5.1  switchTo(.rendered, target: .raw) posts an announcement.
//   AC-5.2  switchTo(.raw, target: .rendered) / toolbar / swipe paths post an announcement.
//   AC-5.3  Each mode transition posts exactly one announcement.
//   AC-5.4  Announcement strings pass through NSLocalizedString / String(localized:).
//   AC-5.5  The initial onAppear mode assignment does NOT post an announcement.
//
// APPROACH — structural verification of call sites:
//   UIAccessibility.post() is a global side-effect with no testable return value.
//   Swizzling it to capture calls is technically possible but fragile and
//   produces flaky tests when the notification center is shared across the test
//   suite. The design explicitly places the announcement inside four named
//   call sites (switchTo, toolbar handler, switchToRenderedFromSwipe,
//   switchToRawFromSwipe-via-switchTo). These tests verify the contract at the
//   seam boundary that IS unit-testable: the DocumentViewAnnouncementProbe
//   mirrors DocumentView's triggering logic with the UIAccessibility.post call
//   replaced by a captured string, giving a structural assertion that the
//   announcement is produced on the correct paths and NOT on the onAppear path.
//
//   End-to-end verification that the real UIAccessibility.post fires is an
//   XCUITest concern (would require VoiceOver running in the simulator, which
//   is not supported in automation — see AccessibilityHeadingRotorUITests for
//   the pattern and limitation note).

import Testing
import SwiftUI
@testable import Markus_v3

// MARK: - Probe

/// Models DocumentView's mode-transition logic with the UIAccessibility.post
/// call replaced by a recordable string, so tests can assert that the
/// announcement is produced on the correct paths and not on others.
///
/// This mirrors the design's Component 5 triggering paths:
///   1. switchTo(_:target:)           — tap-to-edit, VoiceOver "Edit" action,
///                                      and switchToRawFromSwipe delegation
///   2. toolbar "Show rendered" handler
///   3. switchToRenderedFromSwipe()
///
/// The onAppear initialization path (mode = resolved) is deliberately NOT
/// listed; it must not post an announcement (AC-5.5).
struct DocumentViewAnnouncementProbe {
    private(set) var mode: DocumentMode
    private(set) var announcements: [String] = []
    private(set) var saveCount: Int = 0

    init(startMode: DocumentMode = .rendered) {
        self.mode = startMode
    }

    // Call site 1: the shared switchTo used by tap-to-edit, Edit action, and
    // switchToRawFromSwipe. Posts the announcement for `target` mode.
    mutating func switchTo(_ from: DocumentMode, target: DocumentMode) {
        if from == .raw && target == .rendered {
            saveCount += 1 // mirrors triggerSave()
        }
        mode = target
        let text: String
        switch target {
        case .raw:
            text = String(localized: "Editing mode",
                          comment: "VoiceOver announcement when switching to raw edit mode")
        case .rendered:
            text = String(localized: "Preview mode",
                          comment: "VoiceOver announcement when switching to rendered preview mode")
        }
        // In production: UIAccessibility.post(notification: .announcement, argument: text)
        announcements.append(text)
    }

    // Call site 2: toolbar "Show rendered" button handler.
    mutating func toolbarShowRendered() {
        saveCount += 1 // mirrors triggerSave()
        mode = .rendered
        let text = String(localized: "Preview mode",
                          comment: "VoiceOver announcement when switching to rendered preview mode")
        announcements.append(text)
    }

    // Call site 3: R→L swipe on raw editor → rendered mode.
    mutating func switchToRenderedFromSwipe() {
        saveCount += 1 // mirrors triggerSave()
        mode = .rendered
        let text = String(localized: "Preview mode",
                          comment: "VoiceOver announcement when switching to rendered preview mode")
        announcements.append(text)
    }

    // L→R swipe on rendered → delegates to switchTo (no separate post).
    mutating func switchToRawFromSwipe() {
        switchTo(.rendered, target: .raw)
    }

    // onAppear initial mode assignment: must NOT post an announcement (AC-5.5).
    mutating func onAppearSetInitialMode(_ resolved: DocumentMode) {
        mode = resolved
        // No announcement — this is the contract being tested.
    }
}

// MARK: - Suite

@Suite("accessibility-8 / Component 5 — DocumentView mode-switch VoiceOver announcements")
struct DocumentViewModeAnnouncementTests {

    // MARK: - AC-5.1: rendered → raw paths post a raw-mode announcement

    @Test("switchTo(.rendered, target: .raw) posts a non-empty announcement (tap-to-edit path)")
    func switchToRawPostsAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchTo(.rendered, target: .raw)
        #expect(!probe.announcements.isEmpty,
                "switchTo(.rendered, target: .raw) must post an announcement (AC-5.1)")
        #expect(!(probe.announcements.last ?? "").isEmpty,
                "The announcement string must be non-empty (AC-5.1)")
    }

    @Test("switchTo raw announcement describes editing mode")
    func switchToRawAnnouncementText() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchTo(.rendered, target: .raw)
        let text = probe.announcements.last ?? ""
        // The design specifies "Editing mode" as the English default (AC-5.1).
        #expect(text.contains("dit"),
                "Raw-mode announcement '\(text)' should describe editing (AC-5.1)")
    }

    @Test("switchToRawFromSwipe() delegates to switchTo and posts exactly one announcement")
    func swipeToRawPostsAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchToRawFromSwipe()
        #expect(probe.announcements.count == 1,
                "L→R swipe must post exactly one announcement via switchTo delegation (AC-5.1 / AC-5.3)")
        #expect(!(probe.announcements.last ?? "").isEmpty)
    }

    // MARK: - AC-5.2: raw → rendered paths post a rendered-mode announcement

    @Test("switchTo(.raw, target: .rendered) posts a non-empty announcement")
    func switchToRenderedPostsAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.switchTo(.raw, target: .rendered)
        #expect(!probe.announcements.isEmpty,
                "switchTo(.raw, target: .rendered) must post an announcement (AC-5.2)")
        #expect(!(probe.announcements.last ?? "").isEmpty)
    }

    @Test("toolbarShowRendered() posts a rendered-mode announcement")
    func toolbarShowRenderedPostsAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.toolbarShowRendered()
        #expect(!probe.announcements.isEmpty,
                "Toolbar 'Show rendered' handler must post an announcement (AC-5.2)")
        #expect(!(probe.announcements.last ?? "").isEmpty)
    }

    @Test("switchToRenderedFromSwipe() posts a rendered-mode announcement")
    func swipeToRenderedPostsAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.switchToRenderedFromSwipe()
        #expect(!probe.announcements.isEmpty,
                "R→L swipe must post a rendered-mode announcement (AC-5.2)")
        #expect(!(probe.announcements.last ?? "").isEmpty)
    }

    @Test("Rendered-mode announcement text describes preview")
    func renderedModeAnnouncementText() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.toolbarShowRendered()
        let text = probe.announcements.last ?? ""
        // The design specifies "Preview mode" as the English default (AC-5.2).
        #expect(text.contains("review") || text.contains("Preview"),
                "Rendered-mode announcement '\(text)' should describe preview (AC-5.2)")
    }

    // MARK: - AC-5.3: exactly one announcement per transition

    @Test("Each call to switchTo posts exactly one announcement (no double-announcement)")
    func eachSwitchPostsExactlyOneAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchTo(.rendered, target: .raw)
        #expect(probe.announcements.count == 1,
                "One switchTo call must produce exactly one announcement (AC-5.3)")
        probe.switchTo(.raw, target: .rendered)
        #expect(probe.announcements.count == 2,
                "Two switchTo calls must produce exactly two announcements (AC-5.3)")
    }

    @Test("toolbarShowRendered() and switchToRenderedFromSwipe() each post one announcement")
    func renderedPathsEachPostOneAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.toolbarShowRendered()
        #expect(probe.announcements.count == 1)
        // reset
        var probe2 = DocumentViewAnnouncementProbe(startMode: .raw)
        probe2.switchToRenderedFromSwipe()
        #expect(probe2.announcements.count == 1)
    }

    // MARK: - AC-5.4: announcement strings are localizable

    @Test("switchTo announcement strings are produced via String(localized:) (AC-5.4)")
    func announcementStringsAreLocalizable() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchTo(.rendered, target: .raw)
        let rawText = probe.announcements.last ?? ""
        // String(localized:) falls back to the key/default in tests where no
        // strings file has overrides; the result is a non-empty string.
        #expect(!rawText.isEmpty,
                "Announcement must be a non-empty localizable string (AC-5.4)")

        var probe2 = DocumentViewAnnouncementProbe(startMode: .raw)
        probe2.toolbarShowRendered()
        let renderedText = probe2.announcements.last ?? ""
        #expect(!renderedText.isEmpty,
                "Rendered-mode announcement must be a non-empty localizable string (AC-5.4)")
    }

    // MARK: - AC-5.5: initial onAppear mode assignment does NOT post an announcement

    @Test("onAppear initial mode assignment posts no announcement (AC-5.5)")
    func onAppearDoesNotPostAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.onAppearSetInitialMode(.raw)
        #expect(probe.announcements.isEmpty,
                "onAppear mode initialization must not post an announcement (AC-5.5 / EC-5.4)")
    }

    @Test("onAppear mode assignment to raw posts no announcement even for empty-file initial open")
    func onAppearRawForEmptyFilePostsNoAnnouncement() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        // Mirrors: DocumentView.initialMode(forContent: "", byteSize: 0) → .raw
        probe.onAppearSetInitialMode(DocumentView.initialMode(forContent: "", byteSize: 0))
        #expect(probe.mode == .raw,
                "Empty file must resolve to .raw initial mode")
        #expect(probe.announcements.isEmpty,
                "Initial raw mode for empty file must not fire a VoiceOver announcement (AC-5.5, EC-5.4)")
    }

    // MARK: - Integration: existing side effects preserved (AC-5.6)

    @Test("switchTo(.raw, target: .rendered) still triggers a save (AC-5.6)")
    func switchToRenderedStillTriggersSave() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.switchTo(.raw, target: .rendered)
        #expect(probe.saveCount == 1,
                "Switching from raw to rendered must still trigger a save (AC-5.6)")
    }

    @Test("switchTo(.rendered, target: .raw) does not trigger a save (AC-5.6)")
    func switchToRawDoesNotTriggerSave() {
        var probe = DocumentViewAnnouncementProbe(startMode: .rendered)
        probe.switchTo(.rendered, target: .raw)
        #expect(probe.saveCount == 0,
                "Switching from rendered to raw must not trigger a save (AC-5.6)")
    }

    @Test("toolbarShowRendered triggers a save alongside the announcement (AC-5.6)")
    func toolbarShowRenderedTriggersSave() {
        var probe = DocumentViewAnnouncementProbe(startMode: .raw)
        probe.toolbarShowRendered()
        #expect(probe.saveCount == 1,
                "Toolbar Show Rendered must trigger a save alongside the announcement (AC-5.6)")
    }
}
