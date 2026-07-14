import CoreGraphics
import SumiDomain
@testable import Sumi
import SwiftData
import XCTest

@MainActor
final class SpaceSidebarTransitionCoordinatorTests: XCTestCase {
    func testScheduledClickCompletionResolvesDestinationFromCurrentSpaces() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let staleDestination = Space(name: "Deleted", profileId: destinationProfileId)
        let replacement = Space(name: "Replacement", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, staleDestination])
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, staleDestination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.switchSpace(to: staleDestination, context: context)
        browserHarness.tabManager.spaceStateOwner.replaceSpaces([source, replacement])

        XCTAssertEqual(delayedActions.scheduledDelays, [SpaceSidebarRenderPolicy.completionDelay])
        delayedActions.runNext()

        let activeSpaceId = try XCTUnwrap(windowState.currentSpaceId)
        XCTAssertTrue(browserHarness.tabManager.spaceStateOwner.spaces.contains { $0.id == activeSpaceId })
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
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
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

    func testScheduledClickCompletionStartsPendingGeometryEpochBeforePromotion() async throws {
        let windowState = BrowserWindowState()
        let sourceProfileId = UUID()
        let destinationProfileId = UUID()
        let source = Space(name: "Source", profileId: sourceProfileId)
        let destination = Space(name: "Destination", profileId: destinationProfileId)
        let browserHarness = try TestSidebarBrowserContextHarness(spaces: [source, destination])
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

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
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
        guard case .setActiveSpaceFromTransition(let committedSpaceId, _) = browserHarness.transitionEvents.last else {
            XCTFail("Expected completion through transition-aware space activation")
            return
        }
        XCTAssertEqual(committedSpaceId, destination.id)

        let pendingGeneration = try XCTUnwrap(dragState.pendingGeometryGeneration)
        XCTAssertEqual(dragState.activeGeometryGeneration, 0)

        applyIncompleteInteractiveGeometry(
            to: dragState,
            spaceId: destination.id,
            profileId: destinationProfileId,
            generation: pendingGeneration
        )

        XCTAssertEqual(dragState.pendingGeometryGeneration, pendingGeneration)
        XCTAssertEqual(dragState.activeGeometryGeneration, 0)

        applyRegularListGeometry(
            to: dragState,
            spaceId: destination.id,
            generation: pendingGeneration
        )
        dragState.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.activeGeometryGeneration, pendingGeneration)
        XCTAssertNil(dragState.pendingGeometryGeneration)
        XCTAssertEqual(
            dragState.geometrySnapshot.pageGeometryByKey[
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

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, destination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
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
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
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
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
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

        let pendingGeneration = try XCTUnwrap(dragState.pendingGeometryGeneration)
        applyCompleteInteractiveGeometry(
            to: dragState,
            spaceId: scheduledDestination.id,
            profileId: scheduledDestination.profileId,
            generation: pendingGeneration
        )
        dragState.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.pendingGeometryGeneration, pendingGeneration)
        XCTAssertEqual(dragState.activeGeometryGeneration, 0)

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
        dragState.flushDeferredGeometryForDragStart()

        XCTAssertEqual(dragState.activeGeometryGeneration, pendingGeneration)
        XCTAssertNil(dragState.pendingGeometryGeneration)
        XCTAssertEqual(
            dragState.geometrySnapshot.pageGeometryByKey[
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
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentSpaceId = UUID()

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [fallbackSpace, secondSpace],
            currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            inventory: browserHarness.roles.inventory,
            selection: browserHarness.roles.selection,
            pinProjection: browserHarness.roles.pinProjection,
            dragState: SidebarDragState(),
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.handleSpacesCollectionChange(context)

        XCTAssertEqual(windowState.currentSpaceId, fallbackSpace.id)
        XCTAssertEqual(browserHarness.tabManager.spaceStateOwner.currentSpace?.id, fallbackSpace.id)
        XCTAssertEqual(browserHarness.transitionEvents, [.setActiveSpace(fallbackSpace.id)])
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
        guard case .setActiveSpaceFromTransition(let committedSpaceId, _) = fixture.browserHarness.transitionEvents.last else {
            XCTFail("Expected relative switch to commit through transition-aware activation")
            return
        }
        XCTAssertEqual(committedSpaceId, lastSpace.id)
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
        guard case .setActiveSpaceFromTransition(let committedSpaceId, _) = fixture.browserHarness.transitionEvents.last else {
            XCTFail("Expected relative switch to commit through transition-aware activation")
            return
        }
        XCTAssertEqual(committedSpaceId, firstSpace.id)
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
        XCTAssertTrue(fixture.browserHarness.transitionEvents.isEmpty)
        XCTAssertEqual(fixture.coordinator.transitionState.phase, .idle)

        fixture.windowState.currentSpaceId = UUID()
        fixture.switchRelativeSpace(offset: 1, spaces: spaces)

        XCTAssertTrue(fixture.browserHarness.transitionEvents.isEmpty)
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
        let settingsHarness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: settingsHarness.defaults)
        let dragState = SidebarDragState()
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let coordinator = SpaceSidebarTransitionCoordinator(delayedActions: delayedActions.scheduler)

        windowState.tabManager = browserHarness.tabManager
        windowState.currentSpaceId = currentSpace.id
        browserHarness.tabManager.spaceStateOwner.replaceCurrentSpace(currentSpace)
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
                currentSpaces: { browserHarness.tabManager.spaceStateOwner.spaces },
                windowState: windowState,
                browserContext: browserHarness.context,
                inventory: browserHarness.roles.inventory,
                selection: browserHarness.roles.selection,
                pinProjection: browserHarness.roles.pinProjection,
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
    dragState.applyPageGeometry(
        spaceId: spaceId,
        profileId: profileId,
        frame: CGRect(x: 0, y: 0, width: 300, height: 600),
        renderMode: .interactive,
        generation: generation
    )
    dragState.applySectionFrame(
        spaceId: spaceId,
        section: .essentials,
        frame: CGRect(x: 0, y: 0, width: 300, height: 140),
        generation: generation
    )
    dragState.applySectionFrame(
        spaceId: spaceId,
        section: .spacePinned,
        frame: CGRect(x: 0, y: 140, width: 300, height: 180),
        generation: generation
    )
    dragState.applySectionFrame(
        spaceId: spaceId,
        section: .spaceRegular,
        frame: CGRect(x: 0, y: 320, width: 300, height: 260),
        generation: generation
    )
    dragState.applyEssentialsLayoutMetrics(
        SidebarEssentialsLayoutUpdate(
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
        ),
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
    dragState.applyRegularListHitTarget(
        spaceId: spaceId,
        frame: CGRect(x: 0, y: 320, width: 300, height: 260),
        itemCount: 6,
        generation: generation
    )
}

private enum TestSidebarTransitionEvent: Equatable {
    case setActiveSpace(UUID)
    case setActiveSpaceFromTransition(UUID, SpaceTransitionIdentity)
}

private final class TransitionEventRecorder {
    var events: [TestSidebarTransitionEvent] = []
}

@MainActor
private final class TestSidebarBrowserContextHarness {
    let container: ModelContainer
    let tabManager: TabManager
    let profileManager: ProfileManager
    let context: SidebarBrowserContext
    let roles: SidebarConsumerTestRoles

    private let browserManager: BrowserManager
    private let liveFolderManager: SumiLiveFolderManager
    private let downloadManager = DownloadManager.unavailable()
    private let downloadsPopoverPresenter = DownloadsPopoverPresenter()
    private let glanceManager = GlanceManager()
    private let extensionSurfaceStore = BrowserExtensionSurfaceStore(extensionManager: nil)
    private let workspaceThemeCoordinator = WorkspaceThemeCoordinator()
    private let transitionEventRecorder = TransitionEventRecorder()

    var transitionEvents: [TestSidebarTransitionEvent] {
        transitionEventRecorder.events
    }

    init(spaces: [Space]) throws {
        container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        self.browserManager = browserManager
        tabManager = browserManager.tabManager
        tabManager.spaceStateOwner.replaceSpaces(spaces)
        tabManager.spaceStateOwner.replaceCurrentSpace(spaces.first)
        tabManager.startupRestoreLifecycle.markLoadFinished()
        profileManager = browserManager.profileManager
        profileManager.ensureDefaultProfile()
        liveFolderManager = browserManager.liveFolderManager
        roles = SidebarConsumerTestSupport.roles(tabManager: tabManager)

        let tabManager = tabManager
        let profileManager = profileManager
        let liveFolderManager = liveFolderManager
        let downloadManager = downloadManager
        let downloadsPopoverPresenter = downloadsPopoverPresenter
        let glanceManager = glanceManager
        let extensionSurfaceStore = extensionSurfaceStore
        let workspaceThemeCoordinator = workspaceThemeCoordinator
        let transitionEventRecorder = transitionEventRecorder

        context = SidebarBrowserContext(
            profileManager: profileManager,
            liveFolderManager: liveFolderManager,
            splitQuery: browserManager.splitComposition.query,
            splitLayout: browserManager.splitComposition.layout,
            emptySplitCreation: browserManager.splitComposition.emptyCreation,
            downloadManager: downloadManager,
            downloadsPopoverPresenter: downloadsPopoverPresenter,
            glanceManager: glanceManager,
            extensionSurfaceStore: extensionSurfaceStore,
            faviconImageReader: TabDependencyIsolationDefaults.faviconCapabilities.images,
            presentationActions: SidebarBrowserPresentationActions(
                showShortcutEditor: { _, _, _, _ in /* No-op. */ },
                showFolderEditor: { _, _, _, _ in /* No-op. */ },
                showFolderSearchPopover: { _, _, _, _ in /* No-op. */ },
                folderSearchAnchorHoverChanged: { _, _, _ in /* No-op. */ },
                showSpaceEditor: { _, _, _, _ in /* No-op. */ },
                showGradientEditorForSpace: { _, _ in /* No-op. */ },
                confirmDeleteSpace: { _, _ in /* No-op. */ },
                presentSharingServicePicker: { _, _ in /* No-op. */ }
            ),
            headerContext: { _ in fatalError("Unused in SpaceSidebarTransitionCoordinatorTests") },
            isTransitioningProfile: { false },
            currentProfile: { profileManager.profiles.first },
            extensionToolbarSlots: { _, _ in [] },
            extensionActionBrowserContext: { _ in
                fatalError("Unused in SpaceSidebarTransitionCoordinatorTests")
            },
            savedSidebarWidth: { _ in BrowserWindowState.sidebarDefaultWidth },
            configureMediaStore: { _, _ in /* No-op. */ },
            spaceTransitions: SidebarSpaceTransitionActions(
                completePendingSplitGroupFocusIfReady: { _, _ in /* No-op. */ },
                setActiveSpace: { space, windowState in
                    transitionEventRecorder.events.append(.setActiveSpace(space.id))
                    tabManager.spaceStateOwner.replaceCurrentSpace(space)
                    windowState.currentSpaceId = space.id
                    workspaceThemeCoordinator.update(
                        for: windowState,
                        to: space.workspaceTheme,
                        animate: true,
                        isActiveWindow: true
                    )
                },
                setActiveSpaceFromTransition: { space, windowState, identity in
                    guard identity.destinationSpaceId == space.id,
                          windowState.windowThemeState.matchesInteractiveSpaceTransition(identity) else {
                        return
                    }
                    transitionEventRecorder.events.append(.setActiveSpaceFromTransition(space.id, identity))
                    tabManager.spaceStateOwner.replaceCurrentSpace(space)
                    windowState.currentSpaceId = space.id
                    workspaceThemeCoordinator.finishInteractiveTransition(
                        to: space.workspaceTheme,
                        in: windowState,
                        identity: identity
                    )
                },
                beginInteractiveSpaceTransition: { source, destination, identity, windowState in
                    workspaceThemeCoordinator.beginInteractiveTransition(
                        from: source,
                        to: destination,
                        identity: identity,
                        initialProgress: 0,
                        in: windowState
                    )
                },
                updateInteractiveSpaceTransition: { progress, identity, windowState in
                    workspaceThemeCoordinator.updateInteractiveTransition(
                        progress: progress,
                        identity: identity,
                        in: windowState
                    )
                },
                cancelInteractiveSpaceTransition: { identity, windowState in
                    workspaceThemeCoordinator.cancelInteractiveTransition(
                        in: windowState,
                        identity: identity
                    )
                }
            ),
            commands: SidebarBrowserCommandActions(
                canCreateFolderInCurrentSpace: { _ in true },
                showGradientEditor: { _ in /* No-op. */ },
                toggleSidebar: { _ in /* No-op. */ },
                openAppearanceSettings: { _ in /* No-op. */ },
                closeDownloadsPopover: { _ in /* No-op. */ },
                requestUserTabActivation: { _, _ in /* No-op. */ },
                closeTab: { _, _ in /* No-op. */ },
                moveTabUp: { _ in /* No-op. */ },
                moveTabDown: { _ in /* No-op. */ },
                focusSplitGroup: { _, _, _ in /* No-op. */ },
                restoreShortcutSplitMember: { _, _, _ in /* No-op. */ },
                closeSplitMember: { _, _, _ in /* No-op. */ },
                openForegroundTab: { _, _, _ in nil },
                openNewTabOrFloatingBar: { _ in /* No-op. */ },
                duplicateTab: { _, _ in /* No-op. */ },
                pinShortcutGlobally: { _, _, _, _ in /* No-op. */ },
                toggleDownloadsPopover: { _ in /* No-op. */ },
                createFolderInCurrentSpace: { _ in /* No-op. */ },
                createRSSLiveFolderInCurrentSpace: { _ in /* No-op. */ },
                createGitHubPRFolderInCurrentSpace: { _ in /* No-op. */ },
                createGitHubIssuesFolderInCurrentSpace: { _ in /* No-op. */ },
                unloadShortcutPin: { _, _ in /* No-op. */ },
                unloadShortcutPins: { _, _ in /* No-op. */ }
            ),
            windowRegistry: { nil }
        )
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        workspaceThemeCoordinator.restore(theme, in: windowState)
    }
}
