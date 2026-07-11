import Foundation

extension BrowserManager {
    func reconcileStartupSessionIfPossible() {
        startupSessionRestoreOwner.reconcileIfReady(
            hasLoadedInitialTabData: { [weak self] in
                self?.tabManager.startupRestoreLifecycle.hasLoadedInitialData ?? false
            },
            startupMode: { [weak self] in
                self?.sumiSettings?.startupMode
            },
            startupWindow: { [weak self] in
                self?.profileLifecycleBundle.startupPolicy.startupWindow
            },
            applyStartupPolicy: { [weak self] mode in
                self?.profileLifecycleBundle.startupPolicy.apply(mode)
            }
        )
    }

    /// Called when TabManager finishes loading initial data from persistence
    func handleTabManagerDataLoaded() {
        let registeredWindows = windowRegistry?.allWindows ?? []
        windowSessionBundle.restoreService.handleTabManagerDataLoaded(
            windows: registeredWindows
        )
        windowSessionBundle.restoration.completePendingRegistrations(
            registeredWindows: registeredWindows
        )
        windowSessionBundle.activation.completeDeferredActivation(
            for: windowRegistry?.activeWindow
        )
        liveFolderManager.startAfterTabRestore(
            isEnabled: optionalModules.liveFolders.isEnabled
        )
        reconcileStartupSessionIfPossible()
    }
}
