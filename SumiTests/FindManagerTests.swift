import XCTest
@testable import Sumi

@MainActor
final class FindManagerTests: XCTestCase {
    func testShowFindBarWithoutTabKeepsManagerHidden() {
        let manager = FindManager()

        manager.showFindBar()

        XCTAssertFalse(manager.isFindBarVisible)
    }

    func testUpdateCurrentTabWithoutSessionResetsVisibleState() {
        let manager = FindManager()

        manager.updateCurrentTab(nil)

        XCTAssertFalse(manager.isFindBarVisible)
        XCTAssertNil(manager.currentModel)
    }

}
