import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class SpaceViewDecompositionTests: XCTestCase {
    func testInteractiveRenderModeFailsClosedWhenSidebarInteractiveWorkIsDisabled() {
        XCTAssertTrue(
            SpaceViewRenderMode.interactive.resolvesInteraction(allowsInteraction: true)
        )
        XCTAssertFalse(
            SpaceViewRenderMode.interactive.resolvesInteraction(allowsInteraction: false)
        )
        XCTAssertFalse(
            SpaceViewRenderMode.transitionSnapshot.resolvesInteraction(allowsInteraction: true)
        )
    }
}
