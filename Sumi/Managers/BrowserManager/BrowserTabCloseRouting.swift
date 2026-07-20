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

    func close(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        presentNotification: Bool = true
    ) -> Bool {
        if windowState.isIncognito {
            incognitoTabs.close(tab, in: windowState)
            return true
        } else if tab.isShortcutLiveInstance {
            return shortcutTabs.close(
                tab,
                in: windowState,
                presentNotification: presentNotification
            )
        } else {
            return regularTabs.close(
                tab,
                in: windowState,
                presentNotification: presentNotification
            )
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        incognitoTabs.showEmptyState(in: windowState)
    }
}
