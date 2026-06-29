import XCTest
@testable import Sumi

@MainActor
final class BrowserSidebarCommandRoutingOwnerTests: XCTestCase {
    func testActionsRouteWindowAndTabCommands() throws {
        let spy = Spy()
        let returnedTab = makeTab()
        let owner = makeOwner(spy: spy, returnedTab: returnedTab)
        let actions = owner.makeActions()
        let windowState = BrowserWindowState()
        let tab = makeTab()
        let group = try XCTUnwrap(
            SplitGroup.make(tabIds: [tab.id, UUID()], layoutKind: .vertical)
        )
        let memberId = UUID()
        let preferredSpaceId = UUID()

        XCTAssertTrue(actions.canCreateFolderInCurrentSpace(windowState))
        actions.showGradientEditor(
            SidebarTransientPresentationSource(
                windowID: windowState.id,
                window: nil,
                originOwnerView: nil,
                previousFirstResponder: nil,
                wasKeyWindow: false,
                coordinator: nil
            )
        )
        actions.toggleSidebar(windowState)
        actions.openAppearanceSettings(windowState)
        actions.closeDownloadsPopover(windowState)
        actions.requestUserTabActivation(tab, windowState)
        actions.closeTab(tab, windowState)
        actions.moveTabUp(tab.id)
        actions.moveTabDown(tab.id)
        actions.focusSplitGroup(group, windowState)
        actions.restoreShortcutSplitMember(memberId, group, windowState)
        let openedTab = actions.openForegroundTab("https://example.com", windowState, preferredSpaceId)
        actions.openNewTabOrFloatingBar(windowState)
        actions.duplicateTab(tab, windowState)
        actions.toggleDownloadsPopover(windowState)

        XCTAssertTrue(openedTab === returnedTab)
        XCTAssertEqual(
            spy.events,
            [
                .canCreateFolder(windowState.id),
                .showGradientEditor,
                .toggleSidebar(windowState.id),
                .openAppearanceSettings(windowState.id),
                .closeDownloadsPopover(windowState.id),
                .requestUserTabActivation(tab.id, windowState.id),
                .closeTab(tab.id, windowState.id),
                .moveTabUp(tab.id),
                .moveTabDown(tab.id),
                .focusSplitGroup(group.id, windowState.id),
                .restoreShortcutSplitMember(memberId, group.id, windowState.id),
                .openForegroundTab("https://example.com", windowState.id, preferredSpaceId),
                .openNewTabOrFloatingBar(windowState.id),
                .duplicateTab(tab.id, windowState.id),
                .toggleDownloadsPopover(windowState.id),
            ]
        )
    }

    func testActionsRoutePinAndFolderCreationCommands() throws {
        let spy = Spy()
        let owner = makeOwner(spy: spy)
        let actions = owner.makeActions()
        let windowState = BrowserWindowState()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com")),
            title: "Example"
        )
        let liveTab = makeTab()
        let spaceId = UUID()

        actions.pinShortcutGlobally(pin, windowState, spaceId, liveTab)
        actions.createFolderInCurrentSpace(windowState)
        actions.createRSSLiveFolderInCurrentSpace(windowState)
        actions.createGitHubPullRequestsLiveFolderInCurrentSpace(windowState)
        actions.createGitHubIssuesLiveFolderInCurrentSpace(windowState)

        XCTAssertEqual(
            spy.events,
            [
                .pinShortcutGlobally(pin.id, windowState.id, spaceId, liveTab.id),
                .createFolder(windowState.id),
                .createRSSLiveFolder(windowState.id),
                .createGitHubPullRequestsLiveFolder(windowState.id),
                .createGitHubIssuesLiveFolder(windowState.id),
            ]
        )
    }

    private func makeOwner(spy: Spy, returnedTab: Tab? = nil) -> BrowserSidebarCommandRoutingOwner {
        BrowserSidebarCommandRoutingOwner(
            dependencies: BrowserSidebarCommandRoutingOwner.Dependencies(
                canCreateFolderInCurrentSpace: { windowState in
                    spy.events.append(.canCreateFolder(windowState.id))
                    return true
                },
                showGradientEditor: { _ in
                    spy.events.append(.showGradientEditor)
                },
                toggleSidebar: { windowState in
                    spy.events.append(.toggleSidebar(windowState.id))
                },
                openAppearanceSettings: { windowState in
                    spy.events.append(.openAppearanceSettings(windowState.id))
                },
                closeDownloadsPopover: { windowState in
                    spy.events.append(.closeDownloadsPopover(windowState.id))
                },
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
                focusSplitGroup: { group, windowState in
                    spy.events.append(.focusSplitGroup(group.id, windowState.id))
                },
                restoreShortcutSplitMember: { memberId, group, windowState in
                    spy.events.append(.restoreShortcutSplitMember(memberId, group.id, windowState.id))
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
                },
                pinShortcutGlobally: { pin, windowState, spaceId, liveTab in
                    spy.events.append(.pinShortcutGlobally(pin.id, windowState.id, spaceId, liveTab?.id))
                },
                toggleDownloadsPopover: { windowState in
                    spy.events.append(.toggleDownloadsPopover(windowState.id))
                },
                createFolderInCurrentSpace: { windowState in
                    spy.events.append(.createFolder(windowState.id))
                },
                createRSSLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createRSSLiveFolder(windowState.id))
                },
                createGitHubPullRequestsLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubPullRequestsLiveFolder(windowState.id))
                },
                createGitHubIssuesLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubIssuesLiveFolder(windowState.id))
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
    var events: [BrowserSidebarCommandRoutingOwnerTests.Event] = []
}

extension BrowserSidebarCommandRoutingOwnerTests {
    enum Event: Equatable {
        case canCreateFolder(UUID)
        case showGradientEditor
        case toggleSidebar(UUID)
        case openAppearanceSettings(UUID)
        case closeDownloadsPopover(UUID)
        case requestUserTabActivation(UUID, UUID)
        case closeTab(UUID, UUID)
        case moveTabUp(UUID)
        case moveTabDown(UUID)
        case focusSplitGroup(UUID, UUID)
        case restoreShortcutSplitMember(UUID, UUID, UUID)
        case openForegroundTab(String, UUID, UUID?)
        case openNewTabOrFloatingBar(UUID)
        case duplicateTab(UUID, UUID)
        case pinShortcutGlobally(UUID, UUID, UUID, UUID?)
        case toggleDownloadsPopover(UUID)
        case createFolder(UUID)
        case createRSSLiveFolder(UUID)
        case createGitHubPullRequestsLiveFolder(UUID)
        case createGitHubIssuesLiveFolder(UUID)
    }
}
