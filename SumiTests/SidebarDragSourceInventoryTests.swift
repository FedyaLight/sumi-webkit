import AppKit
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragSourceInventoryTests: XCTestCase {
    func testRetainedInventoryDoesNotRetainTabManager() throws {
        var tabManager: BrowserManager? = BrowserManager()
        let inventory = makeInventory(from: try XCTUnwrap(tabManager))
        weak let releasedTabManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedTabManager)
        withExtendedLifetime(inventory) {}
    }

    func testEssentialsSourceIndexAndItemCount() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = makeSpace(tabManager, profileId: profileId)
        let first = try makeEssentialPin(tabManager, in: space, profileId: profileId, url: "https://a.example", index: 0)
        let second = try makeEssentialPin(tabManager, in: space, profileId: profileId, url: "https://b.example", index: 1)
        let third = try makeEssentialPin(tabManager, in: space, profileId: profileId, url: "https://c.example", index: 2)
        let inventory = makeInventory(from: tabManager)
        let scope = makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceContainer: .essentials,
            sourceItemId: second.id
        )

        XCTAssertEqual(inventory.sourceContainerItemCount(for: scope), 3)
        XCTAssertEqual(
            inventory.sourceIndex(for: .pin(second), scope: scope),
            1
        )
        XCTAssertEqual(
            inventory.sourceIdentities(for: scope),
            [.pin(first.id), .pin(second.id), .pin(third.id)]
        )
    }

    func testSpacePinnedSourceProjection() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = makeSpace(tabManager, profileId: profileId)
        let first = try makeSpacePinnedPin(tabManager, in: space, url: "https://a.example", index: 0)
        let second = try makeSpacePinnedPin(tabManager, in: space, url: "https://b.example", index: 1)
        let inventory = makeInventory(from: tabManager)
        let scope = makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceContainer: .spacePinned(space.id),
            sourceItemId: first.id
        )

        XCTAssertEqual(inventory.sourceContainerItemCount(for: scope), 2)
        XCTAssertEqual(inventory.sourceIndex(for: .pin(first), scope: scope), 0)
        XCTAssertEqual(
            inventory.sourceIdentities(for: scope),
            [.pin(first.id), .pin(second.id)]
        )
    }

    func testRegularTabSourceProjection() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = makeSpace(tabManager, profileId: profileId)
        let first = makeRegularTab(tabManager, in: space, url: "https://a.example", index: 0)
        let second = makeRegularTab(tabManager, in: space, url: "https://b.example", index: 1)
        let inventory = makeInventory(from: tabManager)
        let scope = makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceContainer: .spaceRegular(space.id),
            sourceItemId: second.id
        )

        XCTAssertEqual(inventory.sourceContainerItemCount(for: scope), 2)
        XCTAssertEqual(inventory.sourceIndex(for: .tab(second), scope: scope), 1)
        XCTAssertEqual(
            inventory.sourceIdentities(for: scope),
            [.tab(first.id), .tab(second.id)]
        )
    }

    func testFolderChildSourceProjection() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = makeSpace(tabManager, profileId: profileId)
        let folder = TabFolder(name: "Docs", spaceId: space.id)
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [folder],
        ])
        let first = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://a.example",
            index: 0
        )
        let second = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://b.example",
            index: 1
        )
        let inventory = makeInventory(from: tabManager)
        let scope = makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceContainer: .folder(folder.id),
            sourceItemId: second.id
        )

        XCTAssertEqual(inventory.sourceContainerItemCount(for: scope), 2)
        XCTAssertEqual(inventory.sourceIndex(for: .pin(second), scope: scope), 1)
        XCTAssertEqual(
            inventory.sourceIdentities(for: scope),
            [.pin(first.id), .pin(second.id)]
        )
    }

    func testShortcutSplitFolderIdentityMatching() throws {
        let pinId = UUID()
        let folderId = UUID()
        let groupId = UUID()
        let pin = ShortcutPin(
            id: pinId,
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: URL(string: "https://pin.example")!,
            title: "Pin"
        )
        let folder = TabFolder(id: folderId, name: "Docs", spaceId: UUID())
        let group = try XCTUnwrap(
            SplitGroup.make(
                id: groupId,
                members: [
                    .shortcutPin(UUID(), returnPlacement: .spacePinned(spaceId: UUID(), folderId: nil, index: 0)),
                    .shortcutPin(UUID(), returnPlacement: .spacePinned(spaceId: UUID(), folderId: nil, index: 1)),
                ],
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: UUID(),
                    profileId: nil,
                    folderId: nil,
                    index: 0
                )
            )
        )

        XCTAssertTrue(
            SidebarDragSourceMembership.matches(
                .pin(pinId),
                sourceItemId: UUID(),
                payload: .pin(pin)
            )
        )
        XCTAssertTrue(
            SidebarDragSourceMembership.matches(
                .folder(folderId),
                sourceItemId: UUID(),
                payload: .folder(folder)
            )
        )
        XCTAssertTrue(
            SidebarDragSourceMembership.matches(
                .splitGroup(groupId),
                sourceItemId: UUID(),
                payload: .splitGroup(group)
            )
        )
        XCTAssertEqual(
            SidebarDragSourceMembership.sourceIndex(
                in: [.folder(UUID()), .pin(pinId), .splitGroup(groupId)],
                sourceItemId: UUID(),
                payload: .pin(pin)
            ),
            1
        )
    }

    func testStaleFolderScopeReturnsNilInventory() throws {
        let tabManager = BrowserManager()
        let inventory = makeInventory(from: tabManager)
        let scope = makeScope(
            spaceId: UUID(),
            profileId: UUID(),
            sourceContainer: .folder(UUID()),
            sourceItemId: UUID()
        )

        XCTAssertNil(inventory.sourceIdentities(for: scope))
        XCTAssertNil(inventory.sourceContainerItemCount(for: scope))
        XCTAssertNil(
            inventory.sourceIndex(
                for: .pin(
                    ShortcutPin(
                        id: UUID(),
                        role: .essential,
                        profileId: UUID(),
                        index: 0,
                        launchURL: URL(string: "https://stale.example")!,
                        title: "Stale"
                    )
                ),
                scope: scope
            )
        )
    }

    private func makeInventory(from tabManager: BrowserManager) -> SidebarDragSourceInventory {
        SidebarDragSourceInventory(
            essentialPins: tabManager.shortcutPinCollectionStateOwner,
            splitOrdering: tabManager.splitGroupSidebarOrdering,
            regularTabs: tabManager.regularTabCollectionOwner,
            folders: tabManager.folderCollectionStateOwner,
            spacePinned: tabManager.spacePinnedStructureOwner
        )
    }

    private func makeScope(
        spaceId: UUID,
        profileId: UUID,
        sourceContainer: TabDragManager.DragContainer,
        sourceItemId: UUID
    ) -> SidebarDragScope {
        SidebarDragScope(
            windowId: nil,
            spaceId: spaceId,
            profileId: profileId,
            sourceContainer: sourceContainer,
            sourceItemId: sourceItemId,
            sourceItemKind: .tab
        )
    }

    private func makeSpacePinnedPin(
        _ tabManager: BrowserManager,
        in space: Space,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: index,
            launchURL: try XCTUnwrap(URL(string: url)),
            title: url
        )
        var pins = tabManager.shortcutPinCollectionStateOwner
            .spacePinnedShortcutsSnapshot()
        pins[space.id, default: []].append(pin)
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts(pins)
        return pin
    }

    private func makeFolderPin(
        _ tabManager: BrowserManager,
        in space: Space,
        folderId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: index,
            folderId: folderId,
            launchURL: try XCTUnwrap(URL(string: url)),
            title: url
        )
        var pins = tabManager.shortcutPinCollectionStateOwner
            .spacePinnedShortcutsSnapshot()
        pins[space.id, default: []].append(pin)
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts(pins)
        return pin
    }

    private func makeEssentialPin(
        _ tabManager: BrowserManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: index,
            launchURL: try XCTUnwrap(URL(string: url)),
            title: url
        )
        var pins = tabManager.shortcutPinCollectionStateOwner
            .pinnedByProfileSnapshot()
        pins[profileId, default: []].append(pin)
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile(pins)
        return pin
    }

    private func makeSpace(
        _ tabManager: BrowserManager,
        profileId: UUID
    ) -> Space {
        let space = Space(name: "Work", profileId: profileId)
        tabManager.spaceStateOwner.append(space)
        return space
    }

    private func makeRegularTab(
        _ tabManager: BrowserManager,
        in space: Space,
        url: String,
        index: Int
    ) -> Tab {
        let tab = Tab(
            url: URL(string: url)!,
            spaceId: space.id,
            index: index,
            loadsCachedFaviconOnInit: false
        )
        var tabs = tabManager.tabStateStore.regularTabs.tabsBySpaceSnapshot()
        tabs[space.id, default: []].append(tab)
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace(tabs)
        return tab
    }
}
