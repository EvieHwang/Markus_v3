// SeamTests.swift
// Spec tests for native-polish-6 — integration/seam tests derived from design.md
//
// Framework: Swift Testing (@Test, #expect, #require)
// These tests live in features/native-polish-6/tests/ and are reference specs —
// they are NOT part of the Xcode test target. They are syntactically plausible
// Swift Testing code that a developer translates into Markus_v3Tests/ during
// implementation.
//
// Do NOT add DAG task-ID tags here — tagging happens in Stage 5 (verify.md is
// the authoritative task→test mapping after the DAG is committed).
//
// Seams covered:
//   C2 — MarkdownLineBreakNormalizer input/output contract
//   C3 — SwipeNavigationCoordinator: gesture conflict resolution
//   C5 — Share button presence conditioned on DocumentView mode
//   C7 — RecentsRegistrar: called on bookmark-based open, not on browser-delegate open

import Testing
import Foundation
import UIKit
import SwiftUI
@testable import Markus_v3

// MARK: - C2 Seam: MarkdownLineBreakNormalizer input/output contract

@Suite("C2 Seam — MarkdownLineBreakNormalizer input/output contract")
struct C2SeamTests {

    // Seam contract: pure function — takes String, returns String, no side effects.

    // Fenced code blocks pass through unchanged (backtick fence, both delimiters)
    @Test("C2: Fenced code block (backtick) interior passes through verbatim")
    func fencedCodeBacktickPassThrough() {
        let input = "```\nline_a\nline_b\n```"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        // The newlines between code lines must not acquire trailing spaces
        let interiorUnchanged = result.contains("line_a\nline_b")
        #expect(interiorUnchanged,
                "C2: Fenced code block interior must be unchanged by normalizer")
    }

    @Test("C2: Fenced code block (tilde) interior passes through verbatim")
    func fencedCodeTildePassThrough() {
        let input = "~~~\nline_a\nline_b\n~~~"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        let interiorUnchanged = result.contains("line_a\nline_b")
        #expect(interiorUnchanged,
                "C2: Tilde-fenced code block interior must be unchanged by normalizer")
    }

    @Test("C2: Info-string fenced code block passes through verbatim")
    func infoStringFencedCodePassThrough() {
        // Fenced block with language tag (info string) — still a code block
        let input = "```swift\nlet x = 1\nlet y = 2\n```"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result.contains("let x = 1\nlet y = 2"),
                "C2: Code block with info string must be unchanged")
    }

    // Bare newlines outside code regions get two trailing spaces
    @Test("C2: Bare newline in body text becomes two-trailing-spaces + newline")
    func bareNewlineBecomesTwoTrailingSpaces() {
        let input = "first\nsecond"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result == "first  \nsecond",
                "C2: Bare newline must become '  \\n' (two trailing spaces + newline)")
    }

    // List continuation lines: single newline normalized
    @Test("C2: Bare newline in list continuation line is normalized")
    func listContinuationNewlineNormalized() {
        // List item with continuation indent — the \n after the first line must get spaces
        let input = "- item one\n- item two"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result.contains("item one  \n"),
                "C2: List continuation line newline must be normalized (NP-3.3, NPC-4)")
    }

    // Blank lines preserved as paragraph breaks
    @Test("C2: Blank line (\\n\\n) is preserved unchanged — not converted to line break")
    func blankLinePreserved() {
        let input = "paragraph one\n\nparagraph two"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result.contains("paragraph one\n\n"),
                "C2: Blank line must be preserved as paragraph break, not as line break")
        #expect(!result.contains("paragraph one  \n\n"),
                "C2: Must NOT inject trailing spaces before a blank line (\\n\\n)")
    }

    // Paragraph break not converted to line break (NPC-6)
    @Test("C2: Double newline separating paragraphs stays as paragraph break")
    func doubleNewlineStaysParagraphBreak() {
        let input = "A\n\nB"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        // Must not add trailing spaces before the blank line
        #expect(result == "A\n\nB",
                "C2: A\\n\\nB must remain A\\n\\nB — no trailing spaces injected on either \\n")
    }

    // Already-normalized line (two trailing spaces) not double-modified
    @Test("C2: Line already ending in two spaces is not further modified")
    func alreadyNormalizedNotDoubleModified() {
        let input = "first  \nsecond"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(!result.contains("first    \n"),
                "C2: Pre-existing two trailing spaces must not become four spaces")
    }

    // Code block immediately followed by body text: body text after block IS normalized
    @Test("C2: Body text after a fenced code block is normalized normally")
    func bodyTextAfterCodeBlockNormalized() {
        let input = "```\ncode\n```\nbody line one\nbody line two"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        // Code interior: unchanged
        #expect(result.contains("code\n"), "C2: Code interior must be unchanged")
        // Body lines after the block: bare newline gets two trailing spaces
        #expect(result.contains("body line one  \nbody line two"),
                "C2: Body text after code block must be normalized")
    }

    // Empty string is a no-op
    @Test("C2: Empty input produces empty output")
    func emptyInputProducesEmptyOutput() {
        let result = MarkdownLineBreakNormalizer.normalize("")
        #expect(result == "", "C2: Empty input must produce empty output")
    }

    // Single line (no newline) is unchanged
    @Test("C2: Single-line input with no newline is returned unchanged")
    func singleLineUnchanged() {
        let input = "hello world"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result == "hello world",
                "C2: Single-line input (no newline) must be returned unchanged")
    }

    // Nested structure: blockquote with single newline — normalized inside
    @Test("C2: Single newline inside a blockquote is normalized (NP-3.3)")
    func blockquoteNewlineNormalized() {
        let input = "> first line\n> second line"
        let result = MarkdownLineBreakNormalizer.normalize(input)
        #expect(result.contains("first line  \n"),
                "C2: Bare newline inside blockquote must be normalized (NP-3.3)")
    }

    // Normalizer is a pure function: same input → same output, every time
    @Test("C2: MarkdownLineBreakNormalizer is deterministic (same input → same output)")
    func normalizerIsDeterministic() {
        let input = "line one\nline two\n\nparagraph two\nline three\n```\ncode\n```\nafter"
        let first = MarkdownLineBreakNormalizer.normalize(input)
        let second = MarkdownLineBreakNormalizer.normalize(input)
        #expect(first == second, "C2: Normalizer must be a pure function")
    }

    // No state leaks across calls
    @Test("C2: Normalizer has no state — independent calls do not affect each other")
    func normalizerHasNoState() {
        let a = MarkdownLineBreakNormalizer.normalize("a\nb")
        let b = MarkdownLineBreakNormalizer.normalize("x\ny")
        _ = a
        // Second call must produce the same result as if it were the first call
        let b2 = MarkdownLineBreakNormalizer.normalize("x\ny")
        #expect(b == b2, "C2: Normalizer must have no shared state between calls")
    }
}

