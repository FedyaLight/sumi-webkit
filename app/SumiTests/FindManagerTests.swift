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

    func testClearSearchWritesIntoCurrentTabSessionModel() {
        let browserManager = BrowserManager()
        let manager = FindManager()
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/find",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        manager.updateCurrentTab(tab)
        tab.findInPage.model.find("duck")
        manager.clearSearch()

        XCTAssertEqual(tab.findInPage.model.text, "")
    }
}
