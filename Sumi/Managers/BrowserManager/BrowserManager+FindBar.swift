import Foundation

extension BrowserManager {
    // MARK: - Find Bar Routing

    func showFindBar() {
        let page = shellRuntime.activePageResolver.resolveActiveWindow()
        findManager.showFindBar(for: page?.tab, in: page?.windowState.id)
    }

    func updateFindManagerCurrentTab() {
        let page = shellRuntime.activePageResolver.resolveActiveWindow()
        findManager.updateCurrentTab(page?.tab, in: page?.windowState.id)
    }
}
