import Foundation

@MainActor
final class BrowserCurrentTabCloseContext {
    private let windows: WindowRegistry
    private let tabs: BrowserWindowTabContext

    init(
        windows: WindowRegistry,
        tabs: BrowserWindowTabContext
    ) {
        self.windows = windows
        self.tabs = tabs
    }

    var activeWindow: BrowserWindowState? {
        windows.activeWindow
    }

    func currentTab(in windowState: BrowserWindowState) -> Tab? {
        tabs.currentTab(for: windowState)
    }

    func currentCloseTargets(in windowState: BrowserWindowState) -> [Tab] {
        let splitTabs = tabs.currentSplitTabs(in: windowState)
        if splitTabs.isEmpty == false {
            return splitTabs
        }
        return currentTab(in: windowState).map { [$0] } ?? []
    }
}
