import Foundation

@MainActor
protocol BrowserStartupSessionReconciling: AnyObject {
    func reconcileStartupSessionIfPossible()
}

extension BrowserManager: BrowserStartupSessionReconciling {}

/// Restores a newly registered window and publishes its creation only after
/// its persisted state has been reconciled.
@MainActor
final class BrowserWindowSessionRestorationService {
    private let restoration: WindowSessionRestoreService
    private let extensions: SumiExtensionsModule
    private weak var profileSupport: (any SumiProfileRoutingSupport)?
    private weak var startupSessions: (any BrowserStartupSessionReconciling)?

    init(
        restoration: WindowSessionRestoreService,
        extensions: SumiExtensionsModule,
        profileSupport: any SumiProfileRoutingSupport,
        startupSessions: any BrowserStartupSessionReconciling
    ) {
        self.restoration = restoration
        self.extensions = extensions
        self.profileSupport = profileSupport
        self.startupSessions = startupSessions
    }

    func restore(_ windowState: BrowserWindowState) {
        restoration.setupWindowState(
            windowState,
            currentProfile: profileSupport?.currentProfile
        )
        extensions.notifyWindowOpenedIfLoaded(windowState)
        startupSessions?.reconcileStartupSessionIfPossible()
    }
}
