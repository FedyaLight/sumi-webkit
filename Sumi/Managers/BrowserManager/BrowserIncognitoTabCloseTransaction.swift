import Foundation

@MainActor
final class BrowserIncognitoTabCloseTransaction {
    private let selection: BrowserTabSelectionOwner

    init(selection: BrowserTabSelectionOwner) {
        self.selection = selection
    }

    func close(_ tab: Tab, in windowState: BrowserWindowState) {
        tab.performComprehensiveWebViewCleanup()
        windowState.removeEphemeralTab(id: tab.id)

        if let nextTab = windowState.ephemeralTabs.last {
            _ = selection.selectTab(
                nextTab,
                in: windowState,
                loadPolicy: .immediate
            )
        } else {
            showEmptyState(in: windowState)
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        selection.showEmptyState(in: windowState)
    }
}
