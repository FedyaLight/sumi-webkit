import Foundation

@MainActor
final class BrowserWindowSpaceStateOwner {
    struct Dependencies {
        let tabManager: () -> TabManager
        let windowRegistry: () -> WindowRegistry?
        let currentProfile: () -> Profile?
        let profileRouter: SumiProfileRouter
        let selectionService: ShellSelectionService
        let sanitizeFloatingBarState: (BrowserWindowState) -> Void
        let syncShortcutSelectionState: (BrowserWindowState) -> Void
        let updateWorkspaceTheme: (BrowserWindowState, WorkspaceTheme, Bool) -> Void
        let commitWorkspaceTheme: (WorkspaceTheme, BrowserWindowState) -> Void
        let finishInteractiveSpaceTransition: (Space, BrowserWindowState) -> Void
        let applyTabSelection: (Tab, BrowserWindowState, Bool, Bool, Bool, Bool) -> Void
        let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
        let showEmptyState: (BrowserWindowState) -> Void
        let adoptProfileForSpaceChange: (BrowserWindowState) -> Void
        let persistWindowSession: (BrowserWindowState) -> Void
        let completePendingSplitGroupFocusIfReady: (BrowserWindowState, UUID) -> Void
        let refreshCompositor: (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return dependencies.tabManager().spaces.first(where: { $0.id == spaceId })
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        dependencies.selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: dependencies.tabManager().runtimeStore
        )
    }

    func syncWindowSpaceContext(in windowState: BrowserWindowState, animateTheme: Bool) {
        _ = animateTheme
        let currentSpace = space(for: windowState.currentSpaceId)
        let activeProfileId = dependencies.profileRouter.activeProfileId(
            for: currentSpace,
            currentProfile: dependencies.currentProfile()
        )
        if windowState.currentProfileId != activeProfileId {
            windowState.currentProfileId = activeProfileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }

    func setActiveSpace(_ space: Space, in windowState: BrowserWindowState) {
        let isSameSpace = windowState.currentSpaceId == space.id
        if isSameSpace,
           hasValidCurrentSelection(in: windowState),
           currentTabIfSessionResolved(for: windowState) != nil {
            dependencies.sanitizeFloatingBarState(windowState)
            applySpaceContext(space, to: windowState)
            dependencies.syncShortcutSelectionState(windowState)
            dependencies.persistWindowSession(windowState)
            return
        }

        let selectedTargetTab = selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState
        )
        let isActiveWindow = dependencies.windowRegistry()?.activeWindow?.id == windowState.id
        if isActiveWindow {
            dependencies.tabManager().setActiveSpace(space, preferredTab: selectedTargetTab)
        }

        applySpaceContext(space, to: windowState)
        if windowState.spaceTransitionDestinationSpaceId == space.id {
            dependencies.finishInteractiveSpaceTransition(space, windowState)
        } else if !windowState.isInteractiveSpaceTransition {
            dependencies.updateWorkspaceTheme(windowState, space.workspaceTheme, true)
        }

        if let selectedTargetTab {
            dependencies.applyTabSelection(
                selectedTargetTab,
                windowState,
                false,
                false,
                true,
                false
            )
            dependencies.performImmediateVisualHandoffIfPossible(windowState)
        } else {
            dependencies.showEmptyState(windowState)
        }

        if isActiveWindow {
            dependencies.adoptProfileForSpaceChange(windowState)
        }
        dependencies.persistWindowSession(windowState)
        dependencies.completePendingSplitGroupFocusIfReady(windowState, space.id)
    }

