import Foundation

@MainActor
final class BrowserTabSelectionOwner {
    struct RuntimeNotifications {
        let tabActivated: (Tab, Tab?) -> Void
        let tabSelectionChanged: (String) -> Void
    }

    struct Actions {
        let activeWindowId: () -> UUID?
        let window: (UUID) -> BrowserWindowState?
        let tab: (UUID) -> Tab?
        let ephemeralTab: (UUID, BrowserWindowState) -> Tab?
        let currentTab: (BrowserWindowState) -> Tab?
        let liveShortcutTabs: (UUID) -> [Tab]
        let updateActiveSplitSide: (UUID, UUID) -> Void
        let syncWindowSpaceContext: (BrowserWindowState, Bool) -> Void
        let space: (UUID?) -> Space?
        let updateWorkspaceTheme: (BrowserWindowState, WorkspaceTheme, Bool) -> Void
        let applySettingsSurfaceNavigation: (URL) -> Void
        let canMaterializeWebViewDuringStartup: (Tab) -> Bool
        let markTabAccessed: (UUID) -> Void
        let webViewCoordinator: () -> WebViewCoordinator?
        let handleNativeNowPlayingTabActivated: (UUID) -> Void
        let scheduleNativeNowPlayingRefresh: (UInt64) -> Void
        let fetchVisibleFavicon: (Tab) -> Void
        let dismissFloatingBarAfterSelection: (BrowserWindowState) -> Void
        let updateFindManagerCurrentTab: () -> Void
        let clearFindManagerCurrentTab: () -> Void
        let schedulePrepareVisibleWebViews: (BrowserWindowState) -> Void
        let refreshCompositor: (BrowserWindowState) -> Void
        let runtimeNotifications: RuntimeNotifications
        let updateActiveTabState: (Tab) -> Void
        let persistWindowSession: (BrowserWindowState) -> Void
        let selectionTargetForSpaceActivation: (Space, BrowserWindowState) -> Tab?
        let updateProfileRuntimeStates: (BrowserWindowState) -> Void
        let showNewTabFloatingBar: (BrowserWindowState) -> Void
    }

    private let userActivationBatcher = WindowTabActivationBatcher()

