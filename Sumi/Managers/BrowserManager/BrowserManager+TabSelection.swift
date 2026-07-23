import Foundation

extension BrowserManager {
    /// Select a tab in the active window (convenience method for sidebar clicks)
    @discardableResult
    func selectTab(_ tab: Tab) -> BrowserTabSelectionOutcome {
        guard let activeWindow = windowRegistry.activeWindow else {
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
        browserTabSelection.selectTab(
            tab,
            in: windowState,
            loadPolicy: loadPolicy
        )
    }

    func requestUserTabActivation(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        loadPolicy: TabSelectionLoadPolicy = .immediate
    ) {
        _ = browserTabSelection.requestUserTabActivation(
            tab,
            in: windowState,
            loadPolicy: loadPolicy
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
        _ = browserTabSelection.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: updateSpaceFromTab,
            updateTheme: updateTheme,
            rememberSelection: rememberSelection,
            persistSelection: persistSelection,
            loadPolicy: loadPolicy
        )
    }

    func materializeVisibleTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        browserTabSelection.materializeVisibleTabWebViewIfNeeded(
            tab,
            in: windowState
        )
    }

    func publishPreparedTabSelectionEffects(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        previousTabID: UUID?,
        previousSpaceID: UUID?
    ) {
        _ = browserTabSelection.publishPreparedSelectionEffects(
            tab,
            in: windowState,
            previousTabID: previousTabID,
            previousSpaceID: previousSpaceID
        )
    }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        browserTabSelection.syncShortcutSelectionState(
            for: windowState
        )
    }

    func showEmptyState(
        in windowState: BrowserWindowState,
        presentNewTabCommandPalette: Bool = false
    ) {
        browserTabSelection.showEmptyState(
            in: windowState,
            persistSelection: true
        )

        if presentNewTabCommandPalette && windowState.isShowingEmptyState {
            urlBarBundle.commandPalette.presentation.showNewTab(in: windowState)
        }
    }

    func showEmptyStateWithoutPersistence(
        in windowState: BrowserWindowState
    ) {
        browserTabSelection.showEmptyState(
            in: windowState,
            persistSelection: false
        )
    }
}
