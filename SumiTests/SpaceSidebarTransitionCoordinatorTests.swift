import CoreGraphics
import Observation
@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class SpaceSidebarTransitionCoordinatorTests: XCTestCase {
    func testRecordedViewportIsAvailableToCommittedScrollSurface() {
        let coordinator = SpaceSidebarTransitionCoordinator()
        let spaceID = UUID()
        let viewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 260,
            contentHeight: 500,
            viewportHeight: 100
        )

        coordinator.recordScrollViewport(viewport, for: spaceID)

        XCTAssertEqual(coordinator.scrollViewport(for: spaceID), viewport)
    }

    func testScheduledClickCompletionResolvesDestinationFromCurrentSpaces() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let staleDestination = Space(name: "Deleted", profileId: destinationProfileId)
        let replacement = Space(name: "Replacement", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, staleDestination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, staleDestination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.switchSpace(to: staleDestination, context: context)
        browserHarness.browserManager.spaceStateOwner.replaceSpaces([source, replacement])

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        delayedActions.runNext()

        let activeSpaceId = try XCTUnwrap(windowState.currentSpaceId)
        XCTAssertTrue(browserHarness.browserManager.spaceStateOwner.spaces.contains { $0.id == activeSpaceId })
        XCTAssertNotEqual(activeSpaceId, staleDestination.id)
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
    }

    func testClickTransitionMountsLayersAtZeroProgressBeforeAnimating() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: false
        )

        coordinator.switchSpace(to: destination, context: context)

        // The transition layers must mount at progress 0 so SwiftUI has a
        // starting offset to animate from; otherwise the newly-inserted pages
        // (and their essentials) appear already at the committed position and
        // swap without sliding.
        XCTAssertEqual(coordinator.transitionState.phase, .clickAnimating)
        XCTAssertTrue(coordinator.transitionState.hasDestination)
        XCTAssertEqual(coordinator.transitionState.progress, 0)
        XCTAssertNotNil(coordinator.transitionSnapshot)

        // The slide is started from the layers' `onAppear` once the 0-progress
        // frame is committed (simulated here since there is no live view).
        coordinator.startPendingClickAnimation(context: context)
        XCTAssertGreaterThan(coordinator.transitionState.progress, 0)
    }

    func testDiscreteSwipeUsesClickTransitionWithoutInteractiveHold() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.handleSwipeEvent(
            .init(phase: .discrete, direction: 1, progress: 0.4),
            context: context
        )

        XCTAssertEqual(coordinator.transitionState.trigger, .click)
        XCTAssertEqual(coordinator.transitionState.phase, .clickAnimating)
        XCTAssertEqual(coordinator.transitionState.progress, 0)
        XCTAssertEqual(coordinator.transitionState.destinationSpaceId, destination.id)
        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])

        coordinator.startPendingClickAnimation(context: context)
        XCTAssertEqual(coordinator.transitionState.progress, 1)

        delayedActions.runNext()

        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertEqual(coordinator.transitionState.phase, .idle)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
    }

    func testSwipeCommitDoesNotExposeSourceAsCommittedAfterTransitionReset() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.handleSwipeEvent(
            .init(phase: .changed, direction: 1, progress: 0.35),
            context: context
        )

        let observer = SidebarTransitionRenderFrameObserver(
            coordinator: coordinator,
            windowState: windowState
        )
        observer.start()

        coordinator.handleSwipeEvent(
            .init(phase: .ended, direction: 1, progress: 0.35),
            context: context
        )
        delayedActions.runNext()

        XCTAssertFalse(observer.frames.isEmpty)
        XCTAssertFalse(
            observer.frames.contains {
                $0.committedSpaceId == source.id && !$0.usesTransitionLayers
            },
            "transition reset must not render the source live page before the destination is committed"
        )
    }

    func testScheduledClickCompletionStartsPendingGeometryEpochBeforePromotion() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 36,
            contentHeight: 360,
            viewportHeight: 140
        )
        let destinationViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 64,
            contentHeight: 420,
            viewportHeight: 160
        )

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.recordScrollViewport(sourceViewport, for: source.id)
        coordinator.recordScrollViewport(destinationViewport, for: destination.id)
        coordinator.switchSpace(to: destination, context: context)
        let activeSnapshot = try XCTUnwrap(coordinator.transitionSnapshot)
        XCTAssertTrue(activeSnapshot.matches(coordinator.transitionState))
        XCTAssertEqual(activeSnapshot.source.spaceId, source.id)
        XCTAssertEqual(activeSnapshot.destination.spaceId, destination.id)
        XCTAssertEqual(activeSnapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(activeSnapshot.destination.scrollViewport, destinationViewport)

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        delayedActions.runNext()

        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)

        let pendingGeneration = try XCTUnwrap(dragState.geometry.pendingGeometryGeneration)
        XCTAssertEqual(dragState.geometry.activeGeometryGeneration, 0)

        applyIncompleteInteractiveGeometry(
            to: dragState,
            spaceId: destination.id,
            profileId: destinationProfileId,
            generation: pendingGeneration
        )

        XCTAssertEqual(dragState.geometry.pendingGeometryGeneration, pendingGeneration)
        XCTAssertEqual(dragState.geometry.activeGeometryGeneration, 0)

        applyRegularListGeometry(
            to: dragState,
            spaceId: destination.id,
            generation: pendingGeneration
        )
        dragState.geometry.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.geometry.activeGeometryGeneration, pendingGeneration)
        XCTAssertNil(dragState.geometry.pendingGeometryGeneration)
        XCTAssertEqual(
            dragState.geometry.geometrySnapshot.pageGeometryByKey[
                SidebarPageGeometryKey(spaceId: destination.id, profileId: destinationProfileId)
            ]?.renderMode,
            .interactive
        )
    }

    func testSwipeTransitionCapturesMatchingSnapshotAndClearsAfterCommit() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)
        let sourceViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 48,
            contentHeight: 390,
            viewportHeight: 150
        )
        let destinationViewport = SpaceSidebarSnapshotViewport(
            contentOffsetY: 96,
            contentHeight: 520,
            viewportHeight: 180
        )

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.recordScrollViewport(sourceViewport, for: source.id)
        coordinator.recordScrollViewport(destinationViewport, for: destination.id)
        coordinator.handleSwipeEvent(
            .init(phase: .changed, direction: 1, progress: 0.35),
            context: context
        )

        XCTAssertEqual(coordinator.transitionState.trigger, .swipe)
        XCTAssertEqual(coordinator.transitionState.sourceSpaceId, source.id)
        XCTAssertEqual(coordinator.transitionState.destinationSpaceId, destination.id)
        let activeSnapshot = try XCTUnwrap(coordinator.transitionSnapshot)
        XCTAssertTrue(activeSnapshot.matches(coordinator.transitionState))
        XCTAssertEqual(activeSnapshot.source.scrollViewport, sourceViewport)
        XCTAssertEqual(activeSnapshot.destination.scrollViewport, destinationViewport)

        coordinator.handleSwipeEvent(
            .init(phase: .ended, direction: 1, progress: 0.35),
            context: context
        )

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        delayedActions.runNext()

        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
    }

    func testCommittedSpaceChangeCancelsScheduledCompletion() async throws {
        let windowState = BrowserWindowState(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!)
        let source = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Source",
            workspaceTheme: WorkspaceTheme(gradientTheme: .default)
        )
        let scheduledDestination = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
            name: "Scheduled",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito)
        )
        let directDestination = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!,
            name: "Direct",
            workspaceTheme: WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: [
                        WorkspaceThemeColor(hex: "#0A84FF", isPrimary: true, position: .topLeft),
                        WorkspaceThemeColor(hex: "#FFD60A", position: .bottom),
                    ],
                    opacity: 0.78,
                    texture: 0.125
                )
            )
        )
        let browserHarness = try TestSidebarBrowserContextHarness(
            spaces: [source, scheduledDestination, directDestination]
        )
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.switchSpace(to: scheduledDestination, context: context)
        let scheduledIdentity = try XCTUnwrap(coordinator.transitionState.transitionIdentity)
        XCTAssertEqual(windowState.interactiveSpaceTransitionIdentity, scheduledIdentity)

        windowState.windowThemeState.restore(directDestination.workspaceTheme)
        windowState.currentSpaceId = directDestination.id
        coordinator.handleCommittedSpaceChange(context)
        XCTAssertEqual(windowState.currentSpaceId, directDestination.id, "direct switch should commit immediately")
        XCTAssertNotEqual(windowState.interactiveSpaceTransitionIdentity, scheduledIdentity)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertEqual(windowState.currentSpaceId, directDestination.id, "scheduled completion should not override direct switch")
        XCTAssertFalse(windowState.displayedWorkspaceTheme.visuallyEquals(scheduledDestination.workspaceTheme))
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
    }

    func testCommittedSpaceChangeKeepsCancelledDestinationGeometryFromPromoting() async throws {
        let windowState = BrowserWindowState(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D5")!)
        let sourceProfileId = UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!
        let scheduledProfileId = UUID(uuidString: "00000000-0000-0000-0000-0000000000F5")!
        let directProfileId = UUID(uuidString: "00000000-0000-0000-0000-0000000001F5")!
        let source = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A5")!,
            name: "Source",
            workspaceTheme: WorkspaceTheme(gradientTheme: .default),
            profileId: sourceProfileId
        )
        let scheduledDestination = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!,
            name: "Scheduled",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: scheduledProfileId
        )
        let directDestination = Space(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C5")!,
            name: "Direct",
            workspaceTheme: WorkspaceTheme(
                gradientTheme: WorkspaceGradientTheme(
                    colors: [
                        WorkspaceThemeColor(hex: "#0A84FF", isPrimary: true, position: .topLeft),
                        WorkspaceThemeColor(hex: "#FFD60A", position: .bottom),
                    ],
                    opacity: 0.78,
                    texture: 0.125
                )
            ),
            profileId: directProfileId
        )
        let browserHarness = try TestSidebarBrowserContextHarness(
            spaces: [source, scheduledDestination, directDestination]
        )
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.switchSpace(to: scheduledDestination, context: context)
        let scheduledIdentity = try XCTUnwrap(coordinator.transitionState.transitionIdentity)

        windowState.windowThemeState.restore(directDestination.workspaceTheme)
        windowState.currentSpaceId = directDestination.id
        coordinator.handleCommittedSpaceChange(context)

        XCTAssertEqual(windowState.currentSpaceId, directDestination.id)
        XCTAssertNotEqual(windowState.interactiveSpaceTransitionIdentity, scheduledIdentity)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)

        let pendingGeneration = try XCTUnwrap(dragState.geometry.pendingGeometryGeneration)
        applyCompleteInteractiveGeometry(
            to: dragState,
            spaceId: scheduledDestination.id,
            profileId: scheduledDestination.profileId,
            generation: pendingGeneration
        )
        dragState.geometry.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.geometry.pendingGeometryGeneration, pendingGeneration)
        XCTAssertEqual(dragState.geometry.activeGeometryGeneration, 0)

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertEqual(windowState.currentSpaceId, directDestination.id)
        XCTAssertFalse(windowState.displayedWorkspaceTheme.visuallyEquals(scheduledDestination.workspaceTheme))
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)

        applyCompleteInteractiveGeometry(
            to: dragState,
            spaceId: directDestination.id,
            profileId: directDestination.profileId,
            generation: pendingGeneration
        )
        dragState.geometry.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.geometry.activeGeometryGeneration, pendingGeneration)
        XCTAssertNil(dragState.geometry.pendingGeometryGeneration)
        XCTAssertEqual(
            dragState.geometry.geometrySnapshot.pageGeometryByKey[
                SidebarPageGeometryKey(spaceId: directDestination.id, profileId: directDestination.profileId)
            ]?.renderMode,
            .interactive
        )
    }

    func testSpacesCollectionChangeFallbackActivatesFirstSpaceThroughTransitionActions() throws {
        let windowState = BrowserWindowState()
        let fallbackSpace = Space(name: "Fallback")
        let secondSpace = Space(name: "Second")
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [fallbackSpace, secondSpace])
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.currentSpaceId = UUID()

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [fallbackSpace, secondSpace],
            currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            spaceCatalog: browserHarness.sidebar.spaceCatalog,
            inventory: browserHarness.sidebar.inventory,
            selection: browserHarness.sidebar.selection,
            pinProjection: browserHarness.sidebar.pinProjection,
            dragState: SidebarDragState(),
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.handleSpacesCollectionChange(context)

        XCTAssertEqual(windowState.currentSpaceId, fallbackSpace.id)
    }

    func testRuntimeRelativePreviousWrapsFromFirstToLastThroughTransitionPath() async throws {
        let firstSpace = Space(name: "First")
        let middleSpace = Space(name: "Middle")
        let lastSpace = Space(name: "Last")
        let spaces = [firstSpace, middleSpace, lastSpace]
        let fixture = try runtimeRelativeSwitchFixture(spaces: spaces, currentSpace: firstSpace)

        defer { fixture.cleanup() }

        fixture.switchRelativeSpace(offset: -1, spaces: spaces)

        fixture.completeScheduledSpaceTransition()

        XCTAssertEqual(fixture.windowState.currentSpaceId, lastSpace.id)
        XCTAssertFalse(fixture.coordinator.transitionState.hasDestination)
    }

    func testRuntimeRelativeNextWrapsFromLastToFirstThroughTransitionPath() async throws {
        let firstSpace = Space(name: "First")
        let middleSpace = Space(name: "Middle")
        let lastSpace = Space(name: "Last")
        let spaces = [firstSpace, middleSpace, lastSpace]
        let fixture = try runtimeRelativeSwitchFixture(spaces: spaces, currentSpace: lastSpace)

        defer { fixture.cleanup() }

        fixture.switchRelativeSpace(offset: 1, spaces: spaces)

        fixture.completeScheduledSpaceTransition()

        XCTAssertEqual(fixture.windowState.currentSpaceId, firstSpace.id)
        XCTAssertFalse(fixture.coordinator.transitionState.hasDestination)
    }

    func testRuntimeRelativeSwitchNoOpsWhenOnlyOneSpaceOrCurrentSpaceIsMissing() throws {
        let firstSpace = Space(name: "First")
        let secondSpace = Space(name: "Second")
        let spaces = [firstSpace, secondSpace]
        let fixture = try runtimeRelativeSwitchFixture(spaces: spaces, currentSpace: firstSpace)

        defer { fixture.cleanup() }

        fixture.switchRelativeSpace(offset: 1, spaces: [firstSpace])

        XCTAssertEqual(fixture.windowState.currentSpaceId, firstSpace.id)
        XCTAssertEqual(fixture.coordinator.transitionState.phase, .idle)

        fixture.windowState.currentSpaceId = UUID()
        fixture.switchRelativeSpace(offset: 1, spaces: spaces)

        XCTAssertEqual(fixture.coordinator.transitionState.phase, .idle)
    }

    func testRuntimeRelativeSwitchDoesNotReplaceActiveTransition() async throws {
        let firstSpace = Space(name: "First")
        let nextSpace = Space(name: "Next")
        let previousSpace = Space(name: "Previous")
        let spaces = [firstSpace, nextSpace, previousSpace]
        let fixture = try runtimeRelativeSwitchFixture(spaces: spaces, currentSpace: firstSpace)

        defer { fixture.cleanup() }

        fixture.switchRelativeSpace(offset: 1, spaces: spaces)
        XCTAssertEqual(fixture.coordinator.transitionState.destinationSpaceId, nextSpace.id)

        fixture.switchRelativeSpace(offset: -1, spaces: spaces)

        XCTAssertEqual(fixture.coordinator.transitionState.destinationSpaceId, nextSpace.id)

        fixture.completeScheduledSpaceTransition()
        XCTAssertEqual(fixture.windowState.currentSpaceId, nextSpace.id)
    }

    private func runtimeRelativeSwitchFixture(
        spaces: [Space],
        currentSpace: Space
    ) throws -> RuntimeRelativeSwitchFixture {
        let windowState = BrowserWindowState()
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: spaces)
        browserHarness.register(windowState)
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        windowState.currentSpaceId = currentSpace.id
        browserHarness.browserManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
        browserHarness.commitWorkspaceTheme(currentSpace.workspaceTheme, for: windowState)

        return RuntimeRelativeSwitchFixture(
            spaces: spaces,
            windowState: windowState,
            browserHarness: browserHarness,
            settingsHarness: settingsHarness,
            coordinator: coordinator,
            delayedActions: delayedActions,
            dragState: dragState,
            settings: settings
        )
    }

    private struct RuntimeRelativeSwitchFixture {
        let spaces: [Space]
        let windowState: BrowserWindowState
        let browserHarness: TestSidebarBrowserContextHarness
        let settingsHarness: TestDefaultsHarness
        let coordinator: SpaceSidebarTransitionCoordinator
        let delayedActions: ManualMainActorDelayedActionScheduler
        let dragState: SidebarDragState
        let settings: SumiSettingsService

        @MainActor
        func context(spaces contextSpaces: [Space]) -> SpaceSidebarTransitionCoordinator.Context {
            SpaceSidebarTransitionCoordinator.Context(
                spaces: contextSpaces,
                currentSpaces: { browserHarness.browserManager.spaceStateOwner.spaces },
                windowState: windowState,
                browserContext: browserHarness.context,
                spaceCatalog: browserHarness.sidebar.spaceCatalog,
                inventory: browserHarness.sidebar.inventory,
                selection: browserHarness.sidebar.selection,
                pinProjection: browserHarness.sidebar.pinProjection,
                dragState: dragState,
                settings: settings,
                allowsInteractiveWork: true,
                reduceMotion: true
            )
        }

        @MainActor
        func switchRelativeSpace(offset: Int, spaces switchSpaces: [Space]) {
            coordinator.switchRelativeSpace(offset: offset, context: context(spaces: switchSpaces))
        }

        @MainActor
        func completeScheduledSpaceTransition() {
            XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
            delayedActions.runNext()
        }

        @MainActor
        func cleanup() {
            coordinator.cancelLocalSpaceTransitionIfNeeded(
                context: context(spaces: spaces),
                cancelTheme: true
            )
            settingsHarness.reset()
        }
    }
}

