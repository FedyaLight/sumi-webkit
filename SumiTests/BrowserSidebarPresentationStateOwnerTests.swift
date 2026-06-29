import XCTest

@testable import Sumi

@MainActor
final class BrowserSidebarPresentationStateOwnerTests: XCTestCase {
    func testUpdateSidebarWidthClampsWindowStateAndFallbackCache() {
        let owner = BrowserSidebarPresentationStateOwner()
        let windowState = BrowserWindowState()

        owner.updateSidebarWidth(10, for: windowState)

        XCTAssertEqual(windowState.sidebarWidth, BrowserWindowState.sidebarMinimumWidth)
        XCTAssertEqual(windowState.savedSidebarWidth, BrowserWindowState.sidebarMinimumWidth)
        XCTAssertEqual(
            windowState.sidebarContentWidth,
            BrowserWindowState.sidebarContentWidth(for: BrowserWindowState.sidebarMinimumWidth)
        )
        XCTAssertEqual(
            owner.savedSidebarWidth(for: nil, activeWindow: nil),
            BrowserWindowState.sidebarMinimumWidth
        )
    }

    func testSavedSidebarWidthPrefersExplicitWindowThenActiveWindowThenFallback() {
        let owner = BrowserSidebarPresentationStateOwner()
        let explicitWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()

        owner.updateSavedSidebarWidth(500)
        activeWindow.savedSidebarWidth = 420
        explicitWindow.savedSidebarWidth = 340

        XCTAssertEqual(owner.savedSidebarWidth(for: explicitWindow, activeWindow: activeWindow), 340)
        XCTAssertEqual(owner.savedSidebarWidth(for: nil, activeWindow: activeWindow), 420)
        XCTAssertEqual(owner.savedSidebarWidth(for: nil, activeWindow: nil), 500)
    }

    func testSavedSidebarWidthClampsTooSmallFallbackAndWindowValues() {
        let owner = BrowserSidebarPresentationStateOwner()
        let windowState = BrowserWindowState()

        owner.updateSavedSidebarWidth(10)
        windowState.savedSidebarWidth = 20

        XCTAssertEqual(
            owner.savedSidebarWidth(for: windowState, activeWindow: nil),
            BrowserWindowState.sidebarMinimumWidth
        )
        XCTAssertEqual(
            owner.savedSidebarWidth(for: nil, activeWindow: nil),
            BrowserWindowState.sidebarMinimumWidth
        )
    }

    func testSyncFromWindowUpdatesFallbackWidth() {
        let owner = BrowserSidebarPresentationStateOwner()
        let windowState = BrowserWindowState()
        windowState.savedSidebarWidth = 333
        windowState.isSidebarVisible = false

        owner.syncFromWindow(windowState)

        XCTAssertEqual(owner.savedSidebarWidth(for: nil, activeWindow: nil), 333)
    }
}
