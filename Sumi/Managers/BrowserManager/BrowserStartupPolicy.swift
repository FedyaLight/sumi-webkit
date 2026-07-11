import Foundation
import SumiDomain

/// Chooses one startup behavior. The clean-session and window-restore
/// transactions remain separate so neither path can mutate the other's state.
@MainActor
final class BrowserStartupPolicy {
    private let cleanStartup: CleanStartupWorkflow
    private let windowRestore: StartupWindowRestoreService
    private let startupPageURL: @MainActor () -> URL?

    var startupWindow: BrowserWindowState? {
        cleanStartup.firstRegularWindow
    }

    init(
        cleanStartup: CleanStartupWorkflow,
        windowRestore: StartupWindowRestoreService,
        startupPageURL: @escaping @MainActor () -> URL?
    ) {
        self.cleanStartup = cleanStartup
        self.windowRestore = windowRestore
        self.startupPageURL = startupPageURL
    }

    func apply(_ mode: SumiStartupMode) {
        switch mode {
        case .restorePreviousSession:
            windowRestore.restoreIfNeeded()
        case .nothing:
            cleanStartup.apply(opening: nil)
        case .specificPage:
            cleanStartup.apply(
                opening: startupPageURL() ?? SumiSurface.emptyTabURL
            )
        }
    }
}
