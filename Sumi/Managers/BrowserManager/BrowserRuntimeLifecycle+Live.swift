import Foundation

extension BrowserRuntimeLifecycle {
    @MainActor
    static func live(
        browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> BrowserRuntimeLifecycle {
        let runtimeGraphSubscription = BrowserManagerRuntimeWiring.attach(
            to: browserManager,
            splitQuery: splitQuery
        )
        let windowSessions = browserManager.windowSessionBundle
        return BrowserRuntimeLifecycle(
            permissionObservation: BrowserRuntimePermissionObservation(
                permissionRuntime: browserManager.permissionRuntime,
                sidebarPinning: browserManager.privacyBundle
                    .permissionSidebarPinningOwner
            ),
            startupObservation: BrowserRuntimeStartupObservation(
                tabStructureEvents: browserManager.tabStructureEventBus,
                initialDataSettlement: BrowserInitialTabDataLoadedSettlement(
                    windows: BrowserInitialWindowDataSettlement(
                        windows: browserManager.windowRegistry,
                        restore: windowSessions.restoreService,
                        restoration: windowSessions.restoration,
                        activation: browserManager.windowActivation
                    ),
                    liveFolders: browserManager.liveFolderManager,
                    liveFoldersModule: browserManager.optionalModules.liveFolders,
                    startupReconciliation: browserManager
                        .startupSessionReconciliation
                ),
                protectionRestore: browserManager.startupProtectionRuntime
            ),
            retentionObservation: BrowserRuntimeRetentionObservation(
                automaticCleanup: browserManager.privacyBundle
                    .automaticBrowsingDataCleanup
            ),
            backgroundMedia: browserManager
                .backgroundMediaOptimizationService,
            tabRuntime: browserManager.tabRuntimeLifecycle,
            runtimeSubscription: runtimeGraphSubscription
        )
    }
}
