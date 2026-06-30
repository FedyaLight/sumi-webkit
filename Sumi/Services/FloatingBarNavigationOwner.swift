import Foundation

@MainActor
struct FloatingBarNavigationOwner {
    private enum CommitTarget {
        case currentPage(Tab)
        case newTab
    }

    struct Actions {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let window: @MainActor (UUID) -> BrowserWindowState?
        let activePageTab: @MainActor (BrowserWindowState) -> Tab?
        let cancelEmptySplitPlaceholder: @MainActor (BrowserWindowState) -> Void
        let commitEmptySplitPlaceholder: @MainActor (UUID, BrowserWindowState) -> Void
        let replaceEmptySplitPlaceholder: @MainActor (Tab, BrowserWindowState) -> Bool
        let selectTab: @MainActor (Tab, BrowserWindowState) -> Void
        let createNewTab: @MainActor (BrowserWindowState, String) -> Void
        let createNewTabAfterSidebarInsertion: @MainActor (BrowserWindowState, String) -> Void
        let configuredNewTabPageURL: @MainActor () -> String?
        let normalizeURL: @MainActor (String) -> String
        let loadCurrentPageURL: @MainActor (Tab, BrowserWindowState, String) -> Void
        let navigateCurrentPage: @MainActor (Tab, BrowserWindowState, String) -> Void
        let applySettingsSurfaceNavigation: @MainActor (String) -> Void
        let dismissWorkspaceThemePickerIfNeededDiscarding: @MainActor () -> Void
        let persistWindowSession: @MainActor (BrowserWindowState) -> Void
        let schedulePersistWindowSession: @MainActor (BrowserWindowState) -> Void
    }

    func focus(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason,
        actions: Actions
    ) {
        let shouldOverrideDraft = !prefill.isEmpty
            || windowState.floatingBarDraftText.isEmpty
            || navigateCurrentTab
        if shouldOverrideDraft {
            windowState.floatingBarDraftText = prefill
            windowState.floatingBarDraftNavigatesCurrentTab = navigateCurrentTab
        }
        windowState.floatingBarPresentationReason = presentationReason
        windowState.isFloatingBarVisible = true
        actions.dismissWorkspaceThemePickerIfNeededDiscarding()
        actions.persistWindowSession(windowState)
    }

