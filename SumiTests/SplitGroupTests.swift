import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SplitGroupTests: SplitGroupTestCase {
    private struct LegacySplitGroupPayload: Encodable {
        let id: UUID
        let layoutKind: SplitLayoutKind
        let layoutTree: SplitLayoutTree
        let activeTabId: UUID?
    }

    func testRejectsInvalidTabCounts() {
        XCTAssertNil(SplitGroup.make(tabIds: [UUID()], layoutKind: .vertical))
        XCTAssertNil(SplitGroup.make(tabIds: makeIDs(5), layoutKind: .grid))
    }

    func testLegacySplitGroupDecodeDefaultsToRegularHost() throws {
        let ids = makeIDs(2)
        let original = try XCTUnwrap(SplitGroup.make(tabIds: ids, layoutKind: .vertical, activeTabId: ids[0]))
        let legacyPayload = LegacySplitGroupPayload(
            id: original.id,
            layoutKind: original.layoutKind,
            layoutTree: original.layoutTree,
            activeTabId: original.activeTabId
        )

        let data = try JSONEncoder().encode(legacyPayload)
        let decoded = try JSONDecoder().decode(SplitGroup.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.tabIds, original.tabIds)
        XCTAssertEqual(decoded.host, .regular(spaceId: nil))
        XCTAssertTrue(decoded.members.isEmpty)
    }

    func testSanitizedDropsGroupsOverlappingByShortcutPin() throws {
        let ids = makeIDs(4)
        let pinId = UUID()
        let spaceId = UUID()
        let first = try XCTUnwrap(SplitGroup.make(
            tabIds: [ids[0], ids[1]],
            layoutKind: .vertical,
            members: [
                SplitGroupMember(
                    tabId: ids[0],
                    pinId: pinId,
                    origin: .spacePinned(spaceId: spaceId, folderId: nil, index: 0)
                ),
            ]
        ))
        let overlapping = try XCTUnwrap(SplitGroup.make(
            tabIds: [ids[2], ids[3]],
            layoutKind: .horizontal,
            members: [
                SplitGroupMember(
                    tabId: ids[2],
                    pinId: pinId,
                    origin: .spacePinned(spaceId: spaceId, folderId: nil, index: 0)
                ),
            ]
        ))

        let sanitized = SplitGroup.sanitized([first, overlapping])

        XCTAssertEqual(sanitized.map(\.id), [first.id])
    }

    func testShortcutHostedSplitGroupAppearsInsidePinnedVisualItemsAtHostIndex() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let visiblePin = makeSpacePin(spaceId: space.id, index: 0, title: "Visible")
        let groupedPin = makeSpacePin(spaceId: space.id, index: 1, title: "Grouped")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([visiblePin, groupedPin], for: space.id)

        let otherId = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [groupedPin.id, otherId],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: 1),
            members: [
                SplitGroupMember(
                    tabId: groupedPin.id,
                    pinId: groupedPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 1)
                ),
                SplitGroupMember(
                    tabId: otherId,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: nil)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.shortcut(visiblePin.id), .splitGroup(group.id)]
        )
    }

    func testShortcutHostedSplitGroupForFolderPinStaysInsideFolderVisualItems() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let folder = harness.tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let visiblePin = makeSpacePin(spaceId: space.id, index: 0, title: "Visible")
        let groupedPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://grouped.example")!,
            title: "Grouped"
        )
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([visiblePin, groupedPin], for: space.id)

        let otherId = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [groupedPin.id, otherId],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: 0),
            members: [
                SplitGroupMember(
                    tabId: groupedPin.id,
                    pinId: groupedPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: folder.id, index: 0)
                ),
                SplitGroupMember(
                    tabId: otherId,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: nil)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.folder(folder.id), .shortcut(visiblePin.id)]
        )
        XCTAssertEqual(
            harness.tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: folder.id, in: space.id),
            [.splitGroup(group.id)]
        )
    }

    func testShortcutHostedSplitGroupWithFolderAndTopLevelPinsHidesTopLevelMemberUntilRestore() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        harness.windowState.currentSpaceId = space.id
        let folder = harness.tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let folderPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://folder.example")!,
            title: "Folder"
        )
        let groupedTopLevelPin = makeSpacePin(spaceId: space.id, index: 1, title: "GroupedTop")
        let visibleTopLevelPin = makeSpacePin(spaceId: space.id, index: 2, title: "VisibleTop")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [folderPin, groupedTopLevelPin, visibleTopLevelPin],
            for: space.id
        )

        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [folderPin.id, groupedTopLevelPin.id],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: 0),
            members: [
                SplitGroupMember(
                    tabId: folderPin.id,
                    pinId: folderPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: folder.id, index: 0)
                ),
                SplitGroupMember(
                    tabId: groupedTopLevelPin.id,
                    pinId: groupedTopLevelPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 1)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.folder(folder.id), .shortcut(visibleTopLevelPin.id)]
        )
        XCTAssertEqual(
            harness.tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: folder.id, in: space.id),
            [.splitGroup(group.id)]
        )

        harness.browserManager.sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
            groupedTopLevelPin.id,
            from: group,
            in: harness.windowState
        )

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.folder(folder.id), .shortcut(groupedTopLevelPin.id), .shortcut(visibleTopLevelPin.id)]
        )
        XCTAssertEqual(
            harness.tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: folder.id, in: space.id),
            [.shortcut(folderPin.id)]
        )
    }

    func testShortcutHostedSplitGroupWithTopLevelHostAndFolderPinStaysTopLevel() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        harness.windowState.currentSpaceId = space.id
        let folder = harness.tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let folderPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://folder.example")!,
            title: "Folder"
        )
        let topLevelHostPin = makeSpacePin(spaceId: space.id, index: 1, title: "TopHost")
        let visibleTopLevelPin = makeSpacePin(spaceId: space.id, index: 2, title: "VisibleTop")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [folderPin, topLevelHostPin, visibleTopLevelPin],
            for: space.id
        )

        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [folderPin.id, topLevelHostPin.id],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: topLevelHostPin.index),
            members: [
                SplitGroupMember(
                    tabId: folderPin.id,
                    pinId: folderPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: folder.id, index: folderPin.index)
                ),
                SplitGroupMember(
                    tabId: topLevelHostPin.id,
                    pinId: topLevelHostPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: topLevelHostPin.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.folder(folder.id), .splitGroup(group.id), .shortcut(visibleTopLevelPin.id)]
        )
        XCTAssertEqual(
            harness.tabManager.spacePinnedStructureOwner.folderChildVisualItems(for: folder.id, in: space.id),
            []
        )
    }

    func testSplitGroupVisualOrderingResolverProjectsTopLevelAndFolderItems() throws {
        let spaceId = UUID()
        let folder = TabFolder(name: "Docs", spaceId: spaceId, index: 1)
        let childFolder = TabFolder(
            name: "Nested",
            spaceId: spaceId,
            parentFolderId: folder.id,
            index: 0
        )
        let visibleTopLevelPin = makeSpacePin(spaceId: spaceId, index: 2, title: "Visible")
        let visibleFolderPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://folder-visible.example")!,
            title: "FolderVisible"
        )
        let groupedTopLevelPin = makeSpacePin(spaceId: spaceId, index: 0, title: "GroupedTop")
        let groupedFolderPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://folder-grouped.example")!,
            title: "FolderGrouped"
        )

        let topLevelGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [groupedTopLevelPin.id, UUID()],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: spaceId, profileId: nil, index: groupedTopLevelPin.index),
            members: [
                SplitGroupMember(
                    tabId: groupedTopLevelPin.id,
                    pinId: groupedTopLevelPin.id,
                    origin: .spacePinned(spaceId: spaceId, folderId: nil, index: groupedTopLevelPin.index)
                ),
            ]
        ))
        let folderGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [groupedFolderPin.id, UUID()],
            layoutKind: .horizontal,
            host: .shortcutPinned(spaceId: spaceId, profileId: nil, index: groupedFolderPin.index),
            members: [
                SplitGroupMember(
                    tabId: groupedFolderPin.id,
                    pinId: groupedFolderPin.id,
                    origin: .spacePinned(spaceId: spaceId, folderId: folder.id, index: groupedFolderPin.index)
                ),
            ]
        ))

        let resolver = SplitGroupVisualOrderingResolver(
            spaceId: spaceId,
            splitGroups: [folderGroup, topLevelGroup],
            folders: [folder, childFolder],
            spacePinnedPins: [
                visibleTopLevelPin,
                visibleFolderPin,
                groupedTopLevelPin,
                groupedFolderPin,
            ]
        )

        XCTAssertEqual(
            resolver.topLevelItems(),
            [.splitGroup(topLevelGroup.id), .folder(folder.id), .shortcut(visibleTopLevelPin.id)]
        )
        XCTAssertEqual(
            resolver.folderItems(for: folder.id),
            [.splitGroup(folderGroup.id), .folder(childFolder.id), .shortcut(visibleFolderPin.id)]
        )
        XCTAssertEqual(resolver.hiddenPinIds(), Set([groupedTopLevelPin.id, groupedFolderPin.id]))
    }

    func testEssentialOnlyShortcutHostedSplitStartsBeforePinnedRows() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let folder = harness.tabManager.folderMutationOwner.createFolder(for: space.id, name: "Docs")
        let visiblePin = makeSpacePin(spaceId: space.id, index: 0, title: "Visible")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([visiblePin], for: space.id)

        let firstEssentialId = UUID()
        let secondEssentialId = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [firstEssentialId, secondEssentialId],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: 0),
            members: [
                SplitGroupMember(
                    tabId: firstEssentialId,
                    pinId: firstEssentialId,
                    origin: .essential(profileId: nil, index: 0)
                ),
                SplitGroupMember(
                    tabId: secondEssentialId,
                    pinId: secondEssentialId,
                    origin: .essential(profileId: nil, index: 1)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.splitGroup(group.id), .folder(folder.id), .shortcut(visiblePin.id)]
        )
    }

    func testMovingShortcutHostedSplitGroupUpdatesPinnedVisualIndex() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let firstPin = makeSpacePin(spaceId: space.id, index: 0, title: "First")
        let groupedPin = makeSpacePin(spaceId: space.id, index: 1, title: "Grouped")
        let lastPin = makeSpacePin(spaceId: space.id, index: 2, title: "Last")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([firstPin, groupedPin, lastPin], for: space.id)

        let otherId = UUID()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [groupedPin.id, otherId],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: 1),
            members: [
                SplitGroupMember(
                    tabId: groupedPin.id,
                    pinId: groupedPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 1)
                ),
                SplitGroupMember(
                    tabId: otherId,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: nil)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        XCTAssertTrue(harness.tabManager.splitGroupStructureOwner.moveShortcutHostedSplitGroup(group, in: space.id, to: 0))

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.splitGroup(group.id), .shortcut(firstPin.id), .shortcut(lastPin.id)]
        )

        let movedGroup = try XCTUnwrap(harness.tabManager.splitGroupCollectionStateOwner.group(with: group.id))
        XCTAssertTrue(harness.tabManager.splitGroupStructureOwner.moveShortcutHostedSplitGroup(movedGroup, in: space.id, to: 3))

        XCTAssertEqual(
            harness.tabManager.splitGroupStructureOwner.topLevelSpacePinnedVisualItems(for: space.id),
            [.shortcut(firstPin.id), .shortcut(lastPin.id), .splitGroup(group.id)]
        )
        XCTAssertTrue(harness.tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).contains { $0.id == groupedPin.id })
    }

    func testMovingEssentialFromRegularHostedSplitIntoShortcutHostedSplitPreservesLauncherOrigin() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: liveEssential.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveEssential.id,
                    pinId: essentialPin.id,
                    origin: .essential(profileId: profileId, index: 0)
                ),
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(sourceGroup)

        let firstPinned = makeSpacePin(spaceId: space.id, index: 0, title: "PinnedA")
        let secondPinned = makeSpacePin(spaceId: space.id, index: 1, title: "PinnedB")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([firstPinned, secondPinned], for: space.id)
        let liveFirstPinned = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            firstPinned,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let liveSecondPinned = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            secondPinned,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveFirstPinned.id, liveSecondPinned.id],
            layoutKind: .vertical,
            activeTabId: liveFirstPinned.id,
            host: .shortcutPinned(spaceId: space.id, profileId: profileId, index: 0),
            members: [
                SplitGroupMember(
                    tabId: liveFirstPinned.id,
                    pinId: firstPinned.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 0)
                ),
                SplitGroupMember(
                    tabId: liveSecondPinned.id,
                    pinId: secondPinned.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 1)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(targetGroup)

        XCTAssertTrue(harness.browserManager.splitManager.dropTab(
            liveEssential,
            on: SplitDropTarget(tabId: liveFirstPinned.id, side: .right, targetRect: .zero),
            in: harness.windowState
        ))

        let updatedTarget = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: essentialPin.id))
        XCTAssertEqual(updatedTarget.id, targetGroup.id)
        let movedMember = try XCTUnwrap(updatedTarget.member(forPinId: essentialPin.id))
        XCTAssertEqual(movedMember.origin, .essential(profileId: profileId, index: 0))
        XCTAssertTrue(movedMember.isShortcutBacked)
        XCTAssertEqual(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: movedMember.tabId)?.id, targetGroup.id)
        XCTAssertNil(harness.tabManager.splitGroupCollectionStateOwner.group(with: sourceGroup.id))
    }

    func testMovingPinnedProxyBetweenSplitGroupsKeepsRemainingRegularSplitAndPinnedPlaceholder() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let movedPin = makeSpacePin(spaceId: space.id, index: 0, title: "Moved")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([movedPin], for: space.id)
        let liveMovedPin = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            movedPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let firstRegular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://first.example", in: space, activate: false)
        let secondRegular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://second.example", in: space, activate: false)
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveMovedPin.id, firstRegular.id, secondRegular.id],
            layoutKind: .vertical,
            activeTabId: liveMovedPin.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveMovedPin.id,
                    pinId: movedPin.id,
                    origin: .spacePinned(spaceId: space.id, folderId: nil, index: 0)
                ),
                SplitGroupMember(
                    tabId: firstRegular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: firstRegular.index)
                ),
                SplitGroupMember(
                    tabId: secondRegular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: secondRegular.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(sourceGroup)

        let firstEssential = makeEssentialPin(profileId: profileId, index: 0, title: "EssentialA")
        let secondEssential = makeEssentialPin(profileId: profileId, index: 1, title: "EssentialB")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([firstEssential, secondEssential], for: profileId)
        let liveFirstEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            firstEssential,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let liveSecondEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            secondEssential,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveFirstEssential.id, liveSecondEssential.id],
            layoutKind: .vertical,
            activeTabId: liveFirstEssential.id,
            host: .shortcutPinned(spaceId: space.id, profileId: profileId, index: 0),
            members: [
                SplitGroupMember(
                    tabId: liveFirstEssential.id,
                    pinId: firstEssential.id,
                    origin: .essential(profileId: profileId, index: 0)
                ),
                SplitGroupMember(
                    tabId: liveSecondEssential.id,
                    pinId: secondEssential.id,
                    origin: .essential(profileId: profileId, index: 1)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(targetGroup)

        let pinnedProxy = harness.tabManager.shortcutPresentationOwner.dragProxyTab(for: movedPin)
        XCTAssertTrue(harness.browserManager.splitManager.dropTab(
            pinnedProxy,
            on: SplitDropTarget(tabId: liveFirstEssential.id, side: .right, targetRect: .zero),
            in: harness.windowState
        ))

        let updatedTarget = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: movedPin.id))
        XCTAssertEqual(updatedTarget.id, targetGroup.id)
        let movedMember = try XCTUnwrap(updatedTarget.member(forPinId: movedPin.id))
        XCTAssertEqual(movedMember.origin, .spacePinned(spaceId: space.id, folderId: nil, index: 0))
        XCTAssertTrue(movedMember.isShortcutBacked)

        let remainingSource = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: firstRegular.id))
        XCTAssertEqual(remainingSource.id, sourceGroup.id)
        XCTAssertEqual(remainingSource.tabIds, [firstRegular.id, secondRegular.id])
        XCTAssertNil(remainingSource.member(forPinId: movedPin.id))
        XCTAssertEqual(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: movedPin.id)?.id, targetGroup.id)
    }

    func testUpsertRepairsShortcutBackedMemberForLiveEssentialSegment() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        let malformedGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: liveEssential.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveEssential.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: liveEssential.index)
                ),
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(malformedGroup)

        let repaired = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: essentialPin.id))
        let member = try XCTUnwrap(repaired.member(forPinId: essentialPin.id))
        XCTAssertEqual(member.tabId, liveEssential.id)
        XCTAssertEqual(member.origin, .essential(profileId: profileId, index: 0))
        XCTAssertTrue(member.isShortcutBacked)
    }

    func testUpsertRepairsShortcutMembersAcrossPinnedEssentialMixedGroup() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let spacePin = makeSpacePin(spaceId: space.id, index: 1, title: "Pinned")
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([spacePin], for: space.id)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let livePinned = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            spacePin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        let malformedGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [livePinned.id, liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: livePinned.id,
            host: .shortcutPinned(spaceId: space.id, profileId: profileId, index: 1),
            members: [
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(malformedGroup)

        let repaired = try XCTUnwrap(harness.tabManager.splitGroupCollectionStateOwner.group(with: malformedGroup.id))
        XCTAssertEqual(
            repaired.member(forPinId: essentialPin.id)?.origin,
            .essential(profileId: profileId, index: 0)
        )
        XCTAssertEqual(
            repaired.member(forPinId: spacePin.id)?.origin,
            .spacePinned(spaceId: space.id, folderId: nil, index: 1)
        )
        XCTAssertEqual(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: essentialPin.id)?.id, malformedGroup.id)
        XCTAssertEqual(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: spacePin.id)?.id, malformedGroup.id)
    }

    func testUpsertDoesNotRepairSpacePinnedSplitMemberFromGlobalCurrentSpace() throws {
        let harness = try makeHarness()
        let storageSpace = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Storage")
        let globalCurrentSpace = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Global Current")
        harness.tabManager.spaceStateOwner.replaceCurrentSpace(globalCurrentSpace)
        let malformedPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://malformed.example")!,
            title: "Malformed"
        )
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([malformedPin], for: storageSpace.id)
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: storageSpace,
            activate: false
        )
        let malformedGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [malformedPin.id, regular.id],
            layoutKind: .vertical,
            members: [
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: storageSpace.id, index: regular.index)
                ),
            ]
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(malformedGroup)

        let repaired = try XCTUnwrap(harness.tabManager.splitGroupCollectionStateOwner.group(with: malformedGroup.id))
        XCTAssertNil(repaired.member(forPinId: malformedPin.id))
        XCTAssertFalse(
            repaired.members.contains {
                $0.origin == .spacePinned(spaceId: globalCurrentSpace.id, folderId: nil, index: 0)
            }
        )
    }

    func testUpsertRepairsSpacePinnedSplitMemberFromHostSpaceWhenPinSpaceIsMissing() throws {
        let harness = try makeHarness()
        let hostSpace = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Host")
        let globalCurrentSpace = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Global Current")
        harness.tabManager.spaceStateOwner.replaceCurrentSpace(globalCurrentSpace)
        let malformedPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://malformed.example")!,
            title: "Malformed"
        )
        harness.tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([malformedPin], for: hostSpace.id)
        let companionId = UUID()
        let malformedGroup = try XCTUnwrap(SplitGroup.make(
            tabIds: [malformedPin.id, companionId],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: hostSpace.id, profileId: nil, index: 0)
        ))

        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(malformedGroup)

        let repaired = try XCTUnwrap(harness.tabManager.splitGroupCollectionStateOwner.group(with: malformedGroup.id))
        XCTAssertEqual(
            repaired.member(forPinId: malformedPin.id)?.origin,
            .spacePinned(spaceId: hostSpace.id, folderId: nil, index: 0)
        )
    }

    func testRestoreShortcutSplitMemberKeepsLiveInstanceLoaded() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        harness.browserManager.selectTab(liveEssential, in: harness.windowState)

        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: liveEssential.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveEssential.id,
                    pinId: essentialPin.id,
                    origin: .essential(profileId: profileId, index: 0)
                ),
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        harness.browserManager.sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
            liveEssential.id,
            from: group,
            in: harness.windowState
        )

        XCTAssertNil(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: essentialPin.id))
        XCTAssertEqual(
            harness.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: essentialPin.id, in: harness.windowState.id)?.id,
            liveEssential.id
        )
        XCTAssertEqual(harness.tabManager.tabCollectionMembershipOwner.tab(for: liveEssential.id)?.id, liveEssential.id)
        XCTAssertEqual(harness.windowState.currentTabId, liveEssential.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, essentialPin.id)
        XCTAssertEqual(harness.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).map(\.id), [essentialPin.id])
    }

    func testRestoringInactiveShortcutSplitMemberDissolvesToRestoredTab() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        harness.browserManager.selectTab(regular, in: harness.windowState)

        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: regular.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveEssential.id,
                    pinId: essentialPin.id,
                    origin: .essential(profileId: profileId, index: 0)
                ),
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        harness.browserManager.sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
            liveEssential.id,
            from: group,
            in: harness.windowState
        )

        XCTAssertNil(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: regular.id))
        XCTAssertEqual(harness.windowState.currentTabId, liveEssential.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, essentialPin.id)
    }

    func testUnsplitActiveGroupKeepsFocusedTabSelected() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        harness.windowState.currentSpaceId = space.id

        let first = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://one.example", in: space, activate: false)
        let second = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://two.example", in: space, activate: false)
        harness.browserManager.selectTab(second, in: harness.windowState)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [first.id, second.id],
            layoutKind: .vertical,
            activeTabId: second.id,
            host: .regular(spaceId: space.id)
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        harness.browserManager.splitManager.unsplitActiveGroup(for: harness.windowState.id)

        XCTAssertNil(harness.tabManager.splitGroupCollectionStateOwner.group(with: group.id))
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
    }

    func testClosingShortcutSplitMemberStillUnloadsLiveInstance() throws {
        let harness = try makeHarness()
        let profileId = UUID()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work", profileId: profileId)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId

        let essentialPin = makeEssentialPin(profileId: profileId, index: 0, title: "Essential")
        harness.tabManager.structuralCollectionMutationOwner.setPinnedTabs([essentialPin], for: profileId)
        let liveEssential = harness.tabManager.shortcutLiveTabOwner.activateShortcutPin(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: space.id
        )
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://regular.example", in: space, activate: false)
        harness.browserManager.selectTab(liveEssential, in: harness.windowState)

        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [liveEssential.id, regular.id],
            layoutKind: .vertical,
            activeTabId: liveEssential.id,
            host: .regular(spaceId: space.id),
            members: [
                SplitGroupMember(
                    tabId: liveEssential.id,
                    pinId: essentialPin.id,
                    origin: .essential(profileId: profileId, index: 0)
                ),
                SplitGroupMember(
                    tabId: regular.id,
                    pinId: nil,
                    origin: .regular(spaceId: space.id, index: regular.index)
                ),
            ]
        ))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        harness.browserManager.sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
            liveEssential.id,
            from: group,
            in: harness.windowState,
            preserveLiveInstance: false
        )

        XCTAssertNil(harness.tabManager.splitGroupStructureOwner.splitGroup(containingPinId: essentialPin.id))
        XCTAssertNil(harness.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: essentialPin.id, in: harness.windowState.id))
        XCTAssertNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: liveEssential.id))
        XCTAssertEqual(harness.windowState.currentTabId, regular.id)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertEqual(harness.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).map(\.id), [essentialPin.id])
    }

    func testSanitizedDropsInvalidDuplicateAndOverlappingGroups() throws {
        let ids = makeIDs(5)
        let first = try XCTUnwrap(SplitGroup.make(tabIds: [ids[0], ids[1]], layoutKind: .vertical))
        let overlapping = try XCTUnwrap(SplitGroup.make(tabIds: [ids[1], ids[2]], layoutKind: .horizontal))
        let validSecond = try XCTUnwrap(SplitGroup.make(tabIds: [ids[3], ids[4]], layoutKind: .grid))

        let sanitized = SplitGroup.sanitized([first, first, overlapping, validSecond])

        XCTAssertEqual(sanitized.map(\.id), [first.id, validSecond.id])
    }

    func testSanitizedRejectedOverlapDoesNotReserveUnrelatedTabs() throws {
        let ids = makeIDs(4)
        let first = try XCTUnwrap(SplitGroup.make(tabIds: [ids[0], ids[1]], layoutKind: .vertical))
        let rejectedOverlap = try XCTUnwrap(SplitGroup.make(tabIds: [ids[2], ids[1]], layoutKind: .horizontal))
        let validSecond = try XCTUnwrap(SplitGroup.make(tabIds: [ids[2], ids[3]], layoutKind: .grid))

        let sanitized = SplitGroup.sanitized([first, rejectedOverlap, validSecond])

        XCTAssertEqual(sanitized.map(\.id), [first.id, validSecond.id])
    }

    func testVisibleTabPreparationPlanReturnsAllSplitTabs() {
        let current = UUID()
        let secondary = UUID()

        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: current,
                splitTabIds: [current, secondary, current, secondary]
            ),
            [current, secondary]
        )
        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: current,
                splitTabIds: [current, secondary]
            ),
            [current, secondary]
        )
        XCTAssertEqual(
            VisibleTabPreparationPlan.visibleTabIDs(
                currentTabId: current,
                splitTabIds: [secondary]
            ),
            [current]
        )
    }

    func testSelectingNativeSurfaceAwayFromSplitDoesNotDeleteGroup() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let left = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space)
        let right = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let native = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: SumiSurface.emptyTabURL.absoluteString, in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = left.id

        let group = try XCTUnwrap(SplitGroup.make(tabIds: [left.id, right.id], layoutKind: .vertical, activeTabId: right.id))
        harness.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)

        harness.browserManager.selectTab(native, in: harness.windowState)

        XCTAssertNotNil(harness.tabManager.splitGroupCollectionStateOwner.group(with: group.id))
        XCTAssertNil(harness.browserManager.splitManager.splitGroup(for: harness.windowState.id))

        harness.browserManager.selectTab(right, in: harness.windowState)

        let restoredVisibleGroup = try XCTUnwrap(harness.browserManager.splitManager.splitGroup(for: harness.windowState.id))
        XCTAssertEqual(restoredVisibleGroup.id, group.id)
        XCTAssertEqual(restoredVisibleGroup.layoutTree, group.layoutTree)
    }

    func testSnapshotDecodesMissingSplitGroupsAsEmpty() throws {
        struct LegacySnapshot: Codable {
            let spaces: [TabSnapshotRepository.SnapshotSpace]
            let tabs: [TabSnapshotRepository.SnapshotTab]
            let folders: [TabSnapshotRepository.SnapshotFolder]
            let state: TabSnapshotRepository.SnapshotState
        }

        let data = try JSONEncoder().encode(
            LegacySnapshot(
                spaces: [],
                tabs: [],
                folders: [],
                state: TabSnapshotRepository.SnapshotState(currentTabID: nil, currentSpaceID: nil)
            )
        )

        let decoded = try JSONDecoder().decode(TabSnapshotRepository.Snapshot.self, from: data)

        XCTAssertTrue(decoded.splitGroups.isEmpty)
    }

    func testLegacyDuplicateAsRegularHelperCreatesRegularCopy() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let regular = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://anchor.example", in: space)
        let pinned = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://pinned.example", in: space, activate: false)
        pinned.isPinned = true

        let duplicate = harness.tabManager.regularTabLifecycleOwner.duplicateAsRegularForSplit(from: pinned, anchor: regular)

        XCTAssertNotEqual(duplicate.id, pinned.id)
        XCTAssertEqual(duplicate.url, pinned.url)
        XCTAssertFalse(duplicate.isPinned)
        XCTAssertFalse(duplicate.isSpacePinned)
        XCTAssertTrue(pinned.isPinned)
    }

    func testEmptySplitCancelRemovesPlaceholderPane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let current = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://current.example", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = current.id

        harness.browserManager.splitManager.createEmptySplit(in: harness.windowState)
        let group = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: current.id))
        let placeholderId = try XCTUnwrap(group.tabIds.first { $0 != current.id })

        harness.browserManager.floatingBarRoutingOwner.dismissFloatingBar(
            in: harness.windowState,
            preserveDraft: true,
            cancelEmptySplitPlaceholder: true
        )

        XCTAssertNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholderId))
        XCTAssertNil(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: current.id))
    }

    func testSplitViewManagerCreatesEmptySplitThroughRuntimePort() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let tabManager = TabManager(
            context: container.mainContext,
            loadPersistedState: false
        )
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let space = tabManager.spaceLifecycleOwner.createSpace(name: "Runtime")
        let current = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://current.example", in: space)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = current.id

        var selectedTabIds: [UUID] = []
        var refreshCount = 0
        var persistCount = 0
        var focusedReasons: [FloatingBarPresentationReason] = []
        let splitManager = SplitViewManager(
            runtime: SplitViewRuntime(
                tabManager: { tabManager },
                currentTab: { windowState in
                    windowState.currentTabId.flatMap { tabManager.tabCollectionMembershipOwner.tab(for: $0) }
                },
                selectTab: { tab, windowState in
                    selectedTabIds.append(tab.id)
                    windowState.currentTabId = tab.id
                },
                refreshCompositor: { _ in refreshCount += 1 },
                schedulePersistWindowSession: { _ in persistCount += 1 },
                focusFloatingBar: { _, reason in focusedReasons.append(reason) }
            )
        )
        splitManager.windowRegistry = windowRegistry

        splitManager.createEmptySplit(in: windowState)

        let group = try XCTUnwrap(tabManager.splitGroupStructureOwner.splitGroup(containing: current.id))
        let placeholderId = try XCTUnwrap(group.tabIds.first { $0 != current.id })
        XCTAssertNotNil(tabManager.tabCollectionMembershipOwner.tab(for: placeholderId))
        XCTAssertEqual(selectedTabIds.last, placeholderId)
        XCTAssertGreaterThanOrEqual(refreshCount, 1)
        XCTAssertGreaterThanOrEqual(persistCount, 1)
        XCTAssertEqual(focusedReasons, [.keyboard])
    }

    func testEmptySplitExistingTabCommitReplacesPlaceholderPane() throws {
        let harness = try makeHarness()
        let space = harness.tabManager.spaceLifecycleOwner.createSpace(name: "Work")
        let current = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://current.example", in: space)
        let existing = harness.tabManager.regularTabLifecycleOwner.createNewTab(url: "https://existing.example", in: space, activate: false)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentTabId = current.id

        harness.browserManager.splitManager.createEmptySplit(in: harness.windowState)
        let placeholderGroup = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: current.id))
        let placeholderId = try XCTUnwrap(placeholderGroup.tabIds.first { $0 != current.id })

        harness.browserManager.floatingBarRoutingOwner.openFloatingBarSuggestion(
            SearchManager.SearchSuggestion(text: existing.name, type: .tab(existing)),
            in: harness.windowState
        )

        let group = try XCTUnwrap(harness.tabManager.splitGroupStructureOwner.splitGroup(containing: existing.id))
        XCTAssertEqual(group.tabIds, [current.id, existing.id])
        XCTAssertEqual(group.activeTabId, existing.id)
        XCTAssertNil(harness.tabManager.tabCollectionMembershipOwner.tab(for: placeholderId))
    }

}
