import AppKit
import Combine
import SumiDomain
import XCTest

@testable import Sumi

/// Drag previews, geometry scoping, payload identity resolution, drop-commit cleanup, and regular-tab drops into the shortcut sections.
@MainActor
final class SidebarDragCurrentContextTests: SidebarDragContextTestCase {
    func testGeometryModuleIsWindowScoped() {
        let injectedState = SidebarDragState()
        let otherState = SidebarDragState()
        let spaceId = UUID()
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)

        injectedState.geometry.report(
            .presentedSpaceList(
                PresentedSidebarLayout(
                    spaceID: spaceId,
                    sectionFrames: [
                        .spacePinned: .zero,
                        .spaceRegular: frame,
                    ],
                    topLevelPinnedItemTargets: [:],
                    folderDropTargets: [:],
                    folderChildDropTargets: [:],
                    pinnedListHitTarget: nil,
                    regularListHitTarget: SidebarRegularListHitMetrics(
                        frame: frame,
                        rowIdentities: []
                    )
                )
            ),
            generation: injectedState.geometry.activeGeometryGeneration
        )
        injectedState.geometry.flushDeferredGeometryForDragStart()

        XCTAssertEqual(injectedState.geometry.geometrySnapshot.sectionFramesBySpace[key], frame)
        XCTAssertNil(otherState.geometry.geometrySnapshot.sectionFramesBySpace[key])
    }

    func testFavoriteNativeDragPreviewUsesActualSourceTileSize() {
        let sourceSize = CGSize(width: 132, height: 56)
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: SumiDragItem(
                tabId: UUID(),
                title: "Favorite",
                urlString: "https://example.com"
            ),
            previewIcon: nil,
            sourceZone: .favorite,
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: CGPoint(x: 24, y: 20)
        )

        XCTAssertEqual(
            SumiNativeDragImageFactory().size(for: .favoriteTile, descriptor: descriptor),
            sourceSize
        )
    }

    func testFavoriteDragPreviewCentersTileOnCursorRegardlessOfGrabPoint() {
        let sourceSize = CGSize(width: 132, height: 56)
        let session = SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: UUID(),
                    title: "Favorite",
                    urlString: "https://example.com"
                ),
                sourceZone: .favorite,
                previewKind: .favoriteTile
            ),
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: CGPoint(x: 12, y: 8)
        )
        let center = CGPoint(
            x: sourceSize.width / 2,
            y: sourceSize.height / 2
        )

        XCTAssertEqual(session?.primaryAsset.anchorOffset, center)
        XCTAssertEqual(
            session?.previewModel.anchorOffset(in: sourceSize),
            center
        )
    }

    func testLauncherDragPreviewSessionRendersRowAndFavoriteAssets() {
        let session = SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: UUID(),
                    title: "Pinned",
                    urlString: "https://example.com"
                ),
                sourceZone: .favorite,
                previewKind: .favoriteTile
            ),
            sourceSize: CGSize(width: 132, height: 56),
            sourceOffsetFromBottomLeading: CGPoint(x: 18, y: 18)
        )

        let renderedKinds = session.map { Set($0.previewAssets.keys) } ?? Set<SidebarDragPreviewKind>()
        XCTAssertEqual(renderedKinds, [.favoriteTile, .row])
    }

    func testFolderDragPreviewSessionKeepsFolderOnlyAsset() {
        let session = SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem.folder(folderId: UUID(), title: "Folder"),
                sourceZone: .spacePinned(UUID()),
                previewKind: .folderRow
            ),
            sourceSize: CGSize(width: 220, height: 36),
            sourceOffsetFromBottomLeading: CGPoint(x: 18, y: 18)
        )

        let renderedKinds = session.map { Set($0.previewAssets.keys) } ?? Set<SidebarDragPreviewKind>()
        XCTAssertEqual(renderedKinds, [.folderRow])
    }

    func testSplitSegmentDragAnchorUsesWholeRowCoordinates() {
        let geometry = SidebarDragPreviewSourceGeometry(
            size: CGSize(width: 281, height: 36),
            localOrigin: CGPoint(x: 141, y: 0)
        )
        let anchor = geometry.anchor(
            forLocalPoint: CGPoint(x: 18, y: 20)
        )

        let session = SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: .splitGroup(
                    UUID(),
                    title: "Split",
                    urlString: "https://example.com"
                ),
                sourceZone: .spacePinned(UUID()),
                previewKind: .row
            ),
            sourceSize: geometry.size,
            sourceOffsetFromBottomLeading: anchor
        )

        XCTAssertEqual(anchor, CGPoint(x: 159, y: 20))
        XCTAssertEqual(
            session?.previewModel.anchorOffset(in: geometry.size),
            CGPoint(x: 159, y: 16)
        )
    }

    func testStandaloneShortcutPayloadResolvesByTypedPinIdentity() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/typed-pin",
            index: 0
        )
        let item = SumiDragItem.shortcutPin(
            pin.id,
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )

        guard case .pin(let resolvedPin)? = tabManager.sidebarDragRouter
            .resolveSidebarDragPayload(for: item) else {
            return XCTFail("Expected a typed shortcut payload")
        }
        XCTAssertEqual(resolvedPin.id, pin.id)
        XCTAssertEqual(
            tabManager.sidebarDragRouter.resolveDragTab(for: item)?
                .shortcutPinId,
            pin.id
        )
    }

    func testStaleSplitMemberPayloadDoesNotFallBackToRawUUID() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(
            tabManager,
            name: "Work",
            profileId: profileID
        )
        let pin = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://example.com/stale-split-member",
            index: 0
        )
        let item = SumiDragItem.splitMember(
            .shortcutPin(pin.id),
            groupID: UUID(),
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )

        XCTAssertNil(
            tabManager.sidebarDragRouter.resolveSidebarDragPayload(for: item)
        )
        XCTAssertNil(tabManager.sidebarDragRouter.resolveDragTab(for: item))
    }

    func testLauncherPreviewPolicyTransformsRowIntoFavoriteTileOnFavoriteHover() {
        let assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [
            .row: emptyPreviewAsset(size: CGSize(width: 220, height: 36)),
            .favoriteTile: emptyPreviewAsset(size: CGSize(width: 132, height: 56)),
        ]

        XCTAssertEqual(
            SidebarDragPresentationProjection.resolvedPreviewKind(
                baseKind: .row,
                hoveredSlot: .favorite(slot: 0),
                previewAssets: assets
            ),
            .favoriteTile
        )
    }

    func testLauncherPreviewPolicyTransformsFavoriteTileIntoRowOnPinnedHover() {
        let spaceId = UUID()
        let assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [
            .row: emptyPreviewAsset(size: CGSize(width: 220, height: 36)),
            .favoriteTile: emptyPreviewAsset(size: CGSize(width: 132, height: 56)),
        ]

        XCTAssertEqual(
            SidebarDragPresentationProjection.resolvedPreviewKind(
                baseKind: .favoriteTile,
                hoveredSlot: .spacePinned(spaceId: spaceId, slot: 0),
                previewAssets: assets
            ),
            .row
        )
    }

    func testFavoriteSplitGroupPreviewCentersUnderPointerForTileAndRow()
        throws {
        let sourceSize = CGSize(width: 90, height: 64)
        let rowSize = CGSize(width: 240, height: SidebarRowLayout.rowHeight)
        let session = try XCTUnwrap(SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: .splitGroup(UUID(), title: "Split View"),
                sourceZone: .favorite,
                previewKind: .favoriteTile
            ),
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: CGPoint(x: 12, y: 11)
        ))

        XCTAssertEqual(
            session.previewModel.anchorOffset(in: rowSize),
            CGPoint(x: rowSize.width / 2, y: rowSize.height / 2)
        )
        XCTAssertEqual(
            session.previewModel.anchorOffset(in: sourceSize),
            CGPoint(x: sourceSize.width / 2, y: sourceSize.height / 2)
        )
    }

    func testRegularToLauncherDropCommitSuppressesStaleProjectionPlaceholder() throws {
        let state = SidebarDragState()
        let spaceId = UUID()
        let profileId = UUID()
        let draggedItemId = UUID()
        state.isDragging = true
        state.activeDragItemId = draggedItemId
        state.activeDragScope = try makeScope(
            spaceId: spaceId,
            profileId: profileId,
            sourceZone: .spaceRegular(spaceId),
            item: SumiDragItem(
                tabId: draggedItemId,
                title: "Regular",
                urlString: "https://example.com"
            )
        )
        present(.spacePinned(spaceId: spaceId, slot: 0), in: state)

        state.beginDropCommit()

        XCTAssertTrue(
            state.shouldHideCommittedCrossContainerPlaceholder(
                into: .spacePinned(spaceId),
                targetAlreadyContainsDraggedItem: false
            )
        )
        XCTAssertTrue(
            state.shouldHideCommittedCrossContainerPlaceholder(
                into: .favorite,
                targetAlreadyContainsDraggedItem: false
            )
        )
        XCTAssertFalse(
            state.shouldHideCommittedCrossContainerPlaceholder(
                into: .spaceRegular(spaceId),
                targetAlreadyContainsDraggedItem: false
            )
        )
    }

    func testDelayedDropCommitCleanupFinishesWithoutNewDrop() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let state = SidebarDragState(delayedActions: delayedActions.scheduler)
        let spaceId = UUID()
        let draggedItemId = UUID()
        state.isDragging = true
        state.activeDragItemId = draggedItemId
        present(.spacePinned(spaceId: spaceId, slot: 0), in: state)

        state.beginDropCommit()
        state.resetInteractionState()

        XCTAssertTrue(state.isCompletingDrop)
        XCTAssertTrue(state.isDropProjectionActive)
        XCTAssertEqual(state.projectionDragItemId, draggedItemId)
        XCTAssertEqual(
            delayedActions.scheduledDelays,
            [SidebarMotionPolicy.dropSettleDuration],
            "Drop-completion state must outlive the settle animation it gates"
        )

        delayedActions.runNext()

        XCTAssertFalse(state.isCompletingDrop)
        XCTAssertFalse(state.isDropProjectionActive)
        XCTAssertNil(state.projectionDragItemId)
        XCTAssertEqual(state.projectionHoveredSlot, .empty)
    }

    func testSplitDropTargetRequiresOneCancellableDwell() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let gate = SidebarDropTargetDwellGate(
            delayedActions: delayedActions.scheduler
        )
        let spaceID = UUID()
        let target = SidebarDeferredDropTarget.split(
            memberID: .regularTab(UUID()),
            side: .right,
            residence: .spaceRegular(spaceId: spaceID, slot: 1)
        )

        XCTAssertFalse(gate.admits(target))
        XCTAssertFalse(gate.admits(target))
        XCTAssertEqual(
            delayedActions.scheduledDelays,
            [SidebarDropTargetDwellGate.duration]
        )
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        delayedActions.runNext()

        XCTAssertTrue(gate.admits(target))
        XCTAssertEqual(gate.revision, 1)

        gate.leaveDeferredTargets()
        XCTAssertFalse(gate.admits(target))
        XCTAssertEqual(delayedActions.pendingActionCount, 1)
    }

    func testMovingBetweenDeferredTargetsCancelsPreviousDwell() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let gate = SidebarDropTargetDwellGate(
            delayedActions: delayedActions.scheduler
        )
        let spaceID = UUID()
        let first = SidebarDeferredDropTarget.split(
            memberID: .regularTab(UUID()),
            side: .left,
            residence: .spaceRegular(spaceId: spaceID, slot: 1)
        )
        let second = SidebarDeferredDropTarget.split(
            memberID: .regularTab(UUID()),
            side: .right,
            residence: .spaceRegular(spaceId: spaceID, slot: 2)
        )

        XCTAssertFalse(gate.admits(first))
        XCTAssertFalse(gate.admits(second))
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        delayedActions.runAll()

        XCTAssertFalse(gate.admits(first))
        XCTAssertEqual(gate.revision, 1)
    }

    func testStaleDelayedDropCommitCleanupDoesNotClearNewDropProjection() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let state = SidebarDragState(delayedActions: delayedActions.scheduler)
        let spaceId = UUID()
        let firstDraggedItemId = UUID()
        let secondDraggedItemId = UUID()
        state.isDragging = true
        state.activeDragItemId = firstDraggedItemId
        present(.spacePinned(spaceId: spaceId, slot: 0), in: state)
        state.beginDropCommit()
        state.resetInteractionState()

        state.isDragging = true
        state.activeDragItemId = secondDraggedItemId
        present(.spacePinned(spaceId: spaceId, slot: 1), in: state)
        state.beginDropCommit()

        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertTrue(state.isCompletingDrop)
        XCTAssertTrue(state.isDropProjectionActive)
        XCTAssertEqual(state.projectionDragItemId, secondDraggedItemId)
    }

    func testDropCommitCleanupIsCancelledWhenDragStateIsReleased() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        var state: SidebarDragState? = SidebarDragState(delayedActions: delayedActions.scheduler)
        let spaceID = UUID()
        state?.isDragging = true
        state?.activeDragItemId = UUID()
        if let state {
            present(.spacePinned(spaceId: spaceID, slot: 0), in: state)
        }
        state?.beginDropCommit()
        state?.resetInteractionState()

        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        state = nil

        XCTAssertEqual(delayedActions.pendingActionCount, 0)
    }

    func testRegularTabReorderStaysInsideCurrentSpace() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/two", in: space, activate: false)
        let third = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/three", in: space, activate: false)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(first)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(first),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 3
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertEqual(tabManager.regularTabCollectionOwner.tabs(in: space.id).map(\.id), [second.id, third.id, first.id])
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
    }

    func testRegularTabDropIntoSpacePinnedCreatesLauncherAndRemovesRegularEntry() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/pin", in: space)
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
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first)
        XCTAssertEqual(pin.role, .spacePinned)
        XCTAssertEqual(pin.spaceId, space.id)
        XCTAssertNil(pin.folderId)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testRegularTabDropIntoFolderCreatesFolderLauncher() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/folder", in: space)
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
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        XCTAssertEqual(pin.role, .spacePinned)
        XCTAssertEqual(pin.spaceId, space.id)
        XCTAssertEqual(pin.folderId, folder.id)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testRegularTabDropIntoClosedFolderKeepsFolderClosed() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/closed-folder", in: space)
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab)
        )

        XCTAssertFalse(folder.isOpen)

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertFalse(folder.isOpen)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        XCTAssertEqual(pin.folderId, folder.id)
    }

    func testRegularSplitDropIntoClosedFolderKeepsFolderClosed() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let members = (0..<2).map { index in
            tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://example.com/closed-folder-split-\(index)",
                in: space,
                activate: false
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: members.map { .regularTab($0.id) },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: .splitGroup(group.id, title: "Split")
        )

        XCTAssertFalse(folder.isOpen)

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.splitGroup(group.id)]
        )
    }

    func testLauncherSplitDropIntoClosedFolderKeepsFolderClosed() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let members = try (0..<2).map { index in
            try makeSpacePinnedPin(
                tabManager,
                in: space,
                url: "https://example.com/closed-folder-launcher-split-\(index)",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: members.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileId,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spacePinned(space.id),
            item: .splitGroup(group.id, title: "Split")
        )

        XCTAssertFalse(folder.isOpen)

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .splitGroup(group),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [.splitGroup(group.id)]
        )
    }

    func testLauncherSplitDropBesideExistingFolderSplitUsesVisualBoundary() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let folderPins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://existing-folder-split-\(index).example",
                index: index
            )
        }
        let existingGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(folderPins[1].id),
                .shortcutPin(folderPins[2].id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(existingGroup, persist: false))

        let movingPins = try (0..<2).map { index in
            try makeSpacePinnedPin(
                tabManager,
                in: space,
                url: "https://moving-folder-split-\(index).example",
                index: index
            )
        }
        let movingGroup = try XCTUnwrap(SplitGroup.make(
            members: movingPins.map { .shortcutPin($0.id) },
            layoutKind: .horizontal,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(movingGroup, persist: false))
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spacePinned(space.id),
            item: .splitGroup(movingGroup.id, title: "Moving split")
        )

        XCTAssertFalse(folder.isOpen)
        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .splitGroup(movingGroup),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 2
            )
        ))

        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [
                .shortcut(folderPins[0].id),
                .splitGroup(existingGroup.id),
                .splitGroup(movingGroup.id),
                .shortcut(folderPins[3].id),
            ]
        )
    }

    func testRegularSplitDropBesideExistingFolderSplitUsesVisualBoundary() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let folderPins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://regular-target-split-\(index).example",
                index: index
            )
        }
        let existingGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(folderPins[1].id),
                .shortcutPin(folderPins[2].id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(existingGroup, persist: false))

        let regularTabs = (0..<2).map { index in
            tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://regular-moving-split-\(index).example",
                in: space,
                activate: false
            )
        }
        let movingGroup = try XCTUnwrap(SplitGroup.make(
            members: regularTabs.map { .regularTab($0.id) },
            layoutKind: .horizontal,
            container: .regularTabs(spaceId: space.id)
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(movingGroup, persist: false))
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spaceRegular(space.id),
            item: .splitGroup(movingGroup.id, title: "Moving split")
        )

        XCTAssertFalse(folder.isOpen)
        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .splitGroup(movingGroup),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 2
            )
        ))

        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [
                .shortcut(folderPins[0].id),
                .splitGroup(existingGroup.id),
                .splitGroup(movingGroup.id),
                .shortcut(folderPins[3].id),
            ]
        )
    }

    func testShortcutDropBesideFolderSplitUsesVisualBoundary() throws {
        let tabManager = BrowserManager()
        let profileID = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileID)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let folderPins = try (0..<4).map { index in
            try makeFolderPin(
                tabManager,
                in: space,
                folderId: folder.id,
                url: "https://shortcut-target-split-\(index).example",
                index: index
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(folderPins[1].id),
                .shortcutPin(folderPins[2].id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: profileID,
                folderId: folder.id,
                index: 1
            )
        ))
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group, persist: false))
        let moving = try makeSpacePinnedPin(
            tabManager,
            in: space,
            url: "https://moving-shortcut.example",
            index: 0
        )
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileID,
            sourceZone: .spacePinned(space.id),
            item: dragItem(moving)
        )

        XCTAssertFalse(folder.isOpen)
        XCTAssertTrue(tabManager.sidebarDragRouter.performSidebarDragCommit(
            SidebarDragCommitIntent(
                payload: .pin(moving),
                scope: scope,
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                presentedVisualIndex: 2
            )
        ))

        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(
            tabManager.splitGroupSidebarOrdering.resolver(for: space.id)
                .folderItems(for: folder.id),
            [
                .shortcut(folderPins[0].id),
                .splitGroup(group.id),
                .shortcut(moving.id),
                .shortcut(folderPins[3].id),
            ]
        )
    }

    func testRegularTabDropIntoFavoriteCreatesProfileLauncher() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/favorite", in: space)
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
                fromContainer: .spaceRegular(space.id),
                toContainer: .favorite,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.favoritePins(for: profileId).first)
        XCTAssertEqual(pin.role, .favorite)
        XCTAssertEqual(pin.profileId, profileId)
        XCTAssertNil(pin.spaceId)
        XCTAssertNil(pin.folderId)
        XCTAssertEqual(pin.launchURL, tab.url)
    }

    func testSplitRetirementUsesCurrentRuntimeAttachmentGeneration() {
        let window = BrowserWindowState()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        var retiredByInitialRuntime: [UUID] = []
        var retiredByReplacementRuntime: [UUID] = []
        let connection = TabRuntimePortConnection(
            TestRuntimePorts.make(
                windows: { [(window.id, window)] },
                handleTabClosure: { retiredByInitialRuntime.append($0) },
                visibleSplitTabIds: { _ in [tab.id] }
            )
        )
        let transaction = SidebarDraggedTabSplitRetirementTransaction(
            runtimeConnection: connection
        )
        connection.attach(
            TestRuntimePorts.make(
                windows: { [(window.id, window)] },
                handleTabClosure: { retiredByReplacementRuntime.append($0) },
                visibleSplitTabIds: { _ in [tab.id] }
            )
        )

        transaction.dissolveActiveSplitIfNeeded(for: tab)

        XCTAssertTrue(retiredByInitialRuntime.isEmpty)
        XCTAssertEqual(retiredByReplacementRuntime, [tab.id])
    }

    func testDisplayedRegularTabDropIntoSpacePinnedPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-pin", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab),
            windowState: harness.windowState
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

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertIdentical(liveTab, tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertEqual(liveTab.spaceId, space.id)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)
    }

    func testDisplayedRegularTabDropIntoFolderPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-folder", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab),
            windowState: harness.windowState
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertIdentical(liveTab, tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .spacePinned)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertEqual(liveTab.spaceId, space.id)
        XCTAssertEqual(liveTab.folderId, folder.id)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)
    }

    func testDisplayedRegularTabDropIntoFavoritePreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-favorite", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: .spaceRegular(space.id),
            item: dragItem(tab),
            windowState: harness.windowState
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: scope,
                fromContainer: .spaceRegular(space.id),
                toContainer: .favorite,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.favoritePins(for: profileId).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertIdentical(liveTab, tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .favorite)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .favorite)
    }

    func testNonDisplayedRegularTabDropIntoShortcutSectionsCreatesLauncherWithoutLiveTab() throws {
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .spacePinned)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .folder)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .favorite)
    }
}
