import AppKit
import Combine
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi


/// Reordering within a container, and the visual boundary a drop commits to when split groups sit among the siblings.
@MainActor
final class SidebarDragReorderBoundaryTests: SidebarDragContextTestCase {
    func testSpacePinnedReorderMovesLauncherWithinSameSpace() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let first = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).allSatisfy { $0.folderId == nil })
    }

    func testEssentialsReorderMovesLauncherWithinSameProfile() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let first = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeEssentialPin(
            tabManager,
            in: space,
            profileId: profileId,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .essentials,
            item: dragItem(first)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .essentials,
                toContainer: .essentials,
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).allSatisfy { $0.profileId == profileId })
    }

    func testFolderChildReorderMovesLauncherWithinSameFolder() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let first = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/one",
            index: 0
        )
        let second = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/two",
            index: 1
        )
        let third = try makeFolderPin(
            tabManager,
            in: space,
            folderId: folder.id,
            url: "https://example.com/three",
            index: 2
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .folder(folder.id),
            item: dragItem(first)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(first),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).map(\.index), [0, 1, 2])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).allSatisfy { $0.folderId == folder.id })
    }

    func testFolderHeaderReorderMovesFolderWithinTopLevelPinnedSection() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let first = try makeFolder(tabManager, in: space.id, name: "One")
        let second = try makeFolder(tabManager, in: space.id, name: "Two")
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .folder(first),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 2
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(topLevelPinnedItemIDs(tabManager, in: space.id), [second.id, first.id])
        XCTAssertEqual(tabManager.folderCollectionStateOwner.folders(for: space.id).map(\.index), [0, 1])
    }

    func testFolderDropCommitsThePresentedBoundaryBesideSplitGroup() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let target = try makeFolder(
            tabManager,
            in: space.id,
            name: "Target"
        )
        let moving = try makeFolder(
            tabManager,
            in: space.id,
            name: "Moving"
        )
        let sibling = try makeFolder(
            tabManager,
            in: space.id,
            parentFolderId: target.id,
            name: "Sibling"
        )
        let members = try (0..<2).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: target.id,
                url: "https://split-folder-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: members.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: target.id,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(
            group,
            persist: false
        ))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: target.id),
            [.splitGroup(group.id), .folder(sibling.id)]
        )

        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spacePinned(space.id),
            item: dragItem(moving)
        )
        let didMove = tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .folder(moving),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(target.id),
                presentedVisualIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: target.id),
            [
                .splitGroup(group.id),
                .folder(moving.id),
                .folder(sibling.id),
            ]
        )
    }

    func testFolderShortcutReorderUsesSplitGroupAsOneVisualItem() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let folder = try makeFolder(
            tabManager,
            in: space.id,
            name: "Target"
        )
        let pins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://folder-split-reorder-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[1].id), .shortcutPin(pins[2].id)],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.shortcut(pins[0].id), .splitGroup(group.id), .shortcut(pins[3].id)]
        )

        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .folder(folder.id),
            item: dragItem(pins[3])
        )
        let didMove = tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .pin(pins[3]),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 1
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.shortcut(pins[0].id), .shortcut(pins[3].id), .splitGroup(group.id)]
        )

        let leadingScope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .folder(folder.id),
            item: dragItem(pins[0])
        )
        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .pin(pins[0]),
                scope: leadingScope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 3
            )
        ))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.shortcut(pins[3].id), .splitGroup(group.id), .shortcut(pins[0].id)]
        )
    }

    func testFolderLeadingShortcutMovesImmediatelyBelowSplitWithoutRotatingSiblings() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let folder = try makeFolder(tabManager, in: space.id, name: "Target")
        let pins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://folder-leading-below-split-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[1].id), .shortcutPin(pins[2].id)],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.shortcut(pins[0].id), .splitGroup(group.id), .shortcut(pins[3].id)]
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .folder(folder.id),
            item: dragItem(pins[0])
        )

        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .pin(pins[0]),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 2
            )
        ))

        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.splitGroup(group.id), .shortcut(pins[0].id), .shortcut(pins[3].id)]
        )
    }

    func testTopLevelFolderMovesOneRowAboveSiblingSplit() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let pins = try (0..<3).map { index in
            try makeSpacePinnedPin(
                tabManager,
                in: space,
                url: "https://top-level-folder-above-split-\(index).example",
                index: index
            )
        }
        let folder = try makeFolder(tabManager, in: space.id, name: "Moving")
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[0].id), .shortcutPin(pins[1].id)],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.splitGroup(group.id), .shortcut(pins[2].id), .folder(folder.id)]
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spacePinned(space.id),
            item: dragItem(folder)
        )

        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .folder(folder),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                presentedVisualIndex: 1
            )
        ))

        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [.splitGroup(group.id), .folder(folder.id), .shortcut(pins[2].id)]
        )
    }

    func testRepeatedLauncherReordersBelowSplitDoNotMoveSiblingFolder() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let pins = try (0..<4).map { index in
            try makeSpacePinnedPin(
                tabManager,
                in: space,
                url: "https://repeated-reorder-below-split-\(index).example",
                index: index
            )
        }
        let folder = try makeFolder(tabManager, in: space.id, name: "Stable")
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[0].id), .shortcutPin(pins[1].id)],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .splitGroup(group.id),
                .shortcut(pins[2].id),
                .shortcut(pins[3].id),
                .folder(folder.id),
            ]
        )

        func reorder(_ pin: ShortcutPin, to boundary: Int) throws {
            let scope = try makeScope(
                spaceId: space.id,
                profileId: profileID,
                sourceZone: .spacePinned(space.id),
                item: dragItem(pin)
            )
            XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
                SidebarDragCommitIntent(
                    payload: .pin(pin),
                    scope: scope,
                    fromContainer: .spacePinned(space.id),
                    toContainer: .spacePinned(space.id),
                    presentedVisualIndex: boundary
                )
            ))
        }

        try reorder(pins[2], to: 3)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .splitGroup(group.id),
                .shortcut(pins[3].id),
                .shortcut(pins[2].id),
                .folder(folder.id),
            ]
        )

        try reorder(pins[2], to: 1)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.topLevelItems(for: space.id),
            [
                .splitGroup(group.id),
                .shortcut(pins[2].id),
                .shortcut(pins[3].id),
                .folder(folder.id),
            ]
        )
    }

    func testFolderSplitGroupReorderUsesTheSameVisualBoundaryAsLaunchers() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let folder = try makeFolder(
            tabManager,
            in: space.id,
            name: "Target"
        )
        let pins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://folder-group-reorder-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [.shortcutPin(pins[1].id), .shortcutPin(pins[2].id)],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .folder(folder.id),
            item: .splitGroup(group.id, title: "Split")
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.shortcut(pins[0].id), .shortcut(pins[3].id), .splitGroup(group.id)]
        )
    }

}
