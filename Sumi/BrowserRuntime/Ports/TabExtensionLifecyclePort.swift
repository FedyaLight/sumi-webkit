import Foundation

@MainActor
protocol TabExtensionLifecyclePort {
    func notifyTabClosedIfLoaded(_ tab: Tab)
    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?)
}

@MainActor
struct LiveTabExtensionLifecyclePort: TabExtensionLifecyclePort {
    private let runtime: BrowserManagerRuntimeReference

    init(runtime: BrowserManagerRuntimeReference) {
        self.runtime = runtime
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        runtime.require().optionalModules.extensions.notifyTabClosedIfLoaded(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        runtime.require().optionalModules.extensions.notifyTabActivatedIfLoaded(
            newTab: newTab,
            previous: previous
        )
    }
}