@MainActor
private func applyIncompleteInteractiveGeometry(
    to dragState: SidebarDragState,
    spaceId: UUID,
    profileId: UUID?,
    generation: Int
) {
    dragState.geometry.report(
        .page(
            spaceId: spaceId,
            profileId: profileId,
            frame: CGRect(x: 0, y: 0, width: 300, height: 600),
            renderMode: .interactive
        ),
        generation: generation
    )
    dragState.geometry.report(
        .essentials(SidebarEssentialsLayoutUpdate(
            spaceId: spaceId,
            input: SidebarEssentialsLayoutMetricsInput(
                profileId: profileId,
                frame: CGRect(x: 0, y: 0, width: 300, height: 140),
                dropFrame: CGRect(x: 0, y: 0, width: 300, height: 180),
                itemCount: 4,
                columnCount: 2,
                rowCount: 2,
                itemSize: CGSize(width: 96, height: 48),
                gridSpacing: 8,
                canAcceptDrop: true,
                visibleItemCount: 4,
                visibleRowCount: 2,
                maxDropRowCount: 3
            )
        )),
        generation: generation
    )
}

@MainActor
private func applyCompleteInteractiveGeometry(
    to dragState: SidebarDragState,
    spaceId: UUID,
    profileId: UUID?,
    generation: Int
) {
    applyIncompleteInteractiveGeometry(
        to: dragState,
        spaceId: spaceId,
        profileId: profileId,
        generation: generation
    )
    applyRegularListGeometry(
        to: dragState,
        spaceId: spaceId,
        generation: generation
    )
}

