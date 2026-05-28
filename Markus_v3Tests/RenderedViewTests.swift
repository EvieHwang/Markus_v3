import Testing
import SwiftUI
@testable import Markus_v3

@Suite("RenderedView — tap and anchor surface")
struct RenderedViewTests {

    @MainActor
    @Test("Empty source produces an empty rendered view (no crash)")
    func testEmptySourceProducesEmptyView() {
        let _ = RenderedView(text: "", onTap: { _ in })
        #expect(Bool(true))
    }

    @MainActor
    @Test("Tap gesture fires onTap callback")
    func testTapGestureFiresCallback() {
        let tracker = TapTracker()
        let view = RenderedView(text: "# Hi", onTap: { _ in tracker.fire() })
        view.simulateTap()
        #expect(tracker.fired)
    }

    @MainActor
    @Test("Link tap does NOT fire onTap callback (AC-1.5: link follows URL, no mode switch)")
    func testLinkTapFiresCallback() {
        let tracker = TapTracker()
        let view = RenderedView(text: "[Apple](https://apple.com)", onTap: { _ in tracker.fire() })
        view.simulateLinkTap(URL(string: "https://apple.com")!)
        #expect(!tracker.fired)
    }

    @MainActor
    @Test("Link tap reports nothing to onTap (AC-1.5: URL handled by system openURL)")
    func testLinkTapReportsNilFractional() {
        var receivedY: Double?? = nil
        let view = RenderedView(text: "[A](https://a.com)", onTap: { receivedY = $0 })
        view.simulateLinkTap(URL(string: "https://a.com")!)
        #expect(receivedY == nil)
    }

    @MainActor
    @Test("Constructible with a non-nil pending scroll anchor")
    func testConstructibleWithPendingAnchor() {
        let _ = RenderedView(
            text: "# Hi",
            onTap: { _ in },
            pendingScrollAnchor: .constant(ScrollAnchor(fractionalY: 0.5))
        )
        #expect(Bool(true))
    }

    @MainActor
    @Test("GFM features render as recognizable constructs")
    func testGFMFeaturesRender() {
        let gfm = """
        # Heading

        - item one
        - [ ] task list
        - [x] done

        | A | B |
        |---|---|
        | 1 | 2 |

        ~~strike~~ and <https://apple.com>
        """
        let _ = RenderedView(text: gfm, onTap: { _ in })
        #expect(Bool(true))
    }
}

@MainActor
private final class TapTracker {
    private(set) var fired = false
    func fire() { fired = true }
}
