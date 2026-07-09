import Foundation

@MainActor
protocol TabExtensionLifecyclePort {
    func notifyTabClosedIfLoaded(_ tab: Tab)
    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?)
}

@MainActor
struct LiveTabExtensionLifecyclePort: TabExtensionLifecyclePort {
    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
            newTab: newTab,
            previous: previous
        )
    }
}
