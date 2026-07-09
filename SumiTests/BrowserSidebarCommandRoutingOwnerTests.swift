@testable import Sumi
import XCTest

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

        XCTAssertIdentical(openedTab, returnedTab)
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

        spy.lastPinnedLiveTabId = liveTab.id
        actions.pinShortcutGlobally(pin, windowState, spaceId, liveTab)
        actions.createFolderInCurrentSpace(windowState)
        actions.createRSSLiveFolderInCurrentSpace(windowState)
        actions.createGitHubPRFolderInCurrentSpace(windowState)
        actions.createGitHubIssuesFolderInCurrentSpace(windowState)
        actions.unloadShortcutPin(pin, windowState)
        actions.unloadShortcutPins([pin], windowState)

        XCTAssertEqual(
            spy.events,
            [
                .pinShortcutGlobally(pin.id, windowState.id, spaceId, liveTab.id),
                .createFolder(windowState.id),
                .createRSSLiveFolder(windowState.id),
                .createGitHubPullRequestsLiveFolder(windowState.id),
                .createGitHubIssuesLiveFolder(windowState.id),
                .unloadShortcutPin(pin.id, windowState.id),
                .unloadShortcutPins([pin.id], windowState.id),
            ]
        )
    }

    private func makeOwner(spy: Spy, returnedTab: Tab? = nil) -> BrowserSidebarCommandRoutingOwner {
        let pinPromotion = PinPromotionSpy(spy: spy)
        return BrowserSidebarCommandRoutingOwner(
            folderCommand: BrowserSidebarFolderCommandOwner(
                spaceForSidebarActions: { windowState in
                    spy.events.append(.canCreateFolder(windowState.id))
                    return Space(name: "Space")
                },
                createFolderInCurrentSpace: { windowState in
                    spy.events.append(.createFolder(windowState.id))
                },
                createRSSLiveFolderInCurrentSpace: { windowState in
                    spy.events.append(.createRSSLiveFolder(windowState.id))
                },
                createGitHubPRFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubPullRequestsLiveFolder(windowState.id))
                },
                createGitHubIssuesFolderInCurrentSpace: { windowState in
                    spy.events.append(.createGitHubIssuesLiveFolder(windowState.id))
                }
            ),
            chromeCommand: BrowserSidebarChromeCommandOwner(
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
                toggleDownloadsPopover: { windowState in
                    spy.events.append(.toggleDownloadsPopover(windowState.id))
                }
            ),
            tabCommand: BrowserSidebarTabCommandOwner(
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
            ),
            splitShortcutRouting: SplitRoutingSpy(spy: spy),
            shortcutPromotion: pinPromotion.owner,
            shortcutPinUnload: BrowserShortcutPinUnloadOwner(
                selectedShortcutLiveTab: { _, _ in nil },
                closeTab: { _, _ in },
                userInitiatedUnload: { pinId, windowState, presentNotification in
                    if presentNotification {
                        spy.events.append(.unloadShortcutPin(pinId, windowState.id))
                    } else {
                        spy.bulkUnloadPinIds.append(pinId)
                    }
                    return true
                },
                notifications: {
                    BulkUnloadNotificationSpy(spy: spy)
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

@MainActor
private final class PinPromotionSpy {
    let owner: BrowserSidebarShortcutPromotionOwner

    init(spy: Spy) {
        self.owner = BrowserSidebarShortcutPromotionOwner(
            copyShortcutPinToEssentials: { pin, _, context in
                spy.events.append(
                    .pinShortcutGlobally(
                        pin.id,
                        context.windowState?.id ?? UUID(),
                        context.spaceId ?? UUID(),
                        spy.lastPinnedLiveTabId
                    )
                )
                spy.lastPinnedLiveTabId = nil
            }
        )
    }
}

@MainActor
private final class SplitRoutingSpy: BrowserSidebarSplitShortcutRouting {
    private let spy: Spy

    init(spy: Spy) {
        self.spy = spy
    }

    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        spy.events.append(.focusSplitGroup(group.id, windowState.id))
    }

    func restoreShortcutSplitMember(
        _ itemId: UUID,
        from group: SplitGroup,
        in windowState: BrowserWindowState,
        preserveLiveInstance: Bool
    ) {
        spy.events.append(.restoreShortcutSplitMember(itemId, group.id, windowState.id))
    }
}

@MainActor
private final class BulkUnloadNotificationSpy: BrowserNotificationPresenting {
    private let spy: Spy

    init(spy: Spy) {
        self.spy = spy
    }

    func presentNotification(_ notification: BrowserNotification, in windowState: BrowserWindowState?) {}
    func presentProfileSwitchNotification(to profile: Profile, in windowState: BrowserWindowState?) {}
    func presentTabClosureNotification(tabCount: Int) {}
    func presentSpaceRenamedNotification(name: String, in windowState: BrowserWindowState?) {}
    func presentBackgroundTabOpenedNotification(tabId: UUID, in windowState: BrowserWindowState) {}
    func presentSplitViewLimitNotification(in windowState: BrowserWindowState) {}

    func presentTabUnloadedNotification(count: Int, in windowState: BrowserWindowState?) {
        guard let windowState else { return }
        spy.events.append(.unloadShortcutPins(spy.bulkUnloadPinIds, windowState.id))
        spy.bulkUnloadPinIds = []
    }
}

@MainActor
private final class Spy {
    var events: [BrowserSidebarCommandRoutingOwnerTests.Event] = []
    var bulkUnloadPinIds: [UUID] = []
    var lastPinnedLiveTabId: UUID?
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
        case unloadShortcutPin(UUID, UUID)
        case unloadShortcutPins([UUID], UUID)
    }
}
