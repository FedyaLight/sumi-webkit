import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserFindBarRoutingOwnerTests: XCTestCase {
    func testShowFindBarFallsBackToNilSessionWhenThereIsNoActiveWindow() {
        let harness = Harness(activeWindow: nil)
        let owner = harness.makeOwner()

        owner.showFindBar()

        XCTAssertEqual(harness.showRequests.map(\.tabId), [nil])
        XCTAssertEqual(harness.showRequests.map(\.windowId), [nil])
        XCTAssertTrue(harness.updateRequests.isEmpty)
    }

    func testUpdateCurrentTabFallsBackToNilSessionWhenThereIsNoActiveWindow() {
        let harness = Harness(activeWindow: nil)
        let owner = harness.makeOwner()

        owner.updateCurrentTab()

        XCTAssertEqual(harness.updateRequests.map(\.tabId), [nil])
        XCTAssertEqual(harness.updateRequests.map(\.windowId), [nil])
        XCTAssertTrue(harness.showRequests.isEmpty)
    }

    func testShowFindBarRoutesActivePageTabInActiveWindow() {
        let windowState = BrowserWindowState()
        let tab = Self.makeTab()
        let harness = Harness(activeWindow: windowState, activePageTab: tab)
        let owner = harness.makeOwner()

        owner.showFindBar()

        XCTAssertEqual(harness.showRequests.map(\.tabId), [tab.id])
        XCTAssertEqual(harness.showRequests.map(\.windowId), [windowState.id])
    }

    func testUpdateCurrentTabRoutesActivePageTabInActiveWindow() {
        let windowState = BrowserWindowState()
        let tab = Self.makeTab()
        let harness = Harness(activeWindow: windowState, activePageTab: tab)
        let owner = harness.makeOwner()

        owner.updateCurrentTab()

        XCTAssertEqual(harness.updateRequests.map(\.tabId), [tab.id])
        XCTAssertEqual(harness.updateRequests.map(\.windowId), [windowState.id])
    }

    private static func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            name: "Example",
            loadsCachedFaviconOnInit: false
        )
    }

    @MainActor
    private final class Harness {
        var activeWindow: BrowserWindowState?
        var activePageTab: Tab?
        var showRequests: [(tabId: UUID?, windowId: UUID?)] = []
        var updateRequests: [(tabId: UUID?, windowId: UUID?)] = []

        init(activeWindow: BrowserWindowState?, activePageTab: Tab? = nil) {
            self.activeWindow = activeWindow
            self.activePageTab = activePageTab
        }

        func makeOwner() -> BrowserFindBarRoutingOwner {
            BrowserFindBarRoutingOwner(
                dependencies: BrowserFindBarRoutingOwner.Dependencies(
                    activeWindow: { self.activeWindow },
                    activePageTab: { _ in self.activePageTab },
                    showFindBar: { tab, windowId in
                        self.showRequests.append((tabId: tab?.id, windowId: windowId))
                    },
                    updateCurrentTab: { tab, windowId in
                        self.updateRequests.append((tabId: tab?.id, windowId: windowId))
                    }
                )
            )
        }
    }
}
