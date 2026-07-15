import Foundation

/// Owns tab-identity commits that may replace an empty split placeholder or
/// fall back to the browser's exact tab-selection transaction.
@MainActor
final class FloatingBarTabTargetCommitter {
    private let splitPlaceholders:
        @MainActor () -> (any FloatingBarSplitPlaceholderHandling)?
    private let selectTab: @MainActor (
        Tab,
        BrowserWindowState
    ) -> BrowserTabSelectionOutcome

    init(
        splitPlaceholders: @escaping @MainActor
            () -> (any FloatingBarSplitPlaceholderHandling)?,
        selectTab: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> BrowserTabSelectionOutcome
    ) {
        self.splitPlaceholders = splitPlaceholders
        self.selectTab = selectTab
    }

    func select(_ tab: Tab, in windowState: BrowserWindowState) -> Bool {
        if splitPlaceholders()?.replace(with: tab, in: windowState) == true {
            return true
        }
        return selectTab(tab, windowState).wasCommitted
    }

    func commitPlaceholder(for tab: Tab, in windowID: UUID) {
        splitPlaceholders()?.commit(tab, in: windowID)
    }
}
