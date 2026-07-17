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
}
