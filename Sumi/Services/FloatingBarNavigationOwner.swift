import Foundation

@MainActor
struct FloatingBarNavigationOwner {
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
        windowState.floatingBarDraftNavigatesCurrentTab
            && actions.activePageTab(windowState) != nil
    }

    func commitSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool,
        actions: Actions
    ) {
        dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false,
            actions: actions
        )
        openSuggestion(
            suggestion,
            in: windowState,
            navigatesCurrentTab: navigatesCurrentTab,
            actions: actions
        )
    }

    func commitNavigation(
        to urlString: String,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool,
        actions: Actions
    ) {
        let navigationTargetTab = actions.activePageTab(windowState)
        dismiss(
            in: windowState,
            preserveDraft: false,
            cancelEmptySplitPlaceholder: false,
            actions: actions
        )

        if navigatesCurrentTab,
           let navigationTargetTab
        {
            actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
            navigationTargetTab.loadURL(urlString)
        } else {
            actions.createNewTabAfterSidebarInsertion(windowState, urlString)
        }
    }

    func openSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState,
        navigatesCurrentTab: Bool,
        actions: Actions
    ) {
        let navigationTargetTab = actions.activePageTab(windowState)

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
            if navigatesCurrentTab,
               let navigationTargetTab
            {
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                navigationTargetTab.loadURL(historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to history URL: \(historyEntry.url)",
                    category: "FloatingBar"
                )
            } else {
                actions.createNewTabAfterSidebarInsertion(windowState, historyEntry.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from history in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .bookmark(let bookmark):
            if navigatesCurrentTab,
               let navigationTargetTab
            {
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                navigationTargetTab.loadURL(bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to bookmark URL: \(bookmark.url)",
                    category: "FloatingBar"
                )
            } else {
                actions.createNewTabAfterSidebarInsertion(windowState, bookmark.url.absoluteString)
                RuntimeDiagnostics.debug(
                    "Created new tab from bookmark in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        case .url, .search:
            if navigatesCurrentTab,
               let navigationTargetTab
            {
                actions.commitEmptySplitPlaceholder(navigationTargetTab.id, windowState)
                navigationTargetTab.navigateToURL(suggestion.text)
                RuntimeDiagnostics.debug(
                    "Navigated current tab to: \(suggestion.text)",
                    category: "FloatingBar"
                )
            } else {
                let resolved = actions.normalizeURL(suggestion.text)
                actions.createNewTabAfterSidebarInsertion(windowState, resolved)
                RuntimeDiagnostics.debug(
                    "Created new tab in window \(windowState.id)",
                    category: "FloatingBar"
                )
            }
        }
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