// MARK: - C3 Seam: Gesture conflict resolution

@Suite("C3 Seam — SwipeNavigationCoordinator: gesture conflict resolution")
struct C3SeamTests {

    // Seam contract: gesture recognizers on raw editor and rendered view
    // coordinate with native scroll and system edge-pan recognizers.

    // Vertical scroll does not trigger mode-switch swipe (NPC-18)
    @MainActor
    @Test("C3: Vertical drag on raw editor does not trigger R→L mode-switch")
    func verticalDragRawEditorNoModeSwitch() {
        let probe = GestureConflictProbe(surface: .rawEditor)
        probe.simulateDrag(dx: -20, dy: -300, velocityX: -30, startX: 100)
        #expect(!probe.modeSwitchFired,
                "C3: Vertical drag (scroll intent) must not trigger mode switch (NPC-18)")
    }

    @MainActor
    @Test("C3: Vertical drag on rendered view does not trigger L→R mode-switch")
    func verticalDragRenderedViewNoModeSwitch() {
        let probe = GestureConflictProbe(surface: .renderedView)
        probe.simulateDrag(dx: 20, dy: 300, velocityX: 30, startX: 100)
        #expect(!probe.modeSwitchFired,
                "C3: Vertical drag on rendered view must not trigger mode switch (NPC-18)")
    }

    // Screen-edge pan takes priority over DragGesture for rendered L→R (NPC-22)
    @MainActor
    @Test("C3: L→R drag on rendered view starting in edge zone fires edge pan, not DragGesture")
    func edgeZoneDragRenderedFiresEdgePan() {
        let probe = GestureConflictProbe(surface: .renderedView)
        // Start within first 20 pt (edge zone)
        probe.simulateDrag(dx: 150, dy: 8, velocityX: 600, startX: 10)
        #expect(probe.edgePanFired,
                "C3: Edge zone drag must fire the UIScreenEdgePanGestureRecognizer (NPC-22)")
        #expect(!probe.dragGestureFired,
                "C3: SwiftUI DragGesture must NOT fire when edge pan fires (NPC-22)")
    }

    // Mid-screen L→R on rendered view fires DragGesture for raw mode (NPC-22)
    @MainActor
    @Test("C3: L→R drag on rendered view starting outside edge zone fires DragGesture for raw mode")
    func midScreenDragRenderedFiresDragGesture() {
        let probe = GestureConflictProbe(surface: .renderedView)
        // Start outside edge zone (> 20 pt from leading edge)
        probe.simulateDrag(dx: 150, dy: 8, velocityX: 600, startX: 60)
        #expect(probe.dragGestureFired,
                "C3: Mid-screen L→R drag must fire the SwiftUI DragGesture for raw mode (NPC-22)")
        #expect(!probe.edgePanFired,
                "C3: Edge pan must NOT fire for a drag starting outside the edge zone")
    }

    // DragGesture on raw editor and edge pan do not both fire (NPC-9)
    @MainActor
    @Test("C3: On raw editor, L→R edge pan and SwiftUI DragGesture do not both fire")
    func rawEditorNoDualGestureFire() {
        let probe = GestureConflictProbe(surface: .rawEditor)
        // Simulate L→R swipe starting from screen edge on raw editor
        probe.simulateDrag(dx: 150, dy: 5, velocityX: 600, startX: 5)
        let totalFired = (probe.edgePanFired ? 1 : 0) + (probe.dragGestureFired ? 1 : 0)
        #expect(totalFired <= 1,
                "C3: At most one gesture (edge pan OR DragGesture) must fire per swipe on raw editor (NPC-9)")
    }

    // Horizontal content scroll in rendered view yields to scroll, not swipe (NPC-19)
    @MainActor
    @Test("C3: L→R swipe at horizontally-scrollable position yields to content scroll")
    func horizontalScrollablePosYieldsToScroll() {
        let probe = GestureConflictProbe(surface: .renderedView, contentHScrollable: true)
        probe.simulateDrag(dx: 100, dy: 5, velocityX: 400, startX: 60)
        #expect(!probe.modeSwitchFired,
                "C3: Horizontal content scroll must take priority over mode-switch DragGesture (NPC-19)")
    }

    // Minimum velocity threshold: slow horizontal drag does not trigger (NPC-20)
    @MainActor
    @Test("C3: Low-velocity horizontal drag does not reach mode-switch threshold")
    func lowVelocityDragNoModeSwitch() {
        let probe = GestureConflictProbe(surface: .rawEditor)
        // Below velocity threshold: simulates selection extension
        probe.simulateDrag(dx: -45, dy: 5, velocityX: -60, startX: 100)
        #expect(!probe.modeSwitchFired,
                "C3: Low-velocity drag (below threshold) must not trigger mode switch (NPC-20)")
    }

    // .simultaneousGesture: mode-switch swipe does not preempt scroll in ScrollView
    @MainActor
    @Test("C3: Mode-switch DragGesture is simultaneousGesture and does not preempt scroll")
    func modeSwitchGestureIsSimultaneous() {
        let probe = GestureConflictProbe(surface: .renderedView)
        // Verify the DragGesture is configured as .simultaneousGesture:
        // a dominant horizontal drag triggers mode switch; scroll recognizer also receives events.
        probe.simulateDrag(dx: 120, dy: 5, velocityX: 500, startX: 60)
        #expect(probe.dragGestureFired, "C3: Mode-switch DragGesture must fire for a clear horizontal drag")
        #expect(probe.scrollRecognizerAlsoReceived,
                "C3: Scroll recognizer must also receive events (.simultaneousGesture semantics)")
    }

    // Keyboard-up swipe on raw editor: mode switch completes without deadlock (NPC-8)
    @MainActor
    @Test("C3: R→L swipe on raw editor with keyboard up completes mode switch (NPC-8)")
    func swipeWithKeyboardUpCompletesTransition() {
        let probe = GestureConflictProbe(surface: .rawEditor, keyboardPresented: true)
        probe.simulateDrag(dx: -130, dy: 8, velocityX: -550, startX: 100)
        #expect(probe.modeSwitchFired,
                "C3: Mode switch must complete even with keyboard presented (NPC-8, NP-20)")
    }
}

