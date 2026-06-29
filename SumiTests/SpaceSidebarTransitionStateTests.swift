@testable import Sumi
import XCTest

@MainActor
final class SpaceSidebarTransitionStateTests: XCTestCase {
    func testSidebarSwipeCapturePrefersTabListForVerticalAndWheelScrolling() {
        XCTAssertTrue(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: false,
                scrollingDeltaX: 20,
                scrollingDeltaY: 0
            )
        )
        XCTAssertTrue(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 2,
                scrollingDeltaY: 12
            )
        )
        XCTAssertFalse(
            SidebarSwipeScrollForwardingPolicy.shouldPreferTabListScroll(
                hasPreciseScrollingDeltas: true,
                scrollingDeltaX: 12,
                scrollingDeltaY: 2
            )
        )
    }

    func testPassiveScrollIndicatorIsHiddenWhenContentFits() {
        XCTAssertNil(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 120,
                contentHeight: 120,
                contentOffset: 0
            )
        )
    }

    func testPassiveScrollIndicatorTracksScrollProgress() throws {
        let metrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 200,
                contentOffset: 50
            )
        )

        XCTAssertEqual(metrics.thumbHeight, 50, accuracy: 0.001)
        XCTAssertEqual(metrics.thumbOffsetY, 25, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorClampsElasticOffsets() throws {
        let topMetrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 500,
                contentOffset: -40
            )
        )
        let bottomMetrics = try XCTUnwrap(
            SidebarPassiveScrollIndicatorLayout.metrics(
                viewportHeight: 100,
                contentHeight: 500,
                contentOffset: 999
            )
        )

        XCTAssertEqual(topMetrics.thumbOffsetY, 0, accuracy: 0.001)
        XCTAssertEqual(bottomMetrics.thumbOffsetY, 72, accuracy: 0.001)
    }

    func testPassiveScrollIndicatorFrameUsesViewportCoordinates() {
        let metrics = SidebarPassiveScrollIndicatorMetrics(
            thumbOffsetY: 10,
            thumbHeight: 30
        )
        let viewport = CGRect(x: 0, y: 0, width: 120, height: 100)

        let flippedFrame = SidebarPassiveScrollIndicatorLayout.frame(
            for: metrics,
            in: viewport,
            isFlipped: true
        )
        let unflippedFrame = SidebarPassiveScrollIndicatorLayout.frame(
            for: metrics,
            in: viewport,
            isFlipped: false
        )

        XCTAssertEqual(flippedFrame, CGRect(x: 115, y: 10, width: 3, height: 30))
        XCTAssertEqual(unflippedFrame, CGRect(x: 115, y: 60, width: 3, height: 30))
    }

    func testNativeScrollBoundariesTrackVisibleRect() {
        let top = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentHeight: 300
        )
        let middle = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 100, width: 100, height: 100),
            contentHeight: 300
        )
        let bottom = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 200, width: 100, height: 100),
            contentHeight: 300
        )

        XCTAssertFalse(top.hasContentAbove)
        XCTAssertTrue(top.hasContentBelow)
        XCTAssertTrue(middle.hasContentAbove)
        XCTAssertTrue(middle.hasContentBelow)
        XCTAssertTrue(bottom.hasContentAbove)
        XCTAssertFalse(bottom.hasContentBelow)
    }

    func testNativeScrollBoundariesAreClearWhenContentFits() {
        let state = SidebarScrollBoundaryState(
            visibleRect: CGRect(x: 0, y: 0, width: 100, height: 100),
            contentHeight: 100
        )

        XCTAssertFalse(state.hasContentAbove)
        XCTAssertFalse(state.hasContentBelow)
    }

    func testSameSpaceClickIsNoOp() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(state.hasDestination)
    }

    func testClickDirectionMatchesSpaceOrder() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, 1)

        state.reset()

        XCTAssertTrue(
            state.beginClick(
                from: ids[2],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, -1)
    }

    func testClickTransitionCommitsOnlyOnce() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[1],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertNil(state.finishTransition(commit: true))
    }

    func testRenderPolicyKeepsCommittedInteractiveAndTransitionLayersSnapshot() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .committed),
            .interactive
        )
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.pageRenderMode(for: .transitionLayer),
            .transitionSnapshot
        )
    }

    func testRenderPolicyCompletionDelayMatchesAnimationDuration() {
        XCTAssertEqual(
            SpaceSidebarRenderPolicy.completionDelay,
            SpaceSidebarTransitionConfig.spaceSwitchAnimationDuration,
            accuracy: 0.0001
        )
    }

    func testRenderPolicyKeepsUnresolvedSwipeOnCommittedInteractivePage() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertFalse(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))

        state.updateSwipeGesture(
            progress: 0.2,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(SpaceSidebarRenderPolicy.shouldUseTransitionLayers(for: state))
    }

    func testSwipeTransitionBeginsOnlyAfterHorizontalDirectionLatches() {
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .began, direction: nil, progress: 0)
            )
        )
        XCTAssertFalse(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: nil, progress: 0.02)
            )
        )
        XCTAssertTrue(
            SpaceSidebarRenderPolicy.shouldBeginSwipeTransition(
                for: .init(phase: .changed, direction: 1, progress: 0.02)
            )
        )
    }

    func testChromePreviewPolicyAnimatesEssentialsOnlyForInteractiveCommittedPage() {
        XCTAssertTrue(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .interactive
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: false,
                pageRenderMode: .transitionSnapshot
            )
        )
        XCTAssertFalse(
            SpaceSidebarChromePreviewPolicy.shouldAnimateEssentialsLayout(
                isActiveWindow: true,
                isTransitioningProfile: true,
                pageRenderMode: .interactive
            )
        )
    }

    func testEssentialsPlacementUsesSharedPinnedGridForSameProfileTransition() {
        let profileId = UUID()

        XCTAssertTrue(
            SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: profileId,
                destinationProfileId: profileId
            )
        )
    }

    func testEssentialsPlacementKeepsEmbeddedPinnedGridForCrossProfileTransition() {
        XCTAssertFalse(
            SpaceSidebarEssentialsPlacementPolicy.usesSharedPinnedGrid(
                sourceProfileId: UUID(),
                destinationProfileId: UUID()
            )
        )
    }

    func testSnapshotBuilderKeepsSingleStationaryEssentialsForSameProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let essential = makeEssentialPin(profileId: profileId, title: "Pinned")

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.pinnedByProfile[profileId] = [essential]
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        XCTAssertNotNil(snapshot.stationaryEssentials)
        XCTAssertEqual(snapshot.stationaryEssentials?.items.map(\.id), [essential.id])
    }

    func testSnapshotBuilderEmbedsEssentialsForCrossProfileTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let sourceEssential = makeEssentialPin(profileId: sourceProfileId, title: "Source Pin")
        let destinationEssential = makeEssentialPin(profileId: destinationProfileId, title: "Destination Pin")

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.pinnedByProfile[sourceProfileId] = [sourceEssential]
        browserManager.tabManager.pinnedByProfile[destinationProfileId] = [destinationEssential]
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        XCTAssertNil(snapshot.stationaryEssentials)
        XCTAssertEqual(snapshot.source.essentials?.items.map(\.id), [sourceEssential.id])
        XCTAssertEqual(snapshot.destination.essentials?.items.map(\.id), [destinationEssential.id])
    }

    func testSnapshotBuilderMarksSelectedRegularTabWithoutObservedTabRows() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let first = Tab(
            url: URL(string: "https://example.com/first")!,
            name: "First",
            spaceId: source.id,
            index: 0,
            browserManager: browserManager
        )
        let second = Tab(
            url: URL(string: "https://example.com/second")!,
            name: "Second",
            spaceId: source.id,
            index: 1,
            browserManager: browserManager
        )

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.addTab(first)
        browserManager.tabManager.addTab(second)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = second.id

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        XCTAssertEqual(snapshot.source.regularTabs.map(\.id), [first.id, second.id])
        XCTAssertEqual(snapshot.source.regularTabs.map(\.isSelected), [false, true])
    }

    func testSnapshotBuilderPreservesRegularTabUnloadedIndicator() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let unloadedTab = Tab(
            url: URL(string: "https://example.com/unloaded")!,
            name: "Unloaded",
            spaceId: source.id,
            index: 0,
            browserManager: browserManager
        )

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.addTab(unloadedTab)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id
        windowState.currentTabId = unloadedTab.id

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        XCTAssertTrue(unloadedTab.showsWebViewUnloadedIndicator)
        XCTAssertEqual(snapshot.source.regularTabs.map(\.showsUnloadedIndicator), [true])
    }

    func testSnapshotFolderBodyKeepsLiveFolderLayoutMetrics() {
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentLeadingPadding, 14)
        XCTAssertEqual(SpaceSidebarSnapshotFolderLayout.contentVerticalPadding, 4)
        XCTAssertEqual(
            SpaceSidebarSnapshotFolderLayout.bodyHeight(childCount: 2),
            SidebarRowLayout.rowHeight * 2 + 8,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSnapshotFolderLayout.bodyHeight(childCount: 0),
            8,
            accuracy: 0.0001
        )
    }

    func testSnapshotTitleKeepsLiveSpaceTitleControlHeight() {
        XCTAssertEqual(SpaceSidebarSnapshotTitleLayout.trailingControlSize, 28)
        XCTAssertEqual(SpaceSidebarSnapshotTitleLayout.verticalPadding, 5)
        XCTAssertEqual(
            SpaceSidebarSnapshotTitleLayout.minimumHeight,
            38,
            accuracy: 0.0001
        )
    }

    func testPinnedTileFaviconCornerRadiusMatchesTransitionSnapshot() {
        XCTAssertEqual(PinnedTileFaviconLayout.cornerRadius, 6)
    }

    func testSnapshotPageThemeContextUsesPageWorkspaceThemeWithoutInteractiveProgress() {
        let settings = makeIsolatedSettings()
        let sourceTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#0A84FF",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destinationTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .monochrome
                    ),
                ],
                opacity: 1,
                texture: 0
            )
        )
        let destination = Space(name: "Destination", workspaceTheme: destinationTheme)
        var baseContext = ResolvedThemeContext.default
        baseContext.workspaceTheme = sourceTheme
        baseContext.sourceWorkspaceTheme = sourceTheme
        baseContext.targetWorkspaceTheme = destinationTheme
        baseContext.isInteractiveTransition = true
        baseContext.transitionProgress = 0.42

        let pageContext = SpaceSidebarSnapshotThemeResolver.pageThemeContext(
            for: destination,
            baseContext: baseContext,
            settings: settings,
            isIncognito: false
        )

        XCTAssertEqual(pageContext.workspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.sourceWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertEqual(pageContext.targetWorkspaceTheme.gradient.primaryColorHex, "#FF3B30")
        XCTAssertFalse(pageContext.isInteractiveTransition)
        XCTAssertEqual(pageContext.transitionProgress, 1.0, accuracy: 0.0001)
    }

    func testSnapshotBuilderKeepsClosedFolderProjectionRowsForLiveLaunchers() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let folder = TabFolder(name: "Folder", spaceId: source.id)
        let firstPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 0, title: "First")
        let secondPin = makeSpacePinnedPin(spaceId: source.id, folderId: folder.id, index: 1, title: "Second")

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.setFolders([folder], for: source.id)
        browserManager.tabManager.setSpacePinnedShortcuts([firstPin, secondPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        _ = browserManager.tabManager.activateShortcutPin(
            secondPin,
            in: windowState.id,
            currentSpaceId: source.id
        )

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        guard case .folder(let folderSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected first pinned item to be a folder snapshot")
        }

        XCTAssertFalse(folderSnapshot.isOpen)
        XCTAssertEqual(folderSnapshot.bodyChildren.map(\.id), [secondPin.id])
        XCTAssertTrue(folderSnapshot.hasActiveSelection)
    }

    func testSnapshotBuilderPreservesOpenNestedFolderTreeForSpaceTransition() {
        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let settings = makeIsolatedSettings()
        let profileId = UUID()
        let source = Space(name: "Source", profileId: profileId)
        let destination = Space(name: "Destination", profileId: profileId)
        let parent = TabFolder(name: "Parent", spaceId: source.id, index: 0)
        let child = TabFolder(name: "Child", spaceId: source.id, parentFolderId: parent.id, index: 0)
        parent.isOpen = true
        child.isOpen = true
        let nestedPin = makeSpacePinnedPin(spaceId: source.id, folderId: child.id, index: 0, title: "Nested")

        browserManager.tabManager.spaces = [source, destination]
        browserManager.tabManager.setFolders([parent, child], for: source.id)
        browserManager.tabManager.setSpacePinnedShortcuts([nestedPin], for: source.id)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = source.id

        let snapshot = SpaceSidebarTransitionSnapshotBuilder.make(
            sourceSpace: source,
            destinationSpace: destination,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: browserManager.splitManager,
            settings: settings
        )

        guard case .folder(let parentSnapshot) = snapshot.source.pinnedItems.first else {
            return XCTFail("Expected parent folder snapshot")
        }
        guard case .folder(let childSnapshot) = parentSnapshot.bodyChildren.first else {
            return XCTFail("Expected child folder snapshot")
        }

        XCTAssertTrue(parentSnapshot.isOpen)
        XCTAssertEqual(parentSnapshot.bodyChildren.map(\.id), [child.id])
        XCTAssertTrue(childSnapshot.isOpen)
        XCTAssertEqual(childSnapshot.bodyChildren.map(\.id), [nestedPin.id])
    }

    func testSwipeGestureBeginCreatesInteractiveSessionWithoutDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertEqual(state.sourceSpaceId, ids[0])
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.phase, .interactive)
        XCTAssertEqual(state.trigger, .swipe)
        XCTAssertFalse(state.isCommitArmed)
        XCTAssertEqual(state.progress, 0, accuracy: 0.0001)
    }

    func testSwipeUpdateLatchesDestinationAndPreservesProgress() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: nil,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.24, accuracy: 0.0001)
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.direction, 0)

        state.updateSwipeGesture(
            progress: 0.32,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.32, accuracy: 0.0001)
        XCTAssertEqual(state.direction, 1)
        XCTAssertEqual(state.destinationSpaceId, ids[1])
        XCTAssertTrue(state.isCommitArmed)
    }

    func testSwipeBelowThresholdCancelsCleanly() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertFalse(state.shouldCommitSwipeOnEnd)
        XCTAssertNil(state.finishTransition(commit: false))
        XCTAssertFalse(state.hasDestination)
    }

    func testSwipeAboveThresholdCommitsDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.74,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(state.shouldCommitSwipeOnEnd)
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertFalse(state.hasDestination)
    }

    func testSpaceListMutationResetsInvalidTransitionSafely() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )

        state.syncSpaces(
            orderedSpaceIds: [ids[0], ids[1]],
            committedSpaceId: ids[0]
        )

        XCTAssertFalse(state.hasDestination)
        XCTAssertNil(state.visualSelectedSpaceId)
    }

    func testNormalizedProgressPreservesReleaseTailAtHighVelocity() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 0, width: 100),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 40, width: 100),
            0.4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 82, width: 100),
            0.82,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 91, width: 100),
            0.87,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 100, width: 100),
            0.92,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 180, width: 100),
            0.92,
            accuracy: 0.0001
        )
    }

    func testDirectionLatchKeepsFirstDirection() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: nil, rawDeltaX: -1.2),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: 1, rawDeltaX: 4),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: -1, rawDeltaX: -4),
            -1
        )
    }

    func testSwipeTrackerHorizontalLockConsumesAndEmitsExpectedEvents() {
        var tracker = SpaceSwipeGestureTracker()

        let began = tracker.process(
            .init(phase: .began, scrollingDeltaX: -0.4, scrollingDeltaY: 0.1),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(began.handling, .consume)
        XCTAssertEqual(began.emittedEvents, [.init(phase: .began, direction: nil, progress: 0)])

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: -3.0, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .consume)
        XCTAssertEqual(changed.emittedEvents.count, 1)
        XCTAssertEqual(changed.emittedEvents[0].phase, .changed)
        XCTAssertEqual(changed.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(changed.emittedEvents[0].progress, 0.01)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .consume)
        XCTAssertEqual(ended.emittedEvents.count, 1)
        XCTAssertEqual(ended.emittedEvents[0].phase, .ended)
        XCTAssertEqual(ended.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(ended.emittedEvents[0].progress, 0.01)
    }

    func testSwipeTrackerVerticalLockCancelsAndForwardsToUnderlying() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(phase: .began, scrollingDeltaX: 0.2, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: 0.4, scrollingDeltaY: 3.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .forwardToUnderlying)
        XCTAssertEqual(changed.emittedEvents, [.init(phase: .cancelled, direction: nil, progress: 0)])
        XCTAssertEqual(tracker.axisLock, .vertical)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .forwardToUnderlying)
        XCTAssertTrue(ended.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
    }

    func testSwipeTrackerDisabledDoesNotStartGesture() {
        var tracker = SpaceSwipeGestureTracker()

        let result = tracker.process(
            .init(phase: .began, scrollingDeltaX: -4, scrollingDeltaY: 0),
            width: 200,
            isEnabled: false
        )

        XCTAssertEqual(result.handling, .forwardToUnderlying)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
        XCTAssertFalse(tracker.didSendBeginEvent)
    }

    private func makeIsolatedSettings() -> SumiSettingsService {
        let suiteName = "SpaceSidebarTransitionStateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return SumiSettingsService(userDefaults: defaults)
    }

    private func makeEssentialPin(profileId: UUID, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }

    private func makeSpacePinnedPin(
        spaceId: UUID,
        folderId: UUID,
        index: Int,
        title: String
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: URL(string: "https://example.com/\(UUID().uuidString)")!,
            title: title
        )
    }

}
