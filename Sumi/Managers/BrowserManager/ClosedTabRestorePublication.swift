import Foundation

@MainActor
final class ClosedTabRestorePublication {
    private let activeSelection: TabActiveSelectionOwner
    private let browserSelection: BrowserTabSelectionOwner

    init(
        activeSelection: TabActiveSelectionOwner,
        browserSelection: BrowserTabSelectionOwner
    ) {
        self.activeSelection = activeSelection
        self.browserSelection = browserSelection
    }

    func publish(_ tab: Tab, in windowState: BrowserWindowState?) {
        guard let windowState else {
            activeSelection.setActiveTab(tab)
            return
        }
        _ = browserSelection.selectTab(
            tab,
            in: windowState,
            loadPolicy: .immediate
        )
    }
}
