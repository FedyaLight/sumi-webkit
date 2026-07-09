import Foundation

@MainActor
final class BrowserWindowSpaceStateOwner {
    private let tabManager: () -> TabManager
    private let windowRegistry: () -> WindowRegistry?
    private let selectionService: ShellSelectionService
    private let sanitizeFloatingBarState: (BrowserWindowState) -> Void
    private let syncShortcutSelectionState: (BrowserWindowState) -> Void
    private let updateWorkspaceTheme: (BrowserWindowState, WorkspaceTheme, Bool) -> Void
    private let finishInteractiveSpaceTransition: (Space, BrowserWindowState, SpaceTransitionIdentity?) -> Void
    private let applyTabSelection: (Tab, BrowserWindowState, Bool, Bool, Bool, Bool) -> Void
    private let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
    private let showEmptyState: (BrowserWindowState) -> Void
    private let adoptProfileForSpaceChange: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void
    private let completePendingSplitGroupFocusIfReady: (BrowserWindowState, UUID) -> Void
    private let updateProfileRuntimeStatesAction: (BrowserWindowState?) -> Void
    private let validateWindowStatesAction: () -> Void

    init(
        tabManager: @escaping () -> TabManager,
        windowRegistry: @escaping () -> WindowRegistry?,
        selectionService: ShellSelectionService,
        sanitizeFloatingBarState: @escaping (BrowserWindowState) -> Void,
        syncShortcutSelectionState: @escaping (BrowserWindowState) -> Void,
        updateWorkspaceTheme: @escaping (BrowserWindowState, WorkspaceTheme, Bool) -> Void,
        finishInteractiveSpaceTransition: @escaping (Space, BrowserWindowState, SpaceTransitionIdentity?) -> Void,
        applyTabSelection: @escaping (Tab, BrowserWindowState, Bool, Bool, Bool, Bool) -> Void,
        performImmediateVisualHandoffIfPossible: @escaping (BrowserWindowState) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void,
        adoptProfileForSpaceChange: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        completePendingSplitGroupFocusIfReady: @escaping (BrowserWindowState, UUID) -> Void,
        updateProfileRuntimeStates: @escaping (BrowserWindowState?) -> Void,
        validateWindowStates: @escaping () -> Void
    ) {
        self.tabManager = tabManager
        self.windowRegistry = windowRegistry
        self.selectionService = selectionService
        self.sanitizeFloatingBarState = sanitizeFloatingBarState
        self.syncShortcutSelectionState = syncShortcutSelectionState
        self.updateWorkspaceTheme = updateWorkspaceTheme
        self.finishInteractiveSpaceTransition = finishInteractiveSpaceTransition
        self.applyTabSelection = applyTabSelection
        self.performImmediateVisualHandoffIfPossible = performImmediateVisualHandoffIfPossible
        self.showEmptyState = showEmptyState
        self.adoptProfileForSpaceChange = adoptProfileForSpaceChange
        self.persistWindowSession = persistWindowSession
        self.completePendingSplitGroupFocusIfReady = completePendingSplitGroupFocusIfReady
        self.updateProfileRuntimeStatesAction = updateProfileRuntimeStates
        self.validateWindowStatesAction = validateWindowStates
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager().spaceStateOwner.space(with: spaceId)
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabManager().runtimeStore
        )
    }

    func syncWindowSpaceContext(in windowState: BrowserWindowState, animateTheme: Bool) {
        _ = animateTheme
        let currentSpace = space(for: windowState.currentSpaceId)
        let activeProfileId = currentSpace?.profileId
        if windowState.currentProfileId != activeProfileId {
            windowState.currentProfileId = activeProfileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }

    func setActiveSpace(
        _ space: Space,
        in windowState: BrowserWindowState,
        completingTransition identity: SpaceTransitionIdentity? = nil
    ) {
        if let identity {
            guard identity.destinationSpaceId == space.id,
                  windowState.windowThemeState.matchesInteractiveSpaceTransition(identity) else {
                return
            }
        }

        let isSameSpace = windowState.currentSpaceId == space.id
        if identity == nil,
           isSameSpace,
           hasValidCurrentSelection(in: windowState),
           currentTabIfSessionResolved(for: windowState) != nil {
            sanitizeFloatingBarState(windowState)
            applySpaceContext(space, to: windowState)
            syncShortcutSelectionState(windowState)
            persistWindowSession(windowState)
            return
        }

        let selectedTargetTab = selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState
        )
        let isActiveWindow = windowRegistry()?.activeWindow?.id == windowState.id
        if isActiveWindow {
            tabManager().spaceLifecycleOwner.setActiveSpace(
                space,
                preferredTab: selectedTargetTab,
                contextWindowId: windowState.id
            )
        }

        applySpaceContext(space, to: windowState)
        if let identity {
            finishInteractiveSpaceTransition(space, windowState, identity)
        } else {
            updateWorkspaceTheme(windowState, space.workspaceTheme, true)
        }

        if let selectedTargetTab {
            applyTabSelection(
                selectedTargetTab,
                windowState,
                false,
                false,
                true,
                false
            )
            performImmediateVisualHandoffIfPossible(windowState)
        } else {
            showEmptyState(windowState)
        }

        if isActiveWindow {
            adoptProfileForSpaceChange(windowState)
        }
        persistWindowSession(windowState)
        completePendingSplitGroupFocusIfReady(windowState, space.id)
    }

    func selectionTargetForSpaceActivation(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        selectionService.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: tabManager().runtimeStore
        )
    }

    /// Compatibility forward to `BrowserWindowStateValidationOwner`.
    func validateWindowStates() {
        validateWindowStatesAction()
    }

    /// Compatibility forward to `BrowserWindowStateValidationOwner`.
    func updateProfileRuntimeStates(activeWindowState: BrowserWindowState? = nil) {
        updateProfileRuntimeStatesAction(activeWindowState)
    }

    private func currentTabIfSessionResolved(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.isAwaitingInitialSessionResolution else { return nil }
        return selectionService.currentTab(
            for: windowState,
            tabStore: tabManager().runtimeStore
        )
    }

    private func applySpaceContext(
        _ space: Space,
        to windowState: BrowserWindowState
    ) {
        if windowState.currentSpaceId != space.id {
            windowState.currentSpaceId = space.id
        }
        let profileId = space.profileId
        if windowState.currentProfileId != profileId {
            windowState.currentProfileId = profileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }
}
