import AppKit
import XCTest

@testable import Sumi

@MainActor
final class GlanceOverlayResponderCommandTests: XCTestCase {
    func testRootResponderClosesGlanceAfterDescendantsDeclineEscape() {
        let rootView = GlanceOverlayRootView()
        var closeCount = 0
        rootView.onCancelOperation = {
            closeCount += 1
            return true
        }

        rootView.cancelOperation(nil)

        XCTAssertEqual(closeCount, 1)
    }
}
