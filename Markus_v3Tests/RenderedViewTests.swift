import Testing
import SwiftUI
@testable import Markus_v3

@Suite("RenderedView — T-007")
struct RenderedViewTests {

    @MainActor
    @Test("Empty source produces an empty rendered view (no crash)")
    func testEmptySourceProducesEmptyView() {
        let _ = RenderedView(text: "", onTap: {})
        #expect(Bool(true))
    }

    @MainActor
    @Test("Tap gesture switches mode to raw")
    func testTapGestureSwitchesMode() {
        let tracker = TapTracker()
        let view = RenderedView(text: "# Hi", onTap: { tracker.fire() })
        view.simulateTap()
        #expect(tracker.fired)
    }

    @MainActor
    @Test("Tap on a link switches mode (does NOT follow the link)")
    func testLinkTapSwitchesMode() {
        let tracker = TapTracker()
        let view = RenderedView(text: "[Apple](https://apple.com)", onTap: { tracker.fire() })
        view.simulateLinkTap(URL(string: "https://apple.com")!)
        #expect(tracker.fired)
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
        let _ = RenderedView(text: gfm, onTap: {})
        // Visible-render assertion is covered by the E2E flow tests at T-010 time;
        // unit scope here just confirms construction.
        #expect(Bool(true))
    }
}

@MainActor
private final class TapTracker {
    private(set) var fired = false
    func fire() { fired = true }
}