@MainActor
private func applyRegularListGeometry(
    to dragState: SidebarDragState,
    spaceId: UUID,
    generation: Int
) {
    let regularFrame = CGRect(x: 0, y: 320, width: 300, height: 260)
    dragState.geometry.report(
        .presentedSpaceList(
            PresentedSidebarLayout(
                spaceID: spaceId,
                sectionFrames: [
                    .spacePinned: CGRect(
                        x: 0,
                        y: 140,
                        width: 300,
                        height: 180
                    ),
                    .spaceRegular: regularFrame,
                ],
                topLevelPinnedItemTargets: [:],
                folderDropTargets: [:],
                folderChildDropTargets: [:],
                pinnedListHitTarget: nil,
                regularListHitTarget: SidebarRegularListHitMetrics(
                    frame: regularFrame,
                    rowIdentities: [
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!),
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!),
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000005")!),
                        .tab(UUID(uuidString: "00000000-0000-0000-0000-000000000006")!),
                    ]
                )
            )
        ),
        generation: generation
    )
}

private struct SidebarTransitionRenderFrame {
    let committedSpaceId: UUID?
    let usesTransitionLayers: Bool
}

@MainActor
private final class SidebarTransitionRenderFrameObserver: @unchecked Sendable {
    let coordinator: SpaceSidebarTransitionCoordinator
    let windowState: BrowserWindowState
    private(set) var frames: [SidebarTransitionRenderFrame] = []

