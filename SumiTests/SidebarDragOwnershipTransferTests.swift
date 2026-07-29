import AppKit
import Combine
import SumiDomain
import XCTest

@testable import Sumi

/// Canonical-instance rejection, folder structure operations, ownership moves between containers, and drag-scope rejection.
@MainActor
final class SidebarDragOwnershipTransferTests: SidebarDragContextTestCase {
    func testFolderPlacementRejectsNoncanonicalInstanceWithMatchingID() throws {
        let tabManager = BrowserManager()
        let space = try makeSpace(tabManager, name: "Work")
        let canonical = try makeFolder(
            tabManager,
            in: space.id,
            name: "Canonical"
        )
        let sibling = try makeFolder(
            tabManager,
            in: space.id,
            name: "Sibling"
        )
        let stale = TabFolder(
            id: canonical.id,
            name: canonical.name,
            spaceId: canonical.spaceId,
            index: canonical.index
        )
        let persistenceRevision = tabManager.structuralPersistence
            .schedulingRevision
        let publicationRevision = tabManager.structuralLookupCoordinator
            .mutationRevision

        let scope = try makeScope(
            spaceId: space.id,
            profileId: UUID(),
            sourceZone: .spacePinned(space.id),
            item: dragItem(stale)
        )
        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .folder(stale),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 2
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            persistenceRevision
        )
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            publicationRevision
        )
        XCTAssertEqual(
            topLevelPinnedItemIDs(tabManager, in: space.id),
            [canonical.id, sibling.id]
        )
    }

    func testDragRouterRejectsNoncanonicalRegularTabInstanceWithMatchingID() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let canonical = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/canonical",
            in: space,
            activate: false
        )
        let sibling = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/sibling",
            in: space,
            activate: false
        )
        let stale = Tab(
            id: canonical.id,
            url: canonical.url,
            name: canonical.name,
            spaceId: space.id,
            index: canonical.index,
            loadsCachedFaviconOnInit: false
        )
        stale.profileId = canonical.profileId
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(canonical)
        )
        let persistenceRevision = tabManager.structuralPersistence
            .schedulingRevision
        let publicationRevision = tabManager.structuralLookupCoordinator
            .mutationRevision

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(stale),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 2
            )
        )

        XCTAssertFalse(didMove)
        let tabs = tabManager.regularTabCollectionOwner.tabs(in: space)
        XCTAssertEqual(tabs.map(\.id), [canonical.id, sibling.id])
        XCTAssertTrue(tabs.first === canonical)
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            persistenceRevision
        )
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            publicationRevision
        )
    }

    func testFolderDropIntoFolderCreatesNestedFolder() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let target = try makeFolder(tabManager, in: space.id, name: "Target")
        let moving = try makeFolder(tabManager, in: space.id, name: "Moving")
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(moving)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .folder(moving),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(target.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(moving.parentFolderId, target.id)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [target.id])
        XCTAssertEqual(tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: target.id, in: space.id), [.folder(moving.id)])
    }

    func testFolderDropIntoDescendantIsRejected() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let parent = try makeFolder(tabManager, in: space.id, name: "Parent")
        let child = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: parent.id,
            name: "Child"
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(parent)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .folder(parent),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(child.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertNil(parent.parentFolderId)
        XCTAssertEqual(child.parentFolderId, parent.id)
    }

    func testUngroupFolderLiftsDirectChildrenOneLevel() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let root = try makeFolder(tabManager, in: space.id, name: "Root")
        let nested = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: root.id,
            name: "Nested"
        )
        let childFolder = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: nested.id,
            name: "Child"
        )
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: nested.id,
            url: "https://example.com/nested",
            index: 1
        )
        let liveTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-nested", in: space)
        liveTab.isSpacePinned = true
        liveTab.folderId = nested.id

        XCTAssertTrue(tabManager.sidebarFolderCommands.ungroupFolder(nested.id))

        XCTAssertNil(tabManager.folderCollectionStateOwner.folder(by: nested.id))
        XCTAssertEqual(childFolder.parentFolderId, root.id)
        let movedPin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertEqual(movedPin.folderId, root.id)
        XCTAssertEqual(liveTab.folderId, root.id)
        XCTAssertTrue(liveTab.isSpacePinned)
        XCTAssertEqual(tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: root.id, in: space.id), [
            .folder(childFolder.id),
            .shortcut(pin.id),
        ])
    }

    func testDeleteFolderRemovesDescendantChildren() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let root = try makeFolder(tabManager, in: space.id, name: "Root")
        let nested = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: root.id,
            name: "Nested"
        )
        let childFolder = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: nested.id,
            name: "Child"
        )
        let nestedPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: nested.id,
            url: "https://example.com/nested",
            index: 1
        )
        let childPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: childFolder.id,
            url: "https://example.com/child",
            index: 0
        )
        let liveTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-child", in: space)
        liveTab.isSpacePinned = true
        liveTab.folderId = childFolder.id

        XCTAssertEqual(tabManager.spacePinnedStructureOwner.folderRecursiveChildCount(for: nested.id, in: space.id), 3)

        XCTAssertTrue(tabManager.sidebarFolderCommands.deleteFolder(nested.id))

        XCTAssertNotNil(tabManager.folderCollectionStateOwner.folder(by: root.id))
        XCTAssertNil(tabManager.folderCollectionStateOwner.folder(by: nested.id))
        XCTAssertNil(tabManager.folderCollectionStateOwner.folder(by: childFolder.id))
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: nestedPin.id))
        XCTAssertNil(tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: childPin.id))
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: liveTab.id))
        XCTAssertEqual(tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: root.id, in: space.id), [])
    }

    func testSpacePinnedDropIntoFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let existingFolderPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/existing-folder",
            index: 0
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 1
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id])
        let folderPins = tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id)
        XCTAssertEqual(folderPins.map(\.id), [pin.id, existingFolderPin.id])
        let moved = try XCTUnwrap(folderPins.first)
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testSpacePinnedDropIntoEssentialsPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let existingEssential = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/existing-essential",
            index: 0
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
        let essentials = tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId)
        XCTAssertEqual(essentials.map(\.id), [pin.id, existingEssential.id])
        let moved = try XCTUnwrap(essentials.first)
        XCTAssertEqual(moved.role, .essential)
        XCTAssertEqual(moved.profileId, profileId)
        XCTAssertNil(moved.spaceId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testFolderChildDropIntoSpacePinnedPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder-child",
            index: 0
        )
        let existingTopLevelPin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/top-level",
            index: 1
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spacePinned(space.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id, pin.id, existingTopLevelPin.id])
        let moved = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testFolderChildDropIntoEssentialsPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let existingEssential = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/existing-essential",
            index: 0
        )
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder-child",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .essentials,
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        let essentials = tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId)
        XCTAssertEqual(essentials.map(\.id), [existingEssential.id, pin.id])
        let moved = try XCTUnwrap(essentials.first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .essential)
        XCTAssertEqual(moved.profileId, profileId)
        XCTAssertNil(moved.spaceId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testEssentialDropIntoSpacePinnedPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let existingTopLevelPin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/top-level",
            index: 1
        )
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .spacePinned(space.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).isEmpty)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [folder.id, pin.id, existingTopLevelPin.id])
        let moved = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.profileId)
        XCTAssertNil(moved.folderId)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testEssentialDropIntoFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let existingFolderPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/existing-folder",
            index: 0
        )
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .folder(folder.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).isEmpty)
        let folderPins = tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id)
        XCTAssertEqual(folderPins.map(\.id), [existingFolderPin.id, pin.id])
        let moved = try XCTUnwrap(folderPins.first { $0.id == pin.id })
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertNil(moved.profileId)
        XCTAssertEqual(moved.folderId, folder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testFolderChildDropIntoDifferentFolderPreservesLauncherAndMovesOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let sourceFolder = try makeFolder(tabManager, in: space.id, name: "Source")
        let targetFolder = try makeFolder(tabManager, in: space.id, name: "Target")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: sourceFolder.id,
            url: "https://example.com/source-child",
            index: 0
        )
        let existingTargetPin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: targetFolder.id,
            url: "https://example.com/target-child",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(sourceFolder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(sourceFolder.id),
                toContainer: .folder(targetFolder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: sourceFolder.id, in: space.id).isEmpty)
        let targetPins = tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: targetFolder.id, in: space.id)
        XCTAssertEqual(targetPins.map(\.id), [pin.id, existingTargetPin.id])
        let moved = try XCTUnwrap(targetPins.first)
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(moved.spaceId, space.id)
        XCTAssertEqual(moved.folderId, targetFolder.id)
        XCTAssertEqual(moved.launchURL, pin.launchURL)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
    }

    func testSpacePinnedDropIntoRegularCreatesRegularTabAndRemovesLauncher() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/pinned",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: space.id).isEmpty
        )
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testSeparatingRegularSplitExpandsMembersAtGroupPosition() throws {
        let harness = try makeLiveWindowHarness()
        let browser = harness.browserManager
        let space = try makeSpace(browser, name: "Work")
        let tabs = ["a", "b", "c", "d"].map { name in
            browser.regularTabLifecycleOwner.createNewTab(
                url: "https://\(name).example",
                in: space,
                activate: false
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(tabs[1].id),
                .regularTab(tabs[3].id),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group))
        harness.windowState.currentSpaceId = space.id

        browser.splitLayout.separate(
            .regularTab(tabs[3].id),
            from: group.id,
            in: harness.windowState
        )

        XCTAssertNil(browser.splitGroupStore.group(id: group.id))
        XCTAssertEqual(
            browser.regularTabCollectionOwner.tabs(in: space.id).map(\.id),
            [tabs[0].id, tabs[1].id, tabs[3].id, tabs[2].id]
        )
    }

    func testSeparatingPinnedSplitExpandsLaunchersAtGroupPosition() throws {
        let harness = try makeLiveWindowHarness()
        let browser = harness.browserManager
        let profileID = UUID()
        let space = try makeSpace(
            browser,
            name: "Work",
            profileId: profileID
        )
        let pins = try ["a", "b", "c", "d"].enumerated().map {
            index, name in
            try makeSpacePinnedPin(
                browser,
                in: space,
                url: "https://\(name).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pins[1].id),
                .shortcutPin(pins[3].id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: nil,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group))
        harness.windowState.currentSpaceId = space.id

        browser.splitLayout.separate(
            .shortcutPin(pins[3].id),
            from: group.id,
            in: harness.windowState
        )

        XCTAssertNil(browser.splitGroupStore.group(id: group.id))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .shortcut(pins[0].id),
                .shortcut(pins[1].id),
                .shortcut(pins[3].id),
                .shortcut(pins[2].id),
            ]
        )
    }

    func testSeparatingOnePinnedMemberKeepsRemainingGroupAtOriginalPosition()
        throws {
        let harness = try makeLiveWindowHarness()
        let browser = harness.browserManager
        let profileID = UUID()
        let space = try makeSpace(
            browser,
            name: "Work",
            profileId: profileID
        )
        let pins = try ["a", "b", "c", "d", "e"].enumerated().map {
            index, name in
            try makeSpacePinnedPin(
                browser,
                in: space,
                url: "https://\(name).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pins[1].id),
                .shortcutPin(pins[3].id),
                .shortcutPin(pins[4].id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: nil,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group))
        harness.windowState.currentSpaceId = space.id

        browser.splitLayout.separate(
            .shortcutPin(pins[3].id),
            from: group.id,
            in: harness.windowState
        )

        let remainingGroup = try XCTUnwrap(
            browser.splitGroupStore.group(id: group.id)
        )
        XCTAssertEqual(
            remainingGroup.memberIDs,
            [.shortcutPin(pins[1].id), .shortcutPin(pins[4].id)]
        )
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .shortcut(pins[0].id),
                .splitGroup(group.id),
                .shortcut(pins[3].id),
                .shortcut(pins[2].id),
            ]
        )
    }

    func testSeparatingEssentialSplitExpandsLaunchersAtTilePosition() throws {
        let harness = try makeLiveWindowHarness()
        let browser = harness.browserManager
        let profileID = UUID()
        let space = try makeSpace(
            browser,
            name: "Work",
            profileId: profileID
        )
        let pins = try ["a", "b", "c", "d"].enumerated().map {
            index, name in
            try makeEssentialPin(
                browser,
                in: space,
                profileId: profileID,
                url: "https://\(name).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pins[1].id),
                .shortcutPin(pins[3].id),
            ],
            layoutKind: .vertical,
            container: .essentialSidebar(
                profileId: profileID,
                index: 1
            )
        ))
        XCTAssertTrue(browser.splitGroupMutations.insert(group))

        browser.splitLayout.separate(
            .shortcutPin(pins[3].id),
            from: group.id,
            in: harness.windowState
        )

        XCTAssertNil(browser.splitGroupStore.group(id: group.id))
        XCTAssertEqual(
            browser.splitGroupSidebarOrdering.essentialItems(for: profileID),
            [
                .shortcut(pins[0].id),
                .shortcut(pins[1].id),
                .shortcut(pins[3].id),
                .shortcut(pins[2].id),
            ]
        )
    }

    func testFolderChildDropIntoRegularCreatesRegularTabAndRemovesFolderOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let pin = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/folder",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).isEmpty)
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.folderId)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testEssentialDropIntoRegularCreatesRegularTabAndRemovesEssentialOwnership() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let pin = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/essential",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).isEmpty)
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
    }

    func testSpacePinnedWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .spacePinned)
    }

    func testFolderChildWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .folder)
    }

    func testEssentialWithLiveShortcutDropIntoRegularReusesLiveTabAndClearsBinding() throws {
        try assertLiveLauncherDropIntoRegularReusesLiveTab(source: .essentials)
    }

    func testLauncherWithoutLiveShortcutDropIntoRegularCreatesNewRegularTab() throws {
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .spacePinned)
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .folder)
        try assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(source: .essentials)
    }

    func testMovingLiveLauncherBetweenShortcutSectionsPreservesLiveBinding() throws {
        try assertLiveLauncherMovePreservesBinding(source: .spacePinned, destination: .folder)
        try assertLiveLauncherMovePreservesBinding(source: .folder, destination: .essentials)
        try assertLiveLauncherMovePreservesBinding(source: .essentials, destination: .spacePinned)
    }

    func testWrongProfileScopeIsRejectedEvenWhenSpaceMatches() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let wrongProfileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: wrongProfileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id), [tab.id])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
    }

    func testMismatchedSourceContainerIsRejectedEvenWhenTargetIsCurrentSpace() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id), [tab.id])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
    }

    func testCrossSpaceDropTargetIsRejected() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let sourceSpace = try makeSpace(tabManager, name: "Source", profileId: profileId)
        let targetSpace = try makeSpace(tabManager, name: "Target", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: sourceSpace)
        let scope = try makeScope(
            spaceId: sourceSpace.id,
            profileId: profileId,
            sourceZone: .spaceRegular(sourceSpace.id),
            item: dragItem(tab)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .spaceRegular(targetSpace.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: sourceSpace.id).map(\.id), [tab.id])
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: targetSpace.id).isEmpty)
    }

    func testPayloadFromDifferentSpaceIsRejectedEvenWhenSourceScopeNamesCurrentSpace() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let sourceSpace = try makeSpace(tabManager, name: "Source", profileId: profileId)
        let otherSpace = try makeSpace(tabManager, name: "Other", profileId: profileId)
        let sourceTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/source", in: sourceSpace)
        let otherTab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/other", in: otherSpace)
        let scope = try makeScope(
            spaceId: sourceSpace.id,
            profileId: profileId,
            sourceZone: .spaceRegular(sourceSpace.id),
            item: dragItem(otherTab)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(otherTab),
                scope: scope,
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .spacePinned(sourceSpace.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(didMove)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: sourceSpace.id).map(\.id), [sourceTab.id])
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: otherSpace.id).map(\.id), [otherTab.id])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: sourceSpace.id).isEmpty)
    }
}
