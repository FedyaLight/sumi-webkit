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
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        workspaceThemeCoordinator.restore(theme, in: windowState)
    }
}