    func selectTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy,
        actions: Actions
    ) {
        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: loadPolicy,
            actions: actions
        )
    }

    func requestUserTabActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy,
        actions: Actions
    ) {
        userActivationBatcher.requestActivation(
            tabId: tab.id,
            in: windowState.id,
            loadPolicy: loadPolicy
        ) { [weak self, actions] windowId, activation in
            guard let self,
                  let windowState = actions.window(windowId),
                  let tab = Self.resolvedTab(
                    activation.tabId,
                    in: windowState,
                    actions: actions
                  )
            else {
                return
            }

            self.applyTabSelection(
                tab,
                in: windowState,
                updateSpaceFromTab: true,
                updateTheme: true,
                rememberSelection: true,
                persistSelection: true,
                loadPolicy: activation.loadPolicy,
                actions: actions
            )
        }
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool,
        loadPolicy: TabSelectionLoadPolicy,
        actions: Actions
    ) {
        let selectionApplication = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            rememberSelection: rememberSelection
        )

        let selectedTabChanged = selectionApplication.previousTabId != tab.id
        let requiresMaterialization = tab.isUnloaded && tab.requiresPrimaryWebView
        guard selectionApplication.stateDidChange || selectedTabChanged || requiresMaterialization else {
            return
        }

        actions.handleNativeNowPlayingTabActivated(tab.id)
        tab.noteSuspensionAccess()
        actions.dismissFloatingBarAfterSelection(windowState)
        actions.updateActiveSplitSide(tab.id, windowState.id)

        actions.syncWindowSpaceContext(windowState, updateTheme)

        if updateTheme && shouldUpdateWorkspaceTheme(for: windowState) {
            if let currentSpace = actions.space(windowState.currentSpaceId) {
                let animateWorkspaceTheme = selectionApplication.previousSpaceId != currentSpace.id
                actions.updateWorkspaceTheme(windowState, currentSpace.workspaceTheme, animateWorkspaceTheme)
            } else {
                actions.updateWorkspaceTheme(windowState, .default, false)
            }
        }

        if tab.representsSumiSettingsSurface {
            actions.applySettingsSurfaceNavigation(tab.url)
        }

        if tab.requiresPrimaryWebView {
            Self.scheduleTabLoadIfNeeded(
                tab,
                in: windowState,
                loadPolicy: loadPolicy,
                actions: actions
            )
        }

        actions.fetchVisibleFavicon(tab)
        actions.scheduleNativeNowPlayingRefresh(0)
        actions.updateFindManagerCurrentTab()
        actions.schedulePrepareVisibleWebViews(windowState)
        actions.refreshCompositor(windowState)

        let previousTab = selectionApplication.previousTabId.flatMap { previousId in
            actions.tab(previousId)
        }
        actions.runtimeNotifications.tabActivated(tab, previousTab)
        actions.runtimeNotifications.tabSelectionChanged("tab-selection-changed")

        if actions.activeWindowId() == windowState.id {
            actions.updateActiveTabState(tab)
        }
        if persistSelection {
            actions.persistWindowSession(windowState)
        }
    }

    private static func resolvedTab(
        _ tabId: UUID,
        in windowState: BrowserWindowState,
        actions: Actions
    ) -> Tab? {
        actions.tab(tabId)
            ?? actions.ephemeralTab(tabId, windowState)
    }

    private func shouldUpdateWorkspaceTheme(for windowState: BrowserWindowState) -> Bool {
        guard windowState.isInteractiveSpaceTransition else { return true }
        return windowState.currentSpaceId != windowState.spaceTransitionSourceSpaceId
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        Self.materializeVisibleTabWebViewIfNeeded(tab, in: windowState, actions: actions)
    }

    func syncShortcutSelectionState(
        for windowState: BrowserWindowState,
        actions: Actions
    ) {
        guard let currentTabId = windowState.currentTabId else {
            if !windowState.isShowingEmptyState {
                windowState.currentShortcutPinId = nil
                windowState.currentShortcutPinRole = nil
            }
            return
        }

        if let liveShortcutTab = actions.liveShortcutTabs(windowState.id)
            .first(where: { $0.id == currentTabId && $0.isShortcutLiveInstance }) {
            windowState.currentShortcutPinId = liveShortcutTab.shortcutPinId
            windowState.currentShortcutPinRole = liveShortcutTab.shortcutPinRole
        } else {
            windowState.currentShortcutPinId = nil
            windowState.currentShortcutPinRole = nil
        }
    }

    func showEmptyState(
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        if let currentSpace = actions.space(windowState.currentSpaceId),
           let selectableTab = actions.selectionTargetForSpaceActivation(currentSpace, windowState) {
            applyTabSelection(
                selectableTab,
                in: windowState,
                updateSpaceFromTab: false,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: true,
                loadPolicy: .immediate,
                actions: actions
            )
            return
        }

        windowState.currentTabId = nil
        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.isShowingEmptyState = true
        actions.updateProfileRuntimeStates(windowState)
        actions.clearFindManagerCurrentTab()
        actions.refreshCompositor(windowState)
        actions.persistWindowSession(windowState)
        actions.showNewTabFloatingBar(windowState)
    }

    private static func scheduleTabLoadIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy,
        actions: Actions
    ) {
        if tab.isUnloaded {
            tab.beginLoadingPresentationIfNeeded()
        }

        guard actions.canMaterializeWebViewDuringStartup(tab) else { return }

        switch loadPolicy {
        case .immediate:
            materializeVisibleTabWebViewIfNeeded(tab, in: windowState, actions: actions)
        case .deferred:
            Task { @MainActor [weak tab, actions] in
                guard let tab else { return }
                await Task.yield()
                guard actions.currentTab(windowState)?.id == tab.id else { return }
                materializeVisibleTabWebViewIfNeeded(tab, in: windowState, actions: actions)
                actions.refreshCompositor(windowState)
            }
        }
    }

    private static func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        actions.markTabAccessed(tab.id)
        guard let webViewCoordinator = actions.webViewCoordinator() else {
            tab.loadWebViewIfNeeded()
            return
        }
        if webViewCoordinator.getWebView(for: tab.id, in: windowState.id) == nil {
            _ = webViewCoordinator.getOrCreateWebView(for: tab, in: windowState.id)
        }
    }
}
