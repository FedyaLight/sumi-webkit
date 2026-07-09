import Foundation

extension BrowserManager {
    // MARK: - Find Bar Routing

    func showFindBar() {
        let session = urlBarBundle.activePageRoutingOwner.activeFindSession()
        findManager.showFindBar(for: session.tab, in: session.windowId)
    }

    func updateFindManagerCurrentTab() {
        let session = urlBarBundle.activePageRoutingOwner.activeFindSession()
        findManager.updateCurrentTab(session.tab, in: session.windowId)
    }
}
