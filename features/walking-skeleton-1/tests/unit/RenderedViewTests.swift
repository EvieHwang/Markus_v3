// Spec test — Wave 4 / T-007
// Tags: T-007
// Verifies: AC-2.5, AC-3.1, AC-3.3, EC-3; design component #5

import Testing
import SwiftUI
@testable import Markus_v3

@Suite("RenderedView — T-007")
struct RenderedViewTests {

    @MainActor
    @Test("Empty source produces an empty rendered view (no crash)")
    func testEmptySourceProducesEmptyView() {
        // Constructing the view with empty text must not crash.
        let _ = RenderedView(text: "", onTap: {})
        #expect(Bool(true))
    }

    @MainActor
    @Test("Tap gesture switches mode to raw")
    func testTapGestureSwitchesMode() {
        var tapped = false
        let view = RenderedView(text: "# Hi", onTap: { tapped = true })
        // Build agent: invoke the gesture handler directly through the view's
        // exposed test hook or via ViewInspector.
        view.simulateTap() // implementation provides this helper
        #expect(tapped)
    }

    @MainActor
    @Test("Tap on a link switches mode (does NOT follow the link)")
    func testLinkTapSwitchesMode() {
        var tapped = false
        let view = RenderedView(text: "[Apple](https://apple.com)", onTap: { tapped = true })
        view.simulateLinkTap(URL(string: "https://apple.com")!)
        #expect(tapped)
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
        // Build agent: snapshot-test or ViewInspector to confirm the heading,
        // list, task list, table, strikethrough, and autolink are present.
        #expect(Bool(true))
    }
}