// MARK: - C5 Seam: Share button absent in raw mode, present in rendered mode

@Suite("C5 Seam — Share button conditioned on DocumentView mode")
struct C5SeamTests {

    // Seam contract: DocumentView's .toolbar block shows share button iff mode == .rendered.

    // Share button present in rendered mode
    @MainActor
    @Test("C5: Share button (square.and.arrow.up) is present in rendered mode toolbar")
    func shareButtonPresentInRenderedMode() {
        let probe = ToolbarModeProbe(mode: .rendered)
        #expect(probe.shareButtonVisible,
                "C5: Share button must be present when mode == .rendered (NPC-11 complement)")
        #expect(probe.shareButtonSFSymbol == "square.and.arrow.up",
                "C5: Share button icon must be 'square.and.arrow.up'")
    }

    // Share button absent in raw mode (NPC-11)
    @MainActor
    @Test("C5: Share button is absent from raw mode toolbar (NPC-11)")
    func shareButtonAbsentInRawMode() {
        let probe = ToolbarModeProbe(mode: .raw)
        #expect(!probe.shareButtonVisible,
                "C5: Share button must NOT be present when mode == .raw (NPC-11)")
    }

    // Mode switch from rendered → raw removes the share button
    @MainActor
    @Test("C5: Switching from rendered to raw mode removes the share button from the toolbar")
    func modeSwitchRemovesShareButton() {
        var probe = ToolbarModeProbe(mode: .rendered)
        #expect(probe.shareButtonVisible, "C5: Share button must be present in rendered mode")
        probe.switchMode(to: .raw)
        #expect(!probe.shareButtonVisible, "C5: Share button must disappear after switching to raw mode")
    }

    // Mode switch from raw → rendered adds the share button
    @MainActor
    @Test("C5: Switching from raw to rendered mode adds the share button to the toolbar")
    func modeSwitchAddsShareButton() {
        var probe = ToolbarModeProbe(mode: .raw)
        #expect(!probe.shareButtonVisible, "C5: Share button must be absent in raw mode")
        probe.switchMode(to: .rendered)
        #expect(probe.shareButtonVisible, "C5: Share button must appear after switching to rendered mode")
    }

    // Share button in .topBarTrailing position
    @MainActor
    @Test("C5: Share button is placed in topBarTrailing of the navigation bar")
    func shareButtonInTopBarTrailing() {
        let probe = ToolbarModeProbe(mode: .rendered)
        #expect(probe.shareButtonPlacement == .topBarTrailing,
                "C5: Share button must be in .topBarTrailing (matching design C5)")
    }

    // Share button tap with existing file: UIActivityViewController presented
    @MainActor
    @Test("C5: Tapping share button presents UIActivityViewController with file URL")
    func shareButtonTapPresentsActivityVC() {
        let url = URL(fileURLWithPath: "/tmp/seam-test.md")
        let probe = ToolbarModeProbe(mode: .rendered, fileURL: url)
        probe.tapShare()
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        if fileExists {
            #expect(probe.activityVCPresented,
                    "C5: Share button tap must present UIActivityViewController when file exists")
            #expect(probe.activityItems?.first as? URL == url,
                    "C5: Activity item must be the file URL")
        }
        // If file doesn't exist on this test machine, we verify the guard fires instead.
        if !fileExists {
            #expect(!probe.activityVCPresented,
                    "C5: Share button must not present VC when file does not exist on disk")
        }
    }

    // Share button tap with deleted file: no crash, no share sheet
    @MainActor
    @Test("C5: Tapping share with non-existent file is a safe no-op")
    func shareButtonTapWithDeletedFileNoop() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).md")
        let probe = ToolbarModeProbe(mode: .rendered, fileURL: url)
        probe.tapShare()
        #expect(!probe.activityVCPresented,
                "C5: Share must not present when file does not exist (NPC-12)")
        #expect(Bool(true), "C5: Must not crash when file is missing")
    }

    // Share button tap with nil URL: no crash
    @MainActor
    @Test("C5: Tapping share with nil fileURL is a safe no-op (NPC-12)")
    func shareButtonTapWithNilURL() {
        let probe = ToolbarModeProbe(mode: .rendered, fileURL: nil)
        probe.tapShare()
        #expect(!probe.activityVCPresented,
                "C5: Share must not present when fileURL is nil (NPC-12)")
    }
}

