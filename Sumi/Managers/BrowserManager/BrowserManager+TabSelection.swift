import Foundation

extension BrowserManager {
    private var tabSelectionActions: BrowserTabSelectionOwner.Actions {
        BrowserTabSelectionOwner.liveActions(for: self)
    }

    /// Select a tab in the active window (convenience method for sidebar clicks)
    @discardableResult
    func selectTab(_ tab: Tab) -> BrowserTabSelectionOutcome {
        guard let activeWindow = windowRegistry?.activeWindow else {
            RuntimeDiagnostics.emit {
                "⚠️ [BrowserManager] No active window for tab selection"
            }
            return .rejected
        }
        return selectTab(tab, in: activeWindow)
    }

    /// Select a tab in a specific window
    @discardableResult
    func selectTab(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy = .immediate
    ) -> BrowserTabSelectionOutcome {
        tabLifecycleService.selection.selectTab(
            tab,
            in: windowState,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
    }

    func requestUserTabActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy = .immediate
    ) {
        _ = tabLifecycleService.selection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool = true
    ) {
        applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            updateTheme: updateTheme,
            rememberSelection: rememberSelection,
            persistSelection: persistSelection,
            loadPolicy: .immediate
        )
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool = true,
        loadPolicy: TabSelectionLoadPolicy
    ) {
        _ = tabLifecycleService.selection.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            updateTheme: updateTheme,
            rememberSelection: rememberSelection,
            persistSelection: persistSelection,
            loadPolicy: loadPolicy,
            actions: tabSelectionActions
        )
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        tabLifecycleService.selection.materializeVisibleTabWebViewIfNeeded(
            tab,
            in: windowState,
            actions: tabSelectionActions
        )
    }

    func publishPreparedTabSelectionEffects(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousTabID: UUID?,
        previousSpaceID: UUID?
    ) {
        _ = tabLifecycleService.selection.publishPreparedSelectionEffects(
            tab,
            in: windowState,
            previousTabID: previousTabID,
            previousSpaceID: previousSpaceID,
            actions: tabSelectionActions
        )
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        tabLifecycleService.selection.syncShortcutSelectionState(
            for: windowState,
            actions: tabSelectionActions
        )
    }

    func showEmptyState(
        in windowState: BrowserWindowState,
        presentNewTabFloatingBar: Bool = false
    ) {
        tabLifecycleService.selection.showEmptyState(
            in: windowState,
            persistSelection: true,
            actions: tabSelectionActions
        )

        if presentNewTabFloatingBar && windowState.isShowingEmptyState {
            urlBarBundle.floatingBar.presentation.showNewTab(in: windowState)
        }
    }

    func showEmptyStateWithoutPersistence(
        in windowState: BrowserWindowState
    ) {
        tabLifecycleService.selection.showEmptyState(
            in: windowState,
            persistSelection: false,
            actions: tabSelectionActions
        )
    }
}
