import Combine
import Foundation

extension BrowserRuntimeLifecycle {
    @MainActor
    static func live(
        browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> BrowserRuntimeLifecycle {
        let windowSessions = browserManager.windowSessionBundle
        return BrowserRuntimeLifecycle(
            permissionObservation: BrowserRuntimePermissionObservation(
                permissionRuntime: browserManager.permissionRuntime,
                sidebarPinning: browserManager.privacyBundle
                    .permissionSidebarPinningOwner
            ),
            startupObservation: BrowserRuntimeStartupObservation(
                tabStructureEvents: browserManager.tabStructureEventBus,
                windows: browserManager.windowRegistry,
                windowRestore: windowSessions.restoreService,
                windowRestoration: windowSessions.restoration,
                windowActivation: browserManager.windowActivation,
                liveFolders: browserManager.liveFolderManager,
                liveFoldersModule: browserManager.optionalModules.liveFolders,
                startupReconciliation: browserManager
                    .startupSessionReconciliation,
                protectionRestore: browserManager.startupProtectionRuntime
            ),
            retentionObservation: BrowserRuntimeRetentionObservation(
                automaticCleanup: browserManager.privacyBundle
                    .automaticBrowsingDataCleanup
            ),
            tabRuntime: browserManager.tabRuntimeLifecycle,
            attachRuntime: { [weak browserManager] in
                guard let browserManager else {
                    return AnyCancellable {}
                }
                return BrowserManagerRuntimeWiring.attach(
                    to: browserManager,
                    splitQuery: splitQuery
                )
            }
        )
    }
}
