import Foundation

@MainActor
extension BrowserManager {
    var floatingBarBrowserContext: FloatingBarBrowserContext {
        floatingBarBrowserContextOwner.context
    }

    func focusFloatingBarForActiveWindow(
        prefill: String = "",
        navigateCurrentTab: Bool = false,
        presentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        floatingBarRoutingOwner.focusFloatingBarForActiveWindow(
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String = "",
        navigateCurrentTab: Bool = false,
        presentationReason: FloatingBarPresentationReason = .keyboard
    ) {
        floatingBarRoutingOwner.focusFloatingBar(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: presentationReason
        )
    }

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        focusFloatingBar(
            in: windowState,
            prefill: prefill,
            navigateCurrentTab: navigateCurrentTab,
            presentationReason: .keyboard
        )
    }

    func showNewTabFloatingBar(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.showNewTabFloatingBar(in: windowState)
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.openNewTabOrFloatingBar(in: windowState)
    }

    func updateFloatingBarDraft(
        in windowState: BrowserWindowState,
        text: String
    ) {
        floatingBarRoutingOwner.updateFloatingBarDraft(
            in: windowState,
            text: text
        )
    }

    func dismissFloatingBar(
        in windowState: BrowserWindowState,
        preserveDraft: Bool,
        cancelEmptySplitPlaceholder: Bool = true
    ) {
        floatingBarRoutingOwner.dismissFloatingBar(
            in: windowState,
            preserveDraft: preserveDraft,
            cancelEmptySplitPlaceholder: cancelEmptySplitPlaceholder
        )
    }

    func dismissFloatingBarForActiveWindow(preserveDraft: Bool = true) {
        floatingBarRoutingOwner.dismissFloatingBarForActiveWindow(preserveDraft: preserveDraft)
    }

    @discardableResult
    func dismissFloatingBarIfVisible(
        in windowId: UUID,
        preserveDraft: Bool = true
    ) -> Bool {
        floatingBarRoutingOwner.dismissFloatingBarIfVisible(
            in: windowId,
            preserveDraft: preserveDraft
        )
    }

    func floatingBarCommitNavigatesCurrentTab(in windowState: BrowserWindowState) -> Bool {
        floatingBarRoutingOwner.floatingBarCommitNavigatesCurrentTab(in: windowState)
    }

    func commitFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        floatingBarRoutingOwner.commitFloatingBarSuggestion(
            suggestion,
            in: windowState
        )
    }

    func commitFloatingBarNavigation(
        to urlString: String,
        in windowState: BrowserWindowState
    ) {
        floatingBarRoutingOwner.commitFloatingBarNavigation(
            to: urlString,
            in: windowState
        )
    }

    func openFloatingBarSuggestion(
        _ suggestion: SearchManager.SearchSuggestion,
        in windowState: BrowserWindowState
    ) {
        floatingBarRoutingOwner.openFloatingBarSuggestion(
            suggestion,
            in: windowState
        )
    }

    func dismissFloatingBarAfterSelection(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.dismissFloatingBarAfterSelection(in: windowState)
    }

    func sanitizeFloatingBarState(in windowState: BrowserWindowState) {
        floatingBarRoutingOwner.sanitizeFloatingBarState(in: windowState)
    }
}
