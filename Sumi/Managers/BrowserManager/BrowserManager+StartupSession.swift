import Foundation

extension BrowserManager {
    func startPermissionEventObservation() {
        permissionRuntime.startPermissionEventObservation { [weak self] _ in
            await self?.privacyBundle.permissionSidebarPinningOwner.reconcile(reason: "permission-event")
        }
    }

    /// Called when TabManager finishes loading initial data from persistence
    func handleTabManagerDataLoaded() {
        windowSessionService.handleTabManagerDataLoaded(runtime: WindowSessionRuntimeFactory.make(for: self))
        liveFolderManager.startAfterTabRestore(isEnabled: liveFoldersModule.isEnabled)
        reconcileStartupSessionIfPossible()
    }

    func beginProtectionRestoreForStartupIfNeeded() {
        startupProtectionRuntime.beginProtectionRestoreForStartupIfNeeded()
    }

    func reconcileStartupSessionIfPossible() {
        startupSessionRestoreOwner.reconcileIfReady(
            hasLoadedInitialTabData: { [weak self] in
                self?.tabManager.hasLoadedInitialData ?? false
            },
            startupMode: { [weak self] in
                self?.sumiSettings?.startupMode
            },
            startupWindow: { [weak self] in
                self?.profileLifecycleBundle.startupPolicyOwner.firstRegularWindowForStartupPolicy
            },
            applyStartupPolicy: { [weak self] mode in
                self?.profileLifecycleBundle.startupPolicyOwner.applyStartupPolicy(mode)
            }
        )
    }
}
