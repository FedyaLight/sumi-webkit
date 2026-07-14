import Foundation

@MainActor
protocol TabExtensionLifecyclePort {
    func notifyTabClosedIfLoaded(_ tab: Tab)
    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?)
}

@MainActor
struct LiveTabExtensionLifecyclePort: TabExtensionLifecyclePort {
    private let extensions: SumiExtensionRuntimeSurface

    init(extensions: SumiExtensionRuntimeSurface) {
        self.extensions = extensions
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        extensions.notifyTabClosed(tab)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        extensions.notifyTabActivated(
            newTab: newTab,
            previous: previous
        )
    }
}