    init(
        coordinator: SpaceSidebarTransitionCoordinator,
        windowState: BrowserWindowState
    ) {
        self.coordinator = coordinator
        self.windowState = windowState
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = coordinator.transitionState
            _ = coordinator.transitionSnapshot
            _ = windowState.currentSpaceId
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.frames.append(
                    SidebarTransitionRenderFrame(
                        committedSpaceId: self.windowState.currentSpaceId,
                        usesTransitionLayers: SpaceSidebarRenderPolicy.shouldUseTransitionLayers(
                            for: self.coordinator.transitionState
                        )
                    )
                )
                self.observe()
            }
        }
    }
}

@MainActor
private struct TransitionSidebarFixture {
    let spaceCatalog: SidebarSpaceCatalogProjection
    let inventory: SidebarSpaceInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let lifecycle: SidebarSpaceLifecycle

    init(browser: BrowserManager) {
        let registry = browser.windowRegistry
        let windows = SidebarWindowIdentityQuery(registry: registry)
        spaceCatalog = SidebarSpaceCatalogProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            pins: browser.shortcutPinCollectionStateOwner
        )
        inventory = SidebarSpaceInventoryProjection(
            runtime: browser.runtimePortConnection,
            spaces: browser.spaceStateOwner,
            regularTabs: browser.regularTabCollectionOwner,
            pinned: SidebarPinnedInventoryProjection(
                folders: browser.folderCollectionStateOwner,
                pins: browser.shortcutPinCollectionStateOwner,
                splitGroups: browser.splitGroupStore,
                splitOrdering: browser.splitGroupSidebarOrdering
            )
        )
        let splitQuery = browser.splitQuery
        selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: { true },
            windows: windows,
            windowTabs: browser.windowTabContext,
            shortcutPresentation: browser.shortcutPresentationOwner,
            splitQuery: splitQuery
        )
        pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: { true },
            windows: windows,
            essentials: browser.essentialsShortcutPlacementOwner,
            resolution: browser.shortcutPinRuntimeResolutionOwner
        )
        lifecycle = browser.sidebarSpaceLifecycle
    }
}