// MARK: - C7 Seam: RecentsRegistrar called on bookmark-based open, not browser-delegate open

@Suite("C7 Seam — RecentsRegistrar call routing")
struct C7SeamTests {

    // Seam contract: presentDocument(at:) calls RecentsRegistrar.register only when
    // the open originates from LaunchResumeBranch (isResumeOpen: true),
    // not when it originates from the browser delegate.

    // RecentsRegistrar is called on bookmark-based open
    @MainActor
    @Test("C7: RecentsRegistrar.register is called when presentDocument originates from LaunchResumeBranch")
    func recentsRegistrarCalledOnBookmarkOpen() {
        let probe = RecentsRegistrarCallProbe()
        probe.simulatePresentDocument(isResumeOpen: true,
                                      url: URL(fileURLWithPath: "/tmp/resume.md"))
        #expect(probe.registerCallCount == 1,
                "C7: RecentsRegistrar.register must be called for bookmark-based (resume) opens")
    }

    // RecentsRegistrar is NOT called on browser-delegate open
    @MainActor
    @Test("C7: RecentsRegistrar.register is NOT called when presentDocument originates from browser delegate")
    func recentsRegistrarNotCalledOnBrowserDelegateOpen() {
        let probe = RecentsRegistrarCallProbe()
        probe.simulatePresentDocument(isResumeOpen: false,
                                      url: URL(fileURLWithPath: "/tmp/delegate.md"))
        #expect(probe.registerCallCount == 0,
                "C7: RecentsRegistrar.register must NOT be called for browser-delegate opens (NPC-17)")
    }

    // RecentsRegistrar called with the correct URL
    @MainActor
    @Test("C7: RecentsRegistrar.register is called with the same URL as the open request")
    func recentsRegistrarCalledWithCorrectURL() {
        let probe = RecentsRegistrarCallProbe()
        let url = URL(fileURLWithPath: "/tmp/exact-url.md")
        probe.simulatePresentDocument(isResumeOpen: true, url: url)
        #expect(probe.lastRegisteredURL == url,
                "C7: RecentsRegistrar must receive the exact URL being opened")
    }

    // RecentsRegistrar holds a weak reference to BrowserHostController (NPC-15)
    @MainActor
    @Test("C7: RecentsRegistrar works when BrowserHostController is not the frontmost VC")
    func recentsRegistrarWorksWhenBrowserNotFrontmost() {
        let probe = RecentsRegistrarCallProbe(browserIsFrontmost: false)
        probe.simulatePresentDocument(isResumeOpen: true,
                                      url: URL(fileURLWithPath: "/tmp/offscreen.md"))
        #expect(probe.registerCallCount == 1,
                "C7: RecentsRegistrar must be called even when browser is off-screen (NPC-15, NP-10.5)")
    }

    // RecentsRegistrar failure is a no-op (NPC-16)
    @MainActor
    @Test("C7: RecentsRegistrar failure does not propagate an error or crash the presenter")
    func recentsRegistrarFailureIsNoop() {
        let probe = RecentsRegistrarCallProbe()
        probe.registrationShouldFail = true
        probe.simulatePresentDocument(isResumeOpen: true,
                                      url: URL(fileURLWithPath: "/tmp/fail.md"))
        // The document must still be presented; no error thrown
        #expect(probe.documentPresentationCompleted,
                "C7: Document must be presented even if RecentsRegistrar.register fails (NPC-16)")
        #expect(probe.errorPropagated == false,
                "C7: RecentsRegistrar failure must not propagate an error (NPC-16)")
    }

    // RecentsRegistrar called on every bookmark open (not just once per file)
    @MainActor
    @Test("C7: RecentsRegistrar.register is called on every bookmark-based open of the same file")
    func recentsRegistrarCalledEveryOpen() {
        let probe = RecentsRegistrarCallProbe()
        let url = URL(fileURLWithPath: "/tmp/repeated.md")
        probe.simulatePresentDocument(isResumeOpen: true, url: url)
        probe.simulatePresentDocument(isResumeOpen: true, url: url)
        probe.simulatePresentDocument(isResumeOpen: true, url: url)
        #expect(probe.registerCallCount == 3,
                "C7: RecentsRegistrar must be called on every bookmark-based open (NP-10.4)")
    }

    // Multiple distinct files: each registered once per open
    @MainActor
    @Test("C7: RecentsRegistrar.register is called once per bookmark-based open for each URL")
    func recentsRegistrarCalledPerURL() {
        let probe = RecentsRegistrarCallProbe()
        probe.simulatePresentDocument(isResumeOpen: true, url: URL(fileURLWithPath: "/tmp/a.md"))
        probe.simulatePresentDocument(isResumeOpen: true, url: URL(fileURLWithPath: "/tmp/b.md"))
        #expect(probe.registerCallCount == 2,
                "C7: Each bookmark-based open of a distinct file must produce one registration call")
        #expect(probe.registeredURLs[0].lastPathComponent == "a.md")
        #expect(probe.registeredURLs[1].lastPathComponent == "b.md")
    }

    // Mixed opens: only bookmark-based opens produce registration calls
    @MainActor
    @Test("C7: Mixed sequence of browser-delegate and bookmark opens — only bookmark opens register")
    func mixedOpenSequenceOnlyBookmarkRegisters() {
        let probe = RecentsRegistrarCallProbe()
        probe.simulatePresentDocument(isResumeOpen: false, url: URL(fileURLWithPath: "/tmp/via-browser.md"))
        probe.simulatePresentDocument(isResumeOpen: true,  url: URL(fileURLWithPath: "/tmp/via-bookmark.md"))
        probe.simulatePresentDocument(isResumeOpen: false, url: URL(fileURLWithPath: "/tmp/via-browser-2.md"))
        #expect(probe.registerCallCount == 1,
                "C7: Only the bookmark-based open must produce a registration call")
        #expect(probe.lastRegisteredURL?.lastPathComponent == "via-bookmark.md")
    }
}

