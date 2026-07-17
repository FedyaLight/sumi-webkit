import Foundation

@MainActor
final class BrowserInitialWindowDataSettlement {
    private let windows: WindowRegistry
    private let restore: WindowSessionRestoreService
    private let restoration: BrowserWindowSessionRestorationService
    private let activation: BrowserWindowActivationService

    init(
        windows: WindowRegistry,
        restore: WindowSessionRestoreService,
        restoration: BrowserWindowSessionRestorationService,
        activation: BrowserWindowActivationService
    ) {
        self.windows = windows
        self.restore = restore
        self.restoration = restoration
        self.activation = activation
    }

    func settle() {
        let registeredWindows = windows.allWindows
        restore.handleTabManagerDataLoaded(windows: registeredWindows)
        restoration.completePendingRegistrations(
            registeredWindows: registeredWindows
        )
        activation.completeDeferredActivation(for: windows.activeWindow)
    }
}
