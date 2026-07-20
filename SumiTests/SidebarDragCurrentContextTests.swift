import AppKit
import Combine
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragCurrentContextTests: XCTestCase {
    func testDeferredGeometryWriterUsesInjectedDragState() {
        let injectedState = SidebarDragState()
        let otherState = SidebarDragState()
        let spaceId = UUID()
        let frame = CGRect(x: 10, y: 20, width: 30, height: 40)
        let key = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)

        SidebarDragStateDeferredGeometry.setSectionFrame(
            dragState: injectedState,
            spaceId: spaceId,
            section: .spaceRegular,
            generation: injectedState.activeGeometryGeneration,
            frame
        )
        injectedState.flushDeferredGeometryForDragStart()

        XCTAssertEqual(injectedState.geometrySnapshot.sectionFramesBySpace[key], frame)
        XCTAssertNil(otherState.geometrySnapshot.sectionFramesBySpace[key])
    }

    func testEssentialsNativeDragPreviewUsesActualSourceTileSize() {
        let sourceSize = CGSize(width: 132, height: 56)
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: SumiDragItem(
                tabId: UUID(),
                title: "Essential",
                urlString: "https://example.com"
            ),
            previewIcon: nil,
            sourceZone: .essentials,
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: CGPoint(x: 24, y: 20)
        )

        XCTAssertEqual(
            SumiNativeDragImageFactory().size(for: .essentialsTile, descriptor: descriptor),
            sourceSize
        )
    }

    func testLauncherDragPreviewSessionRendersRowAndEssentialsAssets() {
        let session = SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: SumiDragItem(
                    tabId: UUID(),
                    title: "Pinned",
                    urlString: "https://example.com"
                ),
                sourceZone: .essentials,
                previewKind: .essentialsTile
            ),
            sourceSize: CGSize(width: 132, height: 56),
            sourceOffsetFromBottomLeading: CGPoint(x: 18, y: 18)
        )

        let renderedKinds = session.map { Set($0.previewAssets.keys) } ?? Set<SidebarDragPreviewKind>()
        XCTAssertEqual(renderedKinds, [.essentialsTile, .row])
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
            session?.previewModel.anchorOffset(in: geometry.size).x,
            159
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

    func testLauncherPreviewPolicyTransformsRowIntoEssentialsTileOnEssentialsHover() {
        let assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [
            .row: emptyPreviewAsset(size: CGSize(width: 220, height: 36)),
            .essentialsTile: emptyPreviewAsset(size: CGSize(width: 132, height: 56)),
        ]

        XCTAssertEqual(
            SidebarDragPresentationProjection.resolvedPreviewKind(
                baseKind: .row,
                hoveredSlot: .essentials(slot: 0),
                previewAssets: assets
            ),
            .essentialsTile
        )
    }

    func testLauncherPreviewPolicyTransformsEssentialsTileIntoRowOnPinnedHover() {
        let spaceId = UUID()
        let assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [
            .row: emptyPreviewAsset(size: CGSize(width: 220, height: 36)),
            .essentialsTile: emptyPreviewAsset(size: CGSize(width: 132, height: 56)),
        ]

        XCTAssertEqual(
            SidebarDragPresentationProjection.resolvedPreviewKind(
                baseKind: .essentialsTile,
                hoveredSlot: .spacePinned(spaceId: spaceId, slot: 0),
                previewAssets: assets
            ),
            .row
        )
    }

    func testEssentialSplitGroupRowPreviewCentersUnderPointer() throws {
        let sourceSize = CGSize(width: 90, height: 64)
        let rowSize = CGSize(width: 240, height: SidebarRowLayout.rowHeight)
        let session = try XCTUnwrap(SidebarDragPreviewSessionFactory.make(
            configuration: SidebarDragSourceConfiguration(
                item: .splitGroup(UUID(), title: "Split View"),
                sourceZone: .essentials,
                previewKind: .essentialsTile
            ),
            sourceSize: sourceSize,
            sourceOffsetFromBottomLeading: CGPoint(x: 12, y: 11)
        ))

        XCTAssertEqual(
            SidebarDragPresentationProjection.anchorOffset(
                for: session.previewModel,
                previewKind: .row,
                in: rowSize
            ),
            CGPoint(x: rowSize.width / 2, y: rowSize.height / 2)
        )
        XCTAssertNotEqual(
            SidebarDragPresentationProjection.anchorOffset(
                for: session.previewModel,
                previewKind: .essentialsTile,
                in: sourceSize
            ),
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
                into: .essentials,
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
        XCTAssertEqual(delayedActions.scheduledDelays, [0.05])

        delayedActions.runNext()

        XCTAssertFalse(state.isCompletingDrop)
        XCTAssertFalse(state.isDropProjectionActive)
        XCTAssertNil(state.projectionDragItemId)
        XCTAssertEqual(state.projectionHoveredSlot, .empty)
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
        state?.isDragging = true
        state?.activeDragItemId = UUID()
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

    func testRegularTabDropIntoEssentialsCreatesProfileLauncher() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/essential", in: space)
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
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first)
        XCTAssertEqual(pin.role, .essential)
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

    func testDisplayedRegularTabDropIntoEssentialsPreservesTabAsLiveShortcut() throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/live-essential", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = tab.id
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
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        let pin = try XCTUnwrap(tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first)
        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertIdentical(liveTab, tab)
        XCTAssertEqual(liveTab.shortcutPinId, pin.id)
        XCTAssertEqual(liveTab.shortcutPinRole, .essential)
        XCTAssertTrue(liveTab.isShortcutLiveInstance)
        XCTAssertNil(liveTab.spaceId)
        XCTAssertNil(liveTab.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .essential)
    }

    func testNonDisplayedRegularTabDropIntoShortcutSectionsCreatesLauncherWithoutLiveTab() throws {
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .spacePinned)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .folder)
        try assertNonDisplayedRegularTabConversionCreatesLauncherOnly(target: .essentials)
    }

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

    func testSpacePinnedDropIntoRegularCreatesRegularTabAndRemovesLauncherOwnership() throws {
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
        XCTAssertTrue(tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).isEmpty)
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
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

    private func makeLiveWindowHarness() throws -> LiveWindowHarness {
        let container = try makeInMemoryStartupModelContainer()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        let windowRegistry = browserManager.windowRegistry
        let windowState = BrowserWindowState()
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        return LiveWindowHarness(
            browserManager: browserManager,
            tabManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState
        )
    }

    private func makeScope(
        spaceId: UUID,
        profileId: UUID,
        sourceZone: DropZoneID,
        item: SumiDragItem,
        windowState: BrowserWindowState? = nil
    ) throws -> SidebarDragScope {
        let windowState = windowState ?? BrowserWindowState()
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId
        return try XCTUnwrap(
            SidebarDragScope(
                windowState: windowState,
                sourceZone: sourceZone,
                item: item
            )
        )
    }

    private func dragItem(_ tab: Tab) -> SumiDragItem {
        SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
    }

    private func dragItem(_ pin: ShortcutPin) -> SumiDragItem {
        SumiDragItem.shortcutPin(
            pin.id,
            title: pin.title,
            urlString: pin.launchURL.absoluteString
        )
    }

    private func dragItem(_ folder: TabFolder) -> SumiDragItem {
        SumiDragItem.folder(folderId: folder.id, title: folder.name)
    }

    private func makeSpace(
        _ browser: BrowserManager,
        name: String,
        profileId: UUID? = nil
    ) throws -> Space {
        try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: "square",
                profileID: profileId
            )
        )
    }

    private func makeFolder(
        _ browser: BrowserManager,
        in spaceId: UUID,
        parentFolderId: UUID? = nil,
        name: String
    ) throws -> TabFolder {
        try XCTUnwrap(
            browser.sidebarFolderCommands.createFolder(
                in: spaceId,
                parentFolderID: parentFolderId,
                name: name
            )
        )
    }

    private func makeSpacePinnedPin(
        _ tabManager: BrowserManager,
        in space: Space,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: nil,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    private func makeFolderPin(
        _ tabManager: BrowserManager,
        in space: Space,
        folderId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: space.id,
                    folderId: folderId,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    private func makeEssentialPin(
        _ tabManager: BrowserManager,
        in space: Space,
        profileId: UUID,
        url: String,
        index: Int
    ) throws -> ShortcutPin {
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: url, in: space, activate: false)
        return try XCTUnwrap(
            tabManager.regularTabShortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .essential,
                    profileId: profileId,
                    spaceId: nil,
                    folderId: nil,
                    index: index,
                    opensFolder: false
                )
            )
        )
    }

    private func topLevelPinnedItemIDs(_ tabManager: BrowserManager, in spaceId: UUID) -> [UUID] {
        tabManager.spacePinnedStructureOwner.topLevelSpacePinnedItems(for: spaceId).map(\.id)
    }

    private func assertNonDisplayedRegularTabConversionCreatesLauncherOnly(
        target: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://example.com/non-displayed-\(target.pathComponent)", in: space)
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = nil
        let targetContainer = dragContainer(for: target, space: space, folder: folder)
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
                toContainer: targetContainer,
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertTrue(tabManager.regularTabCollectionOwner.tabs(in: space.id).isEmpty)
        XCTAssertNil(tabManager.tabCollectionMembershipOwner.tab(for: tab.id))
        let pin = try XCTUnwrap(shortcutPin(for: target, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertEqual(pin.launchURL, tab.url)
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
    }

    private func assertLiveLauncherDropIntoRegularReusesLiveTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: folder.id,
            profileId: profileId,
            url: "https://example.com/live-\(source.pathComponent)"
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: harness.windowState.id, currentSpaceId: space.id)!
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertNil(shortcutPin(for: source, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertIdentical(converted, liveTab)
        XCTAssertEqual(converted.id, liveTab.id)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertNil(converted.shortcutPinRole)
        XCTAssertFalse(converted.isShortcutLiveInstance)
        XCTAssertEqual(converted.spaceId, space.id)
        XCTAssertNil(converted.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertNil(harness.windowState.currentShortcutPinRole)
        XCTAssertEqual(harness.windowState.activeTabForSpace[space.id], liveTab.id)
    }

    private func assertLauncherWithoutLiveShortcutDropIntoRegularCreatesNewTab(
        source: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let folder = try makeFolder(tabManager, in: space.id, name: "Docs")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: folder.id,
            profileId: profileId,
            url: "https://example.com/no-live-\(source.pathComponent)"
        )
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: folder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: folder),
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        XCTAssertNil(shortcutPin(for: source, tabManager: tabManager, profileId: profileId, space: space, folder: folder))
        XCTAssertNil(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        let converted = try XCTUnwrap(tabManager.regularTabCollectionOwner.tabs(in: space.id).first)
        XCTAssertNotEqual(converted.id, pin.id)
        XCTAssertEqual(converted.url, pin.launchURL)
        XCTAssertNil(converted.shortcutPinId)
        XCTAssertFalse(converted.isShortcutLiveInstance)
        XCTAssertEqual(converted.spaceId, space.id)
        XCTAssertNil(converted.folderId)
    }

    private func assertLiveLauncherMovePreservesBinding(
        source: ShortcutSectionTarget,
        destination: ShortcutSectionTarget
    ) throws {
        let harness = try makeLiveWindowHarness()
        let tabManager = harness.tabManager
        let profileId = UUID()
        let space = try makeSpace(tabManager, name: "Work", profileId: profileId)
        let sourceFolder = try makeFolder(tabManager, in: space.id, name: "Source")
        let destinationFolder = try makeFolder(tabManager, in: space.id, name: "Destination")
        let pin = try makePin(
            source,
            tabManager: tabManager,
            space: space,
            folderId: sourceFolder.id,
            profileId: profileId,
            url: "https://example.com/move-\(source.pathComponent)-\(destination.pathComponent)"
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(pin, in: harness.windowState.id, currentSpaceId: space.id)!
        harness.windowState.currentSpaceId = space.id
        harness.windowState.currentProfileId = profileId
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role
        let scope = try makeScope(
            spaceId: space.id,
            profileId: profileId,
            sourceZone: source.dropZone(spaceId: space.id, folderId: sourceFolder.id),
            item: dragItem(pin)
        )

        let didMove = tabManager.sidebarDragRouter.performSidebarDragOperation(
            DragOperation(
                payload: .pin(pin),
                scope: scope,
                fromContainer: dragContainer(for: source, space: space, folder: sourceFolder),
                toContainer: dragContainer(for: destination, space: space, folder: destinationFolder),
                toIndex: 0
            )
        )

        XCTAssertTrue(didMove)
        let movedPin = try XCTUnwrap(shortcutPin(for: destination, tabManager: tabManager, profileId: profileId, space: space, folder: destinationFolder))
        XCTAssertEqual(movedPin.id, pin.id)
        let movedLiveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: movedPin.id, in: harness.windowState.id))
        XCTAssertIdentical(movedLiveTab, liveTab)
        XCTAssertEqual(movedLiveTab.shortcutPinId, movedPin.id)
        XCTAssertEqual(movedLiveTab.shortcutPinRole, movedPin.role)
        XCTAssertTrue(movedLiveTab.isShortcutLiveInstance)
        XCTAssertEqual(movedLiveTab.spaceId, movedPin.spaceId)
        XCTAssertEqual(movedLiveTab.folderId, movedPin.folderId)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, movedPin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, movedPin.role)
    }

    private func present(_ slot: DropZoneSlot, in state: SidebarDragState) {
        state.presentDropResolution(
            SidebarDropResolution(
                slot: slot,
                folderIntent: .none,
                activeHoveredFolderId: nil
            )
        )
    }

    private func makePin(
        _ target: ShortcutSectionTarget,
        tabManager: BrowserManager,
        space: Space,
        folderId: UUID,
        profileId: UUID,
        url: String
    ) throws -> ShortcutPin {
        switch target {
        case .spacePinned:
            return try makeSpacePinnedPin(tabManager, in: space, url: url, index: 0)
        case .folder:
            return try makeFolderPin(tabManager, in: space, folderId: folderId, url: url, index: 0)
        case .essentials:
            return try makeEssentialPin(tabManager, in: space, profileId: profileId, url: url, index: 0)
        }
    }

    private func emptyPreviewAsset(size: CGSize) -> SidebarDragPreviewAsset {
        SidebarDragPreviewAsset(
            image: NSImage(size: size),
            size: size,
            anchorOffset: CGPoint(x: size.width / 2, y: size.height / 2)
        )
    }

    private func dragContainer(
        for target: ShortcutSectionTarget,
        space: Space,
        folder: TabFolder
    ) -> TabDragManager.DragContainer {
        switch target {
        case .spacePinned:
            return .spacePinned(space.id)
        case .folder:
            return .folder(folder.id)
        case .essentials:
            return .essentials
        }
    }

    private func shortcutPin(
        for target: ShortcutSectionTarget,
        tabManager: BrowserManager,
        profileId: UUID,
        space: Space,
        folder: TabFolder
    ) -> ShortcutPin? {
        switch target {
        case .spacePinned:
            return tabManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: space.id).first { $0.folderId == nil }
        case .folder:
            return tabManager.shortcutPinCollectionStateOwner.folderPinnedPins(for: folder.id, in: space.id).first
        case .essentials:
            return tabManager.shortcutPinCollectionStateOwner.essentialPins(for: profileId).first
        }
    }
}

private enum ShortcutSectionTarget: Equatable {
    case spacePinned
    case folder
    case essentials

    var pathComponent: String {
        switch self {
        case .spacePinned:
            return "space-pinned"
        case .folder:
            return "folder"
        case .essentials:
            return "essentials"
        }
    }

    func dropZone(spaceId: UUID, folderId: UUID) -> DropZoneID {
        switch self {
        case .spacePinned:
            return .spacePinned(spaceId)
        case .folder:
            return .folder(folderId)
        case .essentials:
            return .essentials
        }
    }
}

private struct LiveWindowHarness {
    let browserManager: BrowserManager
    let tabManager: BrowserManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
}
