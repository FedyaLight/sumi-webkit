import Foundation
import SumiDomain

@MainActor
final class BrowserFloatingBarRoutingOwner {
    private let tabOpeningOwner: @MainActor @Sendable () -> BrowserTabOpeningOwner
    private let windowRegistry: @MainActor @Sendable () -> WindowRegistry?
    private let settings: @MainActor @Sendable () -> SumiSettingsService?
    private let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
    private let hasValidCurrentSelection: @MainActor @Sendable (BrowserWindowState) -> Bool
    private let cancelEmptySplitPlaceholder: @MainActor @Sendable (BrowserWindowState) -> Void
    private let commitEmptySplitPlaceholder: @MainActor @Sendable (UUID, BrowserWindowState) -> Void
    private let replaceEmptySplitPlaceholder: @MainActor @Sendable (Tab, BrowserWindowState) -> Bool
    private let selectTab: @MainActor @Sendable (Tab, BrowserWindowState) -> Void
    private let loadCurrentPageURL: @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void
    private let navigateCurrentPage: @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void
    private let dismissThemePickerDiscardingIfNeeded: @MainActor @Sendable () -> Void
    private let persistWindowSession: @MainActor @Sendable (BrowserWindowState) -> Void
    private let schedulePersistWindowSession: @MainActor @Sendable (BrowserWindowState, UInt64) -> Void
    private let navigationOwner = FloatingBarNavigationOwner()

    init(
        tabOpeningOwner: @escaping @MainActor @Sendable () -> BrowserTabOpeningOwner,
        windowRegistry: @escaping @MainActor @Sendable () -> WindowRegistry?,
        settings: @escaping @MainActor @Sendable () -> SumiSettingsService?,
        activePageTab: @escaping @MainActor @Sendable (BrowserWindowState) -> Tab?,
        hasValidCurrentSelection: @escaping @MainActor @Sendable (BrowserWindowState) -> Bool,
        cancelEmptySplitPlaceholder: @escaping @MainActor @Sendable (BrowserWindowState) -> Void,
        commitEmptySplitPlaceholder: @escaping @MainActor @Sendable (UUID, BrowserWindowState) -> Void,
        replaceEmptySplitPlaceholder: @escaping @MainActor @Sendable (Tab, BrowserWindowState) -> Bool,
        selectTab: @escaping @MainActor @Sendable (Tab, BrowserWindowState) -> Void,
        loadCurrentPageURL: @escaping @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void,
        navigateCurrentPage: @escaping @MainActor @Sendable (Tab, BrowserWindowState, String) -> Void,
        dismissThemePickerDiscardingIfNeeded: @escaping @MainActor @Sendable () -> Void,
        persistWindowSession: @escaping @MainActor @Sendable (BrowserWindowState) -> Void,
        schedulePersistWindowSession: @escaping @MainActor @Sendable (BrowserWindowState, UInt64) -> Void
    ) {
        self.tabOpeningOwner = tabOpeningOwner
        self.windowRegistry = windowRegistry
        self.settings = settings
        self.activePageTab = activePageTab
        self.hasValidCurrentSelection = hasValidCurrentSelection
        self.cancelEmptySplitPlaceholder = cancelEmptySplitPlaceholder
        self.commitEmptySplitPlaceholder = commitEmptySplitPlaceholder
        self.replaceEmptySplitPlaceholder = replaceEmptySplitPlaceholder
        self.selectTab = selectTab
        self.loadCurrentPageURL = loadCurrentPageURL
        self.navigateCurrentPage = navigateCurrentPage
        self.dismissThemePickerDiscardingIfNeeded = dismissThemePickerDiscardingIfNeeded
        self.persistWindowSession = persistWindowSession
        self.schedulePersistWindowSession = schedulePersistWindowSession
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
            hasValidCurrentSelection: hasValidCurrentSelection(windowState),
            actions: actions
        )
    }

    private var actions: FloatingBarNavigationOwner.Actions {
        FloatingBarNavigationOwner.Actions(
            activeWindow: {
                self.windowRegistry()?.activeWindow
            },
            window: { windowId in
                self.windowRegistry()?.windows[windowId]
            },
            activePageTab: activePageTab,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder,
            commitEmptySplitPlaceholder: commitEmptySplitPlaceholder,
            replaceEmptySplitPlaceholder: replaceEmptySplitPlaceholder,
            selectTab: selectTab,
            createNewTab: { [weak self] windowState, url in
                self?.tabOpeningOwner().createNewTab(in: windowState, url: url)
            },
            createNewTabAfterSidebarInsertion: { [weak self] windowState, url in
                self?.tabOpeningOwner().createNewTabAfterSidebarInsertion(in: windowState, url: url)
            },
            configuredNewTabPageURL: {
                guard let settings = self.settings(),
                      settings.newTabMode == .specificPage
                else {
                    return nil
                }
                return settings.resolvedNewTabPageURL.absoluteString
            },
            normalizeURL: { text in
                let template = self.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                return normalizeURL(text, queryTemplate: template)
            },
            loadCurrentPageURL: loadCurrentPageURL,
            navigateCurrentPage: navigateCurrentPage,
            applySettingsSurfaceNavigation: { text in
                let template = self.settings()?.resolvedSearchEngineTemplate
                    ?? SearchProvider.google.queryTemplate
                let normalized = normalizeURL(text, queryTemplate: template)
                guard let url = URL(string: normalized),
                      SumiSurface.isSettingsSurfaceURL(url)
                else { return }
                self.settings()?.applyNavigationFromSettingsSurfaceURL(url)
            },
            dismissThemePickerDiscardingIfNeeded: dismissThemePickerDiscardingIfNeeded,
            persistWindowSession: persistWindowSession,
            schedulePersistWindowSession: { windowState in
                self.schedulePersistWindowSession(windowState, 450_000_000)
            }
        )
    }
}
