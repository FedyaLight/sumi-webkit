import Foundation

@MainActor
final class BrowserTabCloseRouting {
    private let regularTabs: BrowserRegularTabCloseTransaction
    private let incognitoTabs: BrowserIncognitoTabCloseTransaction
    private let shortcutTabs: ShortcutLiveTabCloseService

    init(
        regularTabs: BrowserRegularTabCloseTransaction,
        incognitoTabs: BrowserIncognitoTabCloseTransaction,
        shortcutTabs: ShortcutLiveTabCloseService
    ) {
        self.regularTabs = regularTabs
        self.incognitoTabs = incognitoTabs
        self.shortcutTabs = shortcutTabs
    }

    func close(_ tab: Tab, in windowState: BrowserWindowState) {
        if windowState.isIncognito {
            incognitoTabs.close(tab, in: windowState)
        } else if tab.isShortcutLiveInstance {
            shortcutTabs.close(tab, in: windowState)
        } else {
            regularTabs.close(tab, in: windowState)
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        incognitoTabs.showEmptyState(in: windowState)
    }
}