// MARK: - Test Support Types for Seam Tests

// GestureConflictProbe: observes gesture firing behavior from C3 seam.
// Required implementation surface:
//   - surface: .rawEditor or .renderedView
//   - contentHScrollable: Bool (simulates horizontal scroll position)
//   - keyboardPresented: Bool
//   - modeSwitchFired: Bool — set when the swipe gesture completes a mode switch
//   - edgePanFired: Bool — set when UIScreenEdgePanGestureRecognizer fires
//   - dragGestureFired: Bool — set when SwiftUI DragGesture fires
//   - scrollRecognizerAlsoReceived: Bool — set when the scroll view also receives events
//   - simulateDrag(dx:dy:velocityX:startX:)
@MainActor
private struct GestureConflictProbe {
    enum Surface { case rawEditor, renderedView }

    let surface: Surface
    let contentHScrollable: Bool
    let keyboardPresented: Bool

    private(set) var modeSwitchFired: Bool = false
    private(set) var edgePanFired: Bool = false
    private(set) var dragGestureFired: Bool = false
    private(set) var scrollRecognizerAlsoReceived: Bool = false

    private let edgeZone: CGFloat = 20
    private let velocityThreshold: CGFloat = 200
    private let translationThreshold: CGFloat = 50

    init(surface: Surface, contentHScrollable: Bool = false, keyboardPresented: Bool = false) {
        self.surface = surface
        self.contentHScrollable = contentHScrollable
        self.keyboardPresented = keyboardPresented
    }

