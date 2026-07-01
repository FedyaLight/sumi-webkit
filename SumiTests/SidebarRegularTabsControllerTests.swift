@testable import Sumi
import XCTest

@MainActor
final class SidebarRegularTabsControllerTests: XCTestCase {
    func testControllerRoutesRegularTabStateAndCommandsThroughDependencies() throws {
        let spy = SidebarRegularTabsControllerSpy()
        let space = Space(name: "Work")
        let otherSpace = Space(name: "Other")
        let tab = makeTab(spaceId: space.id)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/pin")),
            title: "Pinned"
        )
        let userFolder = TabFolder(name: "User", spaceId: space.id)
        let liveFolder = TabFolder(name: "Live", spaceId: space.id)
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tab.id, UUID()], layoutKind: .vertical))
        let windowState = BrowserWindowState()
        let targetSpaceId = otherSpace.id
        let profileId = UUID()

        let controller = SidebarRegularTabsController(
            dependencies: SidebarRegularTabsController.Dependencies(
                spaces: {
                    spy.events.append(.spaces)
                    return [space, otherSpace]
                },
                tabs: { requestedSpace in
                    spy.events.append(.tabs(requestedSpace.id))
                    return [tab]
                },
                tab: { tabId in
                    spy.events.append(.tab(tabId))
                    return tabId == tab.id ? tab : nil
                },
                splitGroup: { tabId in
                    spy.events.append(.splitGroup(tabId))
                    return group.contains(tabId) ? group : nil
                },
                shortcutPin: { pinId in
                    spy.events.append(.shortcutPin(pinId))
                    return pinId == pin.id ? pin : nil
                },
                folders: { spaceId in
                    spy.events.append(.folders(spaceId))
                    return [userFolder, liveFolder]
                },
                isLiveFolder: { folderId in
                    spy.events.append(.isLiveFolder(folderId))
                    return folderId == liveFolder.id
                },
                canAddURLToEssentials: { url, context in
                    spy.events.append(.canAddURLToEssentials(url, context.spaceId, context.windowState?.id))
                    return true
                },
                clearRegularTabs: { spaceId in
                    spy.events.append(.clearRegularTabs(spaceId))
                },
                pinTabToSpace: { tab, spaceId in
                    spy.events.append(.pinTabToSpace(tab.id, spaceId))
                },
                pinTabToEssentials: { tab, context in
                    spy.events.append(.pinTabToEssentials(tab.id, context.spaceId, context.windowState?.id))
                },
                closeAllTabsBelow: { tab in
                    spy.events.append(.closeAllTabsBelow(tab.id))
                },
                moveTab: { tabId, spaceId in
                    spy.events.append(.moveTab(tabId, spaceId))
                },
                moveTabToFolder: { tab, folderId in
                    spy.events.append(.moveTabToFolder(tab.id, folderId))
                },
                assignTabToProfile: { tab, profileId in
                    spy.events.append(.assignTabToProfile(tab.id, profileId))
                    return true
                }
            )
        )

        XCTAssertEqual(controller.spaces.map(\.id), [space.id, otherSpace.id])
        XCTAssertEqual(controller.tabs(in: space, windowState: windowState).map(\.id), [tab.id])
        XCTAssertTrue(controller.hasPersistedTabs(in: space))
        XCTAssertIdentical(controller.tab(for: tab.id), tab)
        XCTAssertEqual(controller.splitGroup(containing: tab.id)?.id, group.id)
        XCTAssertEqual(controller.shortcutPin(by: pin.id)?.id, pin.id)
        XCTAssertEqual(controller.userFolders(for: space.id).map(\.id), [userFolder.id])
        XCTAssertTrue(controller.canAddToEssentials(tab, in: space, windowState: windowState))

        controller.clearRegularTabs(for: space.id)
        controller.pinTabToSpace(tab, spaceId: space.id)
        controller.addTabToEssentials(tab, in: space, windowState: windowState)
        controller.closeAllTabsBelow(tab)
        controller.moveTab(tab.id, to: targetSpaceId)
        controller.moveTabToFolder(tab, folderId: userFolder.id)
        XCTAssertTrue(controller.assign(tab, toProfile: profileId))

        let expectedEvents: [Event] = [
            .spaces,
            .tabs(space.id),
            .tabs(space.id),
            .tab(tab.id),
            .splitGroup(tab.id),
            .shortcutPin(pin.id),
            .folders(space.id),
            .isLiveFolder(userFolder.id),
            .isLiveFolder(liveFolder.id),
            .canAddURLToEssentials(tab.url, space.id, windowState.id),
            .clearRegularTabs(space.id),
            .pinTabToSpace(tab.id, space.id),
            .pinTabToEssentials(tab.id, space.id, windowState.id),
            .closeAllTabsBelow(tab.id),
            .moveTab(tab.id, targetSpaceId),
            .moveTabToFolder(tab.id, userFolder.id),
            .assignTabToProfile(tab.id, profileId),
        ]
        XCTAssertEqual(spy.events, expectedEvents)
    }

    func testIncognitoTabsComeFromWindowStateWithoutTouchingPersistedTabStore() {
        let spy = SidebarRegularTabsControllerSpy()
        let space = Space(name: "Private")
        let first = makeTab(spaceId: space.id, index: 1)
        let second = makeTab(spaceId: space.id, index: 0)
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.ephemeralTabs = [first, second]

        let controller = SidebarRegularTabsController(
            dependencies: SidebarRegularTabsController.Dependencies(
                spaces: { [] },
                tabs: { _ in
                    spy.events.append(.tabs(space.id))
                    return []
                },
                tab: { _ in nil },
                splitGroup: { _ in nil },
                shortcutPin: { _ in nil },
                folders: { _ in [] },
                isLiveFolder: { _ in false },
                canAddURLToEssentials: { _, _ in false },
                clearRegularTabs: { _ in /* No-op. */ },
                pinTabToSpace: { _, _ in /* No-op. */ },
                pinTabToEssentials: { _, _ in /* No-op. */ },
                closeAllTabsBelow: { _ in /* No-op. */ },
                moveTab: { _, _ in /* No-op. */ },
                moveTabToFolder: { _, _ in /* No-op. */ },
                assignTabToProfile: { _, _ in false }
            )
        )

        XCTAssertEqual(controller.tabs(in: space, windowState: windowState).map(\.id), [second.id, first.id])
        XCTAssertTrue(spy.events.isEmpty)
    }

    func testRegularTabsSectionUsesControllerInsteadOfDirectTabManagerAccess() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(
            "Sumi/Components/Sidebar/SpaceSection/SpaceRegularTabsSection.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("browserContext.tabManager"))
    }

    private func makeTab(spaceId: UUID, index: Int = 0) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(index)") ?? preconditionFailure("Invalid test URL"),
            name: "Example \(index)",
            favicon: "globe",
            spaceId: spaceId,
            index: index
        )
    }
}

private final class SidebarRegularTabsControllerSpy {
    var events: [SidebarRegularTabsControllerTests.Event] = []
}

extension SidebarRegularTabsControllerTests {
    enum Event: Equatable {
        case spaces
        case tabs(UUID)
        case tab(UUID)
        case splitGroup(UUID)
        case shortcutPin(UUID)
        case folders(UUID)
        case isLiveFolder(UUID)
        case canAddURLToEssentials(URL, UUID?, UUID?)
        case clearRegularTabs(UUID)
        case pinTabToSpace(UUID, UUID)
        case pinTabToEssentials(UUID, UUID?, UUID?)
        case closeAllTabsBelow(UUID)
        case moveTab(UUID, UUID)
        case moveTabToFolder(UUID, UUID)
        case assignTabToProfile(UUID, UUID)
    }
}
