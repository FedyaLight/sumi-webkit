import AppKit
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragSourceInventoryTests: XCTestCase {
    func testRetainedInventoryDoesNotRetainTabManager() throws {
        var tabManager: TabManager? = try makeInMemoryTabManager()
        let inventory = makeInventory(from: try XCTUnwrap(tabManager))
        weak let releasedTabManager = tabManager

        tabManager = nil

        XCTAssertNil(releasedTabManager)
        withExtendedLifetime(inventory) {}
    }

    func testEssentialsSourceIndexAndItemCount() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
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
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
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
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://a.example", in: space, activate: false)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://b.example", in: space, activate: false)
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
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Work", profileId: profileId)
        let folder = tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
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
        let tabManager = try makeInMemoryTabManager()
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

    private func makeInventory(from tabManager: TabManager) -> SidebarDragSourceInventory {
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
        _ tabManager: TabManager,
        in space: Space,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: nil,
                at: index
            )
        )
    }

    private func makeFolderPin(
        _ tabManager: TabManager,
        in space: Space,
        folderId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .spacePinned,
                profileId: nil,
                spaceId: space.id,
                folderId: folderId,
                at: index,
                openTargetFolder: false
            )
        )
    }

    private func makeEssentialPin(
        _ tabManager: TabManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.shortcutPinCommandOwner.convertTabToShortcutPin(
                tab,
                role: .essential,
                profileId: profileId,
                spaceId: nil,
                folderId: nil,
                at: index
            )
        )
    }
}