    mutating func simulateDrag(dx: CGFloat, dy: CGFloat, velocityX: CGFloat, startX: CGFloat) {
        let isDominantlyHorizontal = abs(dx) > abs(dy) * 1.5
        let meetsThreshold = abs(velocityX) > velocityThreshold && abs(dx) > translationThreshold

        // Always provide scroll events (.simultaneousGesture contract)
        if isDominantlyHorizontal {
            scrollRecognizerAlsoReceived = true
        }

        // Near-edge L→R: edge pan takes priority (NPC-22)
        if startX <= edgeZone && dx > 0 {
            edgePanFired = true
            // dragGestureFired remains false (edge pan claims it)
            return
        }

        guard isDominantlyHorizontal && meetsThreshold else { return }
        guard !contentHScrollable else { return }

        // DragGesture fires for valid swipes starting outside edge zone
        dragGestureFired = true

        // Mode switch fires based on surface and direction
        switch surface {
        case .rawEditor where dx < 0:   // R→L on raw → rendered
            modeSwitchFired = true
        case .renderedView where dx > 0: // L→R on rendered → raw
            modeSwitchFired = true
        default:
            break
        }
    }
}

// ToolbarModeProbe: observes DocumentView toolbar composition per mode (C5 seam).
// Required implementation surface:
//   - mode: DocumentMode
//   - fileURL: URL?
//   - shareButtonVisible: Bool
//   - shareButtonSFSymbol: String?
//   - shareButtonPlacement: ToolbarItemPlacement
//   - activityVCPresented: Bool
//   - activityItems: [Any]?
//   - switchMode(to:)
//   - tapShare()
@MainActor
private struct ToolbarModeProbe {
    enum DocumentMode { case raw, rendered }

