import Foundation

/// Validates window selection / space / profile runtime state after structural mutations.
@MainActor
final class BrowserWindowStateValidationOwner {
    private let tabManagerAction: () -> TabManager
    private let windowRegistryAction: () -> WindowRegistry?
    private let selectionService: ShellSelectionService
    private let syncShortcutSelectionStateAction: (BrowserWindowState) -> Void
    private let commitWorkspaceThemeAction: (WorkspaceTheme, BrowserWindowState) -> Void
    private let applyTabSelectionAction: (Tab, BrowserWindowState, Bool, Bool, Bool, Bool) -> Void
    private let showEmptyStateAction: (BrowserWindowState) -> Void
    private let persistWindowSessionAction: (BrowserWindowState) -> Void
    private let refreshCompositorAction: (BrowserWindowState) -> Void

    init(
        tabManager: @escaping () -> TabManager,
        windowRegistry: @escaping () -> WindowRegistry?,
        selectionService: ShellSelectionService,
        syncShortcutSelectionState: @escaping (BrowserWindowState) -> Void,
        commitWorkspaceTheme: @escaping (WorkspaceTheme, BrowserWindowState) -> Void,
        applyTabSelection: @escaping (Tab, BrowserWindowState, Bool, Bool, Bool, Bool) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void,
        refreshCompositor: @escaping (BrowserWindowState) -> Void
    ) {
        self.tabManagerAction = tabManager
        self.windowRegistryAction = windowRegistry
        self.selectionService = selectionService
        self.syncShortcutSelectionStateAction = syncShortcutSelectionState
        self.commitWorkspaceThemeAction = commitWorkspaceTheme
        self.applyTabSelectionAction = applyTabSelection
        self.showEmptyStateAction = showEmptyState
        self.persistWindowSessionAction = persistWindowSession
        self.refreshCompositorAction = refreshCompositor
    }

    convenience init(browserManager: BrowserManager) {
        let selectionService = browserManager.shellSelectionService
        self.init(
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            selectionService: selectionService,
            syncShortcutSelectionState: { [weak browserManager] windowState in
                browserManager?.syncShortcutSelectionState(for: windowState)
            },
            commitWorkspaceTheme: { [weak browserManager] theme, windowState in
                browserManager?.workspaceThemeTransitionOwner.commitWorkspaceTheme(theme, for: windowState)
            },
            applyTabSelection: { [weak browserManager] tab, windowState, updateSpaceFromTab, updateTheme, rememberSelection, persistSelection in
                browserManager?.applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: updateSpaceFromTab,
                    updateTheme: updateTheme,
                    rememberSelection: rememberSelection,
                    persistSelection: persistSelection
                )
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionActivationOwner.persistWindowSession(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.refreshCompositor(for: windowState)
            }
        )
    }

    func validateWindowStates() {
        let tabManager = tabManagerAction()
        for (_, windowState) in windowRegistryAction()?.windows ?? [:] {
            var needsUpdate = false
            if let currentTabId = windowState.currentTabId,
               tabManager.tabCollectionMembershipOwner.tab(for: currentTabId) == nil {
                windowState.currentTabId = nil
                needsUpdate = true
            }

            let resolvedWindowSpace = resolvedWindowOwnedSpace(
                for: windowState,
                tabManager: tabManager
            )
            if windowState.currentSpaceId != resolvedWindowSpace?.id {
                windowState.currentSpaceId = resolvedWindowSpace?.id
                needsUpdate = true
            }

            if !windowState.isShowingEmptyState && !hasValidCurrentSelection(in: windowState) {
                if let currentSpace = space(for: windowState.currentSpaceId),
                   let preferred = preferredTabForSpace(currentSpace, in: windowState) {
                    applyTabSelectionAction(
                        preferred,
                        windowState,
                        false,
                        false,
                        false,
                        false
                    )
                } else if let fallback = preferredTabForWindow(windowState) {
                    applyTabSelectionAction(
                        fallback,
                        windowState,
                        false,
                        false,
                        false,
                        false
                    )
                } else {
                    showEmptyStateAction(windowState)
                }
                needsUpdate = true
            }

            let previousShortcutSelection = windowState.currentShortcutPinId
            syncShortcutSelectionStateAction(windowState)
            if previousShortcutSelection != windowState.currentShortcutPinId {
                needsUpdate = true
            }

            if let currentSpace = space(for: windowState.currentSpaceId) {
                commitWorkspaceThemeAction(currentSpace.workspaceTheme, windowState)
                if windowState.currentProfileId != currentSpace.profileId {
                    windowState.currentProfileId = currentSpace.profileId
                    needsUpdate = true
                }
            } else if windowState.currentSpaceId == nil {
                commitWorkspaceThemeAction(.default, windowState)
                if windowState.currentProfileId != nil {
                    windowState.currentProfileId = nil
                    needsUpdate = true
                }
            }

            if needsUpdate {
                refreshCompositorAction(windowState)
                persistWindowSessionAction(windowState)
            }
        }
    }

    func updateProfileRuntimeStates(activeWindowState: BrowserWindowState? = nil) {
        let tabManager = tabManagerAction()
        let focusedWindow = activeWindowState ?? windowRegistryAction()?.activeWindow
        let focusedWindowId = focusedWindow?.id

        for space in tabManager.spaceStateOwner.spaces {
            let isFocusedSpace = focusedWindow?.currentSpaceId == space.id
            let hasRegularTabs = !tabManager.regularTabCollectionOwner.tabs(in: space).isEmpty
            let hasPinnedLiveShortcut: Bool
            if let windowId = focusedWindowId {
                hasPinnedLiveShortcut = tabManager.shortcutPresentationOwner.liveShortcutTabs(in: windowId)
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

    private func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManagerAction().spaceStateOwner.space(with: spaceId)
    }

    private func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        selectionService.hasValidCurrentSelection(
            in: windowState,
            tabStore: tabManagerAction().runtimeStore
        )
    }

    private func preferredTabForWindow(_ windowState: BrowserWindowState) -> Tab? {
        selectionService.preferredTabForWindow(
            windowState,
            tabStore: tabManagerAction().runtimeStore
        )
    }

    private func preferredTabForSpace(_ space: Space, in windowState: BrowserWindowState) -> Tab? {
        selectionService.preferredTabForSpace(
            space,
            in: windowState,
            tabStore: tabManagerAction().runtimeStore
        )
    }

    private func resolvedWindowOwnedSpace(
        for windowState: BrowserWindowState,
        tabManager: TabManager
    ) -> Space? {
        if let currentSpace = space(for: windowState.currentSpaceId) {
            return currentSpace
        }

        if let currentTabId = windowState.currentTabId,
           let tabSpaceId = tabManager.tabCollectionMembershipOwner.tab(for: currentTabId)?.spaceId,
           let tabSpace = space(for: tabSpaceId) {
            return tabSpace
        }

        if let profileId = windowState.currentProfileId {
            return tabManager.spaceStateOwner.spaces.first(where: { $0.profileId == profileId })
        }

        return nil
    }
}
