@testable import Sumi
import XCTest

@MainActor
final class BrowserSidebarTabCommandOwnerTests: XCTestCase {
    func testTabCommandsRouteToDependenciesAndReturnOpenedTab() {
        let spy = Spy()
        let returnedTab = makeTab()
        let owner = makeOwner(spy: spy, returnedTab: returnedTab)
        let windowState = BrowserWindowState()
        let tab = makeTab()
        let preferredSpaceId = UUID()

        owner.requestUserTabActivation(tab, in: windowState)
        owner.closeTab(tab, in: windowState)
        owner.moveTabUp(tab.id)
        owner.moveTabDown(tab.id)
        let openedTab = owner.openForegroundTab(
            "https://example.com",
            in: windowState,
            preferredSpaceId: preferredSpaceId
        )
        owner.openNewTabOrFloatingBar(in: windowState)
        owner.duplicateTab(tab, in: windowState)

        XCTAssertIdentical(openedTab, returnedTab)
        XCTAssertEqual(
            spy.events,
            [
                .requestUserTabActivation(tab.id, windowState.id),
                .closeTab(tab.id, windowState.id),
                .moveTabUp(tab.id),
                .moveTabDown(tab.id),
                .openForegroundTab("https://example.com", windowState.id, preferredSpaceId),
                .openNewTabOrFloatingBar(windowState.id),
                .duplicateTab(tab.id, windowState.id),
            ]
        )
    }

    private func makeOwner(spy: Spy, returnedTab: Tab?) -> BrowserSidebarTabCommandOwner {
        BrowserSidebarTabCommandOwner(
            dependencies: BrowserSidebarTabCommandOwner.Dependencies(
                requestUserTabActivation: { tab, windowState in
                    spy.events.append(.requestUserTabActivation(tab.id, windowState.id))
                },
                closeTab: { tab, windowState in
                    spy.events.append(.closeTab(tab.id, windowState.id))
                },
                moveTabUp: { tabId in
                    spy.events.append(.moveTabUp(tabId))
                },
                moveTabDown: { tabId in
                    spy.events.append(.moveTabDown(tabId))
                },
                openForegroundTab: { url, windowState, preferredSpaceId in
                    spy.events.append(.openForegroundTab(url, windowState.id, preferredSpaceId))
                    return returnedTab
                },
                openNewTabOrFloatingBar: { windowState in
                    spy.events.append(.openNewTabOrFloatingBar(windowState.id))
                },
                duplicateTab: { tab, windowState in
                    spy.events.append(.duplicateTab(tab.id, windowState.id))
                }
            )
        )
    }

    private func makeTab() -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            name: "Example",
            favicon: "globe",
            index: 0
        )
    }
}

private final class Spy {
    var events: [BrowserSidebarTabCommandOwnerTests.Event] = []
}

extension BrowserSidebarTabCommandOwnerTests {
    enum Event: Equatable {
        case requestUserTabActivation(UUID, UUID)
        case closeTab(UUID, UUID)
        case moveTabUp(UUID)
        case moveTabDown(UUID)
        case openForegroundTab(String, UUID, UUID?)
        case openNewTabOrFloatingBar(UUID)
        case duplicateTab(UUID, UUID)
    }
}