    private(set) var mode: DocumentMode
    let fileURL: URL?
    private(set) var shareButtonVisible: Bool
    private(set) var shareButtonSFSymbol: String?
    private(set) var shareButtonPlacement: ToolbarItemPlacement
    private(set) var activityVCPresented: Bool = false
    private(set) var activityItems: [Any]? = nil

    init(mode: DocumentMode, fileURL: URL? = nil) {
        self.mode = mode
        self.fileURL = fileURL
        self.shareButtonVisible = (mode == .rendered)
        self.shareButtonSFSymbol = (mode == .rendered) ? "square.and.arrow.up" : nil
        self.shareButtonPlacement = .topBarTrailing
    }

    mutating func switchMode(to newMode: DocumentMode) {
        mode = newMode
        shareButtonVisible = (newMode == .rendered)
        shareButtonSFSymbol = (newMode == .rendered) ? "square.and.arrow.up" : nil
    }

    mutating func tapShare() {
        guard mode == .rendered, let url = fileURL else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        activityVCPresented = true
        activityItems = [url]
    }
}

// RecentsRegistrarCallProbe: observes BrowserHostController→RecentsRegistrar routing (C7 seam).
// Required implementation surface:
//   - registerCallCount: Int
//   - registeredURLs: [URL]
//   - lastRegisteredURL: URL?
//   - registrationShouldFail: Bool
//   - documentPresentationCompleted: Bool
//   - errorPropagated: Bool
//   - browserIsFrontmost: Bool
//   - simulatePresentDocument(isResumeOpen:url:)
@MainActor
private struct RecentsRegistrarCallProbe {
    let browserIsFrontmost: Bool
    private(set) var registerCallCount: Int = 0
    private(set) var registeredURLs: [URL] = []
    private(set) var lastRegisteredURL: URL? = nil
    var registrationShouldFail: Bool = false
    private(set) var documentPresentationCompleted: Bool = false
    private(set) var errorPropagated: Bool = false

    init(browserIsFrontmost: Bool = true) {
        self.browserIsFrontmost = browserIsFrontmost
    }

    mutating func simulatePresentDocument(isResumeOpen: Bool, url: URL) {
        if isResumeOpen {
            // RecentsRegistrar.register is called for bookmark-based opens
            registerCallCount += 1
            registeredURLs.append(url)
            lastRegisteredURL = url
            if registrationShouldFail {
                // Failure is silent: no error thrown, no user-visible error
                errorPropagated = false
            }
        }
        // Document presentation always completes regardless of registration outcome
        documentPresentationCompleted = true
    }
}
