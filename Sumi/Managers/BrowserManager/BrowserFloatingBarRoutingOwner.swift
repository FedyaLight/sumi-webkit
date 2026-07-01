import Foundation

@MainActor
final class BrowserFloatingBarRoutingOwner {
    struct Dependencies {
        let tabOpeningOwner: @MainActor @Sendable () -> BrowserTabOpeningOwner
        let windowRegistry: @MainActor @Sendable () -> WindowRegistry?
        let settings: @MainActor @Sendable () -> SumiSettingsService?
        let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
        let hasValidCurrentSelection: @MainActor @Sendable (BrowserWindowState) -> Bool
        let cancelEmptySplitPlaceholder: @MainActor @Sendable (BrowserWindowState) -> Void
        let commitEmptySplitPlaceholder: @MainActor @Sendable (UUID, BrowserWindowState) -> Void
        let replaceEmptySplitPlaceholder: @MainActor @Sendable (Tab, BrowserWindowState) -> Bool
        let selectTab: @MainActor @Sendable (Tab, BrowserWindowState) -> Void
        let loadCurrentPageURL: @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void
        let navigateCurrentPage: @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void
        let dismissWorkspaceThemePickerIfNeededDiscarding: @MainActor @Sendable () -> Void
        let persistWindowSession: @MainActor @Sendable (BrowserWindowState) -> Void
        let schedulePersistWindowSession: @MainActor @Sendable (BrowserWindowState, UInt64) -> Void
    }

    private let dependencies: Dependencies
    private let navigationOwner = FloatingBarNavigationOwner()

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func focusFloatingBarForActiveWindow(
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        navigationOwner.focusActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: actions
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool,
        presentationReason: FloatingBarPresentationReason
    ) {
        navigationOwner.focus(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason,
            actions: actions
        )
    }

    func showNewTabFloatingBar(in windowState: BrowserWindowState) {
        navigationOwner.showNewTab(
            in: windowState,
            actions: actions
        )
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        navigationOwner.openNewTabSurface(
            in: windowState,
            actions: actions
        )
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        navigationOwner.updateDraft(
            in: windowState,
            text: text,
            actions: actions
        )
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool
    ) {
        navigationOwner.dismiss(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder,
            actions: actions
        )
    }

    func dismissFloatingBarForActiveWindow(preserveDraft: Bool) {
        navigationOwner.dismissActiveWindow(
            preserveDraft: preserveDraft,
            actions: actions
        )
    }

    @discardableResult
    func dismissFloatingBarIfVisible(
        in windowId: UUID,
        preserveDraft: Bool
    ) -> Bool {
        navigationOwner.dismissIfVisible(
            in: windowId,
            preserveDraft: preserveDraft,
            actions: actions
        )
    }

    func floatingBarCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        navigationOwner.commitNavigatesCurrentTab(
            in: windowState,
            actions: actions
        )
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        navigationOwner.commitSuggestion(
            suggestion,
            in: windowState,
            actions: actions
        )
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        navigationOwner.commitNavigation(
            to: urlString,
            in: windowState,
            actions: actions
        )
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        navigationOwner.openSuggestion(
            suggestion,
            in: windowState,
            actions: actions
        )
    }

    func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        navigationOwner.dismissAfterSelection(
            in: windowState,
            actions: actions
        )
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        navigationOwner.sanitize(
            in: windowState,
            hasValidCurrentSelection: dependencies.hasValidCurrentSelection(windowState),
            actions: actions
        )
    }

    private var actions: FloatingBarNavigationOwner.Actions {
        FloatingBarNavigationOwner.Actions(
            activeWindow: {
                self.dependencies.windowRegistry()?.activeWindow
            },
            window: { windowId in
                self.dependencies.windowRegistry()?.windows[windowId]
            },
            activePageTab: dependencies.activePageTab,
            cancelEmptySplitPlaceholder: dependencies.cancelEmptySplitPlaceholder,
            commitEmptySplitPlaceholder: dependencies.commitEmptySplitPlaceholder,
            replaceEmptySplitPlaceholder: dependencies.replaceEmptySplitPlaceholder,
            selectTab: dependencies.selectTab,
            createNewTab: { [weak self] windowState, url in
                self?.dependencies.tabOpeningOwner().createNewTab(in: windowState, url: url)
            },
            createNewTabAfterSidebarInsertion: { [weak self] windowState, url in
                self?.dependencies.tabOpeningOwner().createNewTabAfterSidebarInsertion(in: windowState, url: url)
            },
            configuredNewTabPageURL: {
                guard let settings = self.dependencies.settings(),
                      settings.newTabMode == .specificPage
                else {
                    return nil
                }
                return settings.resolvedNewTabPageURL.absoluteString
            },
            normalizeURL: { text in
                let template = self.dependencies.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                return Sumi.normalizeURL(text, queryTemplate: template)
            },
            loadCurrentPageURL: dependencies.loadCurrentPageURL,
            navigateCurrentPage: dependencies.navigateCurrentPage,
            applySettingsSurfaceNavigation: { text in
                let template = self.dependencies.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                let normalized = Sumi.normalizeURL(text, queryTemplate: template)
                guard let url = URL(string: normalized),
                      SumiSurface.isSettingsSurfaceURL(url)
                else { return }
                self.dependencies.settings()?.applyNavigationFromSettingsSurfaceURL(url)
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: dependencies.dismissWorkspaceThemePickerIfNeededDiscarding,
            persistWindowSession: dependencies.persistWindowSession,
            schedulePersistWindowSession: { windowState in
                self.dependencies.schedulePersistWindowSession(windowState, 450_000_000)
            }
        )
    }
}

extension BrowserFloatingBarRoutingOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let tabLifecycleService = browserManager.tabLifecycleService
        return Self(
            tabOpeningOwner: { tabLifecycleService.opening },
            windowRegistry: { [weak browserManager] in browserManager?.windowRegistry },
            settings: { [weak browserManager] in browserManager?.sumiSettings },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.activePageTab(for: windowState)
            },
            hasValidCurrentSelection: { [weak browserManager] windowState in
                browserManager?.hasValidCurrentSelection(in: windowState) ?? false
            },
            cancelEmptySplitPlaceholder: { [weak browserManager] windowState in
                browserManager?.splitManager.cancelEmptySplitPlaceholder(in: windowState)
            },
            commitEmptySplitPlaceholder: { [weak browserManager] tabId, windowState in
                browserManager?.splitManager.commitEmptySplitPlaceholder(tabId: tabId, in: windowState)
            },
            replaceEmptySplitPlaceholder: { [weak browserManager] tab, windowState in
                browserManager?.splitManager.replaceEmptySplitPlaceholder(with: tab, in: windowState) ?? false
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            loadCurrentPageURL: { [weak browserManager] tab, windowState, urlString in
                browserManager?.loadFloatingBarCurrentPage(
                    urlString,
                    tab: tab,
                    in: windowState
                )
            },
            navigateCurrentPage: { [weak browserManager] tab, windowState, input in
                browserManager?.navigateFloatingBarCurrentPage(
                    input,
                    tab: tab,
                    in: windowState
                )
            },
            dismissWorkspaceThemePickerIfNeededDiscarding: { [weak browserManager] in
                browserManager?.dismissWorkspaceThemePickerIfNeededDiscarding()
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            },
            schedulePersistWindowSession: { [weak browserManager] windowState, delayNanoseconds in
                browserManager?.schedulePersistWindowSession(
                    for: windowState,
                    delayNanoseconds: delayNanoseconds
                )
            }
        )
    }
}