@MainActor
private final class TestSidebarBrowserContextHarness {
    let browserManager: BrowserManager
    let context: SidebarBrowserContext
    let sidebar: TransitionSidebarFixture

    init(spaces: [Space]) throws {
        let container = try SumiDatabase.inMemory()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container
            )
        )
        self.browserManager = browserManager
        let profileIDs = Set(spaces.compactMap(\.profileId))
        if profileIDs.isEmpty {
            browserManager.profileManager.ensureDefaultProfile()
        } else {
            browserManager.profileManager.profiles = profileIDs.map {
                Profile(id: $0, name: "Transition")
            }
        }
        browserManager.currentProfile = spaces.first.flatMap { space in
            browserManager.profileManager.profiles.first {
                $0.id == space.profileId
            }
        } ?? browserManager.profileManager.profiles.first
        browserManager.spaceStateOwner.replaceSpaces(spaces)
        browserManager.spaceStateOwner.replaceCurrentSpace(spaces.first)
        browserManager.startupRestoreLifecycle.markLoadFinished()
        let sidebar = TransitionSidebarFixture(browser: browserManager)
        self.sidebar = sidebar

        context = browserManager.composeSidebarBrowserContext(
            spaceLifecycle: sidebar.lifecycle
        )
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        browserManager.chromeBundle.workspaceThemeTransitionOwner
            .commitWorkspaceTheme(theme, for: windowState)
    }

    func register(_ windowState: BrowserWindowState) {
        browserManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        windowState.currentProfileId = browserManager.currentProfile?.id
        XCTAssertEqual(
            browserManager.windowRegistry.register(windowState),
            .registered
        )
        browserManager.windowRegistry.setActive(windowState)
    }
}