    func selectionTargetForSpaceActivation(
        in space: Space,
        windowState: BrowserWindowState
    ) -> Tab? {
        dependencies.selectionService.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: dependencies.tabManager().runtimeStore
        )
    }

    func validateWindowStates() {
        let tabManager = dependencies.tabManager()
        for (_, windowState) in dependencies.windowRegistry()?.windows ?? [:] {
            var needsUpdate = false
            if let currentTabId = windowState.currentTabId,
               tabManager.tab(for: currentTabId) == nil {
                windowState.currentTabId = nil
                needsUpdate = true
            }

            if let currentSpaceId = windowState.currentSpaceId,
               tabManager.spaces.first(where: { $0.id == currentSpaceId }) == nil {
                windowState.currentSpaceId = tabManager.spaces.first?.id
                needsUpdate = true
            }

            if !windowState.isShowingEmptyState && !hasValidCurrentSelection(in: windowState) {
                if let currentSpace = space(for: windowState.currentSpaceId),
                   let preferred = preferredTabForSpace(currentSpace, in: windowState) {
                    dependencies.applyTabSelection(
                        preferred,
                        windowState,
                        false,
                        false,
                        false,
                        false
                    )
                } else if let fallback = preferredTabForWindow(windowState) {
                    dependencies.applyTabSelection(
                        fallback,
                        windowState,
                        false,
                        false,
                        false,
                        false
                    )
                } else {
                    dependencies.showEmptyState(windowState)
                }
                needsUpdate = true
            }

            let previousShortcutSelection = windowState.currentShortcutPinId
            dependencies.syncShortcutSelectionState(windowState)
            if previousShortcutSelection != windowState.currentShortcutPinId {
                needsUpdate = true
            }

            if windowState.currentSpaceId == nil {
                windowState.currentSpaceId = tabManager.spaces.first?.id
                needsUpdate = true
            }

            if let currentSpace = space(for: windowState.currentSpaceId) {
                dependencies.commitWorkspaceTheme(currentSpace.workspaceTheme, windowState)
                windowState.currentProfileId = currentSpace.profileId ?? dependencies.currentProfile()?.id
            } else if windowState.currentSpaceId == nil {
                dependencies.commitWorkspaceTheme(.default, windowState)
                windowState.currentProfileId = dependencies.currentProfile()?.id
            }

            if needsUpdate {
                dependencies.refreshCompositor(windowState)
                dependencies.persistWindowSession(windowState)
            }
        }
    }

    func updateProfileRuntimeStates(activeWindowState: BrowserWindowState? = nil) {
        let tabManager = dependencies.tabManager()
        let focusedWindow = activeWindowState ?? dependencies.windowRegistry()?.activeWindow
        let focusedWindowId = focusedWindow?.id

        for space in tabManager.spaces {
            let isFocusedSpace = focusedWindow?.currentSpaceId == space.id
            let hasRegularTabs = !tabManager.tabs(in: space).isEmpty
            let hasPinnedLiveShortcut: Bool
            if let windowId = focusedWindowId {
                hasPinnedLiveShortcut = tabManager.liveShortcutTabs(in: windowId)
                    .contains(where: { $0.spaceId == space.id && $0.shortcutPinRole != .essential })
            } else {
                hasPinnedLiveShortcut = false
            }
            let hasActiveShortcutSelection = focusedWindow?.selectedShortcutPinForSpace[space.id] != nil

            if isFocusedSpace {
                space.profileRuntimeState = hasRegularTabs || hasPinnedLiveShortcut || hasActiveShortcutSelection
                    ? .active
                    : .dormant
            } else if hasRegularTabs || hasPinnedLiveShortcut || hasActiveShortcutSelection {
                space.profileRuntimeState = .loadedInactive
            } else {
                space.profileRuntimeState = .dormant
            }
        }
    }

    private func preferredTabForWindow(_ windowState: BrowserWindowState) -> Tab? {
        dependencies.selectionService.preferredTabForWindow(
            windowState,
            tabStore: dependencies.tabManager().runtimeStore
        )
    }

    private func currentTabIfSessionResolved(for windowState: BrowserWindowState) -> Tab? {
        guard !windowState.isAwaitingInitialSessionResolution else { return nil }
        return dependencies.selectionService.currentTab(
            for: windowState,
            tabStore: dependencies.tabManager().runtimeStore
        )
    }

    private func preferredTabForSpace(_ space: Space, in windowState: BrowserWindowState) -> Tab? {
        dependencies.selectionService.preferredTabForSpace(
            space,
            in: windowState,
            tabStore: dependencies.tabManager().runtimeStore
        )
    }

    private func applySpaceContext(
        _ space: Space,
        to windowState: BrowserWindowState
    ) {
        if windowState.currentSpaceId != space.id {
            windowState.currentSpaceId = space.id
        }
        let profileId = space.profileId ?? dependencies.currentProfile()?.id
        if windowState.currentProfileId != profileId {
            windowState.currentProfileId = profileId
        }
        updateProfileRuntimeStates(activeWindowState: windowState)
    }
}
