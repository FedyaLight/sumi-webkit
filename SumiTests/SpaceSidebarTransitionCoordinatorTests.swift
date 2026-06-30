@testable import Sumi
import CoreGraphics
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
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentProfileId = sourceProfileId
        windowState.currentSpaceId = source.id

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, staleDestination],
            currentSpaces: { browserHarness.tabManager.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.switchSpace(to: staleDestination, context: context)
        browserHarness.tabManager.spaces = [source, replacement]

        try await Task.sleep(
            nanoseconds: UInt64((SpaceSidebarRenderPolicy.completionDelay + 0.15) * 1_000_000_000)
        )

        let activeSpaceId = try XCTUnwrap(windowState.currentSpaceId)
        XCTAssertTrue(browserHarness.tabManager.spaces.contains { $0.id == activeSpaceId })
        XCTAssertNotEqual(activeSpaceId, staleDestination.id)
        XCTAssertFalse(windowState.isInteractiveSpaceTransition)
        XCTAssertNil(coordinator.transitionSnapshot)
        XCTAssertFalse(coordinator.transitionState.hasDestination)
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
            currentSpaces: { browserHarness.tabManager.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            dragState: dragState,
            settings: settings,
            allowsInteractiveWork: true,
            reduceMotion: true
        )

        coordinator.switchSpace(to: destination, context: context)

        try await Task.sleep(
            nanoseconds: UInt64((SpaceSidebarRenderPolicy.completionDelay + 0.15) * 1_000_000_000)
        )

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
        let coordinator = SpaceSidebarTransitionCoordinator()

        defer {
            coordinator.cancelPendingSpaceTransition()
            settingsHarness.reset()
        }

        windowState.tabManager = browserHarness.tabManager
        windowState.currentSpaceId = source.id
        browserHarness.commitWorkspaceTheme(source.workspaceTheme, for: windowState)

        let context = SpaceSidebarTransitionCoordinator.Context(
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.tabManager.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
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

        try await Task.sleep(
            nanoseconds: UInt64((SpaceSidebarRenderPolicy.completionDelay + 0.20) * 1_000_000_000)
        )

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
            spaces: [source, scheduledDestination, directDestination],
            currentSpaces: { browserHarness.tabManager.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
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

        try await Task.sleep(
            nanoseconds: UInt64((SpaceSidebarRenderPolicy.completionDelay + 0.20) * 1_000_000_000)
        )

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
            currentSpaces: { browserHarness.tabManager.spaces },
            windowState: windowState,
            browserContext: browserHarness.context,
            dragState: SidebarDragState(),
            settings: settings,
            allowsInteractiveWork: false,
            reduceMotion: true
        )

        coordinator.handleSpacesCollectionChange(context)

        XCTAssertEqual(windowState.currentSpaceId, fallbackSpace.id)
        XCTAssertEqual(browserHarness.tabManager.currentSpace?.id, fallbackSpace.id)
        XCTAssertEqual(browserHarness.transitionEvents, [.setActiveSpace(fallbackSpace.id)])
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
        spaceId: spaceId,
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
        maxDropRowCount: 3,
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

    private let liveFolderManager = SumiLiveFolderManager()
    private let splitManager = SplitViewManager()
    private let downloadManager = DownloadManager()
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
        tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        tabManager.spaces = spaces
        tabManager.currentSpace = spaces.first
        tabManager.markInitialDataLoadFinished()
        profileManager = ProfileManager(context: container.mainContext)
        profileManager.ensureDefaultProfile()

        let tabManager = tabManager
        let profileManager = profileManager
        let liveFolderManager = liveFolderManager
        let splitManager = splitManager
        let downloadManager = downloadManager
        let downloadsPopoverPresenter = downloadsPopoverPresenter
        let glanceManager = glanceManager
        let extensionSurfaceStore = extensionSurfaceStore
        let workspaceThemeCoordinator = workspaceThemeCoordinator
        let transitionEventRecorder = transitionEventRecorder

        context = SidebarBrowserContext(
            tabManager: tabManager,
            profileManager: profileManager,
            liveFolderManager: liveFolderManager,
            splitManager: splitManager,
            downloadManager: downloadManager,
            downloadsPopoverPresenter: downloadsPopoverPresenter,
            glanceManager: glanceManager,
            extensionSurfaceStore: extensionSurfaceStore,
            presentationActions: SidebarBrowserPresentationActions(
                showShortcutEditor: { _, _, _, _ in },
                showFolderEditor: { _, _, _, _ in },
                showSpaceEditor: { _, _, _, _ in },
                showGradientEditorForSpace: { _, _ in },
                confirmDeleteSpace: { _, _ in },
                presentSharingServicePicker: { _, _ in }
            ),
            headerContext: { _ in fatalError("Unused in SpaceSidebarTransitionCoordinatorTests") },
            tabStructuralRevision: { 0 },
            isTransitioningProfile: { false },
            currentProfile: { profileManager.profiles.first },
            currentTab: { _ in tabManager.currentTab },
            space: { spaceId in tabManager.spaces.first { $0.id == spaceId } },
            extensionToolbarSlots: { _, _ in [] },
            extensionActionBrowserContext: { _ in
                fatalError("Unused in SpaceSidebarTransitionCoordinatorTests")
            },
            savedSidebarWidth: { _ in BrowserWindowState.sidebarDefaultWidth },
            performDrop: { _, _, _ in false },
            configureMediaStore: { _, _ in },
            spaceTransitions: SidebarSpaceTransitionActions(
                completePendingSplitGroupFocusIfReady: { _, _ in },
                setActiveSpace: { space, windowState in
                    transitionEventRecorder.events.append(.setActiveSpace(space.id))
                    tabManager.currentSpace = space
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
                    tabManager.currentSpace = space
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
                showGradientEditor: { _ in },
                toggleSidebar: { _ in },
                openAppearanceSettings: { _ in },
                closeDownloadsPopover: { _ in },
                requestUserTabActivation: { _, _ in },
                closeTab: { _, _ in },
                moveTabUp: { _ in },
                moveTabDown: { _ in },
                focusSplitGroup: { _, _ in },
                restoreShortcutSplitMember: { _, _, _ in },
                openForegroundTab: { _, _, _ in nil },
                openNewTabOrFloatingBar: { _ in },
                duplicateTab: { _, _ in },
                pinShortcutGlobally: { _, _, _, _ in },
                toggleDownloadsPopover: { _ in },
                createFolderInCurrentSpace: { _ in },
                createRSSLiveFolderInCurrentSpace: { _ in },
                createGitHubPullRequestsLiveFolderInCurrentSpace: { _ in },
                createGitHubIssuesLiveFolderInCurrentSpace: { _ in }
            )
        )
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        workspaceThemeCoordinator.restore(theme, in: windowState)
    }
}