    func focusActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason,
        actions: Actions
    ) {
        guard let activeWindow = actions.activeWindow() else { return }
        focus(
            in: activeWindow,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: actions
        )
    }

    func showNewTab(
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        windowState.floatingBarDraftText = ""
        windowState.floatingBarDraftNavigatesCurrentTab = false
        windowState.floatingBarPresentationReason = .emptySpace
        windowState.isFloatingBarVisible = true
        actions.dismissWorkspaceThemePickerIfNeededDiscarding()
        actions.persistWindowSession(windowState)
    }

    func openNewTabSurface(
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        if let configuredURL = actions.configuredNewTabPageURL() {
            actions.createNewTab(windowState, configuredURL)
        } else {
            showNewTab(in: windowState, actions: actions)
        }
    }

    func updateDraft(
        in windowState: BrowserWindowState,
        text: String,
        actions: Actions
    ) {
        guard windowState.floatingBarDraftText != text else { return }
        windowState.floatingBarDraftText = text
        actions.schedulePersistWindowSession(windowState)
    }

    func dismiss(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true,
        actions: Actions
    ) {
        if cancelEmptySplitPlaceholder {
            actions.cancelEmptySplitPlaceholder(windowState)
        }
        windowState.floatingBarPresentationReason = .none
        windowState.isFloatingBarVisible = false
        if !preserveDraft {
            windowState.floatingBarDraftText = ""
            windowState.floatingBarDraftNavigatesCurrentTab = false
        }
        actions.persistWindowSession(windowState)
    }

    func dismissActiveWindow(
        preserveDraft: Bool,
        actions: Actions
    ) {
        guard let activeWindow = actions.activeWindow(),
              activeWindow.isFloatingBarVisible
        else { return }

        dismiss(in: activeWindow, preserveDraft: preserveDraft, actions: actions)
    }

    @discardableResult
    func dismissIfVisible(
        in windowId: UUID,
        preserveDraft: Bool,
        actions: Actions
    ) -> Bool {
        guard let windowState = actions.window(windowId),
              windowState.isFloatingBarVisible
        else { return false }

        dismiss(in: windowState, preserveDraft: preserveDraft, actions: actions)
        return true
    }

    func commitNavigatesCurrentTab(
        in windowState: BrowserWindowState,
        actions: Actions
    ) -> Bool {
        if case .currentPage = resolveCommitTarget(in: windowState, actions: actions) {
            return true
        }
        return false
    }

    func commitSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        let commitTarget = resolveCommitTarget(in: windowState, actions: actions)
        dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false,
            actions: actions
        )
        openSuggestion(
            suggestion,
            in: windowState,
            commitTarget: commitTarget,
            actions: actions
        )
    }

    func commitNavigation(
        to urlString: String,
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        let commitTarget = resolveCommitTarget(in: windowState, actions: actions)
        dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false,
            actions: actions
        )

        switch commitTarget {
        case .currentPage(let navigationTargetTab):
            actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
            actions.loadCurrentPageURL(navigationTargetTab, windowState, urlString)
            actions.applySettingsSurfaceNavigation(urlString)
        case .newTab:
            actions.createNewTabAfterSidebarInsertion(windowState, urlString)
        }
    }

    func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        openSuggestion(
            suggestion,
            in: windowState,
            commitTarget: resolveCommitTarget(in: windowState, actions: actions),
            actions: actions
        )
    }

    private func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        commitTarget: CommitTarget,
        actions: Actions
    ) {
        switch suggestion.type {
        case .tab(let existingTab):
            if !actions.replaceEmptySplitPlaceholder(existingTab, windowState) {
                actions.selectTab(existingTab, windowState)
            }
            RuntimeDiagnostics.debug(
                "Switched to existing tab: \(existingTab.name)",
                category: "FloatingBar"
            )
        case .history(let historyEntry):
            switch commitTarget {
            case .currentPage(let navigationTargetTab):
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                actions.loadCurrentPageURL(navigationTargetTab, windowState, historyEntry.url.absoluteString)
                actions.applySettingsSurfaceNavigation(historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to history URL: \(historyEntry.url)",
                    category: "FloatingBar"
                )
            case .newTab:
                actions.createNewTabAfterSidebarInsertion(windowState, historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from history in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .bookmark(let bookmark):
            switch commitTarget {
            case .currentPage(let navigationTargetTab):
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                actions.loadCurrentPageURL(navigationTargetTab, windowState, bookmark.url.absoluteString)
                actions.applySettingsSurfaceNavigation(bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to bookmark URL: \(bookmark.url)",
                    category: "FloatingBar"
                )
            case .newTab:
                actions.createNewTabAfterSidebarInsertion(windowState, bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from bookmark in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .url, .search:
            switch commitTarget {
            case .currentPage(let navigationTargetTab):
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                actions.navigateCurrentPage(navigationTargetTab, windowState, suggestion.text)
                actions.applySettingsSurfaceNavigation(suggestion.text)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to: \(suggestion.text)",
                    category: "FloatingBar"
                )
            case .newTab:
                let resolved = actions.normalizeURL(suggestion.text)
                actions.createNewTabAfterSidebarInsertion(windowState, resolved)
                RuntimeDiagnostics.debug(
                    "Created new tab in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        }
    }

    private func resolveCommitTarget(
        in windowState: BrowserWindowState,
        actions: Actions
    ) -> CommitTarget {
        guard windowState.floatingBarDraftNavigatesCurrentTab,
              let navigationTargetTab = actions.activePageTab(windowState)
        else {
            return .newTab
        }
        return .currentPage(navigationTargetTab)
    }

    func dismissAfterSelection(
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        guard windowState.isFloatingBarVisible || windowState.floatingBarPresentationReason != .none else {
            return
        }
        let preserveDraft: Bool
        switch windowState.floatingBarPresentationReason {
        case .emptySpace, .splitTabPicker:
            preserveDraft = false
        case .keyboard, .none:
            preserveDraft = true
        }
        dismiss(in: windowState, preserveDraft: preserveDraft, actions: actions)
    }

    func sanitize(
        in windowState: BrowserWindowState,
        hasValidCurrentSelection: Bool,
        actions: Actions
    ) {
        if hasValidCurrentSelection {
            clearEmptyStatePresentationIfNeeded(in: windowState, actions: actions)
        } else if windowState.isShowingEmptyState {
            if windowState.floatingBarPresentationReason == .none {
                windowState.floatingBarPresentationReason = .emptySpace
            }
        } else {
            windowState.floatingBarPresentationReason = .none
        }
    }

    private func clearEmptyStatePresentationIfNeeded(
        in windowState: BrowserWindowState,
        actions: Actions
    ) {
        guard windowState.isShowingEmptyState
            || windowState.floatingBarPresentationReason == .emptySpace
        else { return }

        windowState.isShowingEmptyState = false
        dismiss(in: windowState, preserveDraft: false, actions: actions)
    }
}
