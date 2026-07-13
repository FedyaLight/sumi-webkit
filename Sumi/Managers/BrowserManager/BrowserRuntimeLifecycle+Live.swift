import Foundation

extension BrowserRuntimeLifecycle {
    /// Composes the process lifecycle against the live browser graph. Only
    /// `BrowserManager` — the object whose init/deinit bound the runtime's
    /// lifetime — builds and holds the result; nothing else can reach it.
    @MainActor
    static func live(browserManager: BrowserManager) -> BrowserRuntimeLifecycle {
        // Whole capabilities pass as direct references (not weak browserManager
        // hops) so shutdown still reaches them while BrowserManager itself is
        // deinitializing; only cross-subsystem signal routing stays closure-shaped.
        // Runtime graph attachments have BrowserManager process lifetime. The
        // returned subscription is the only detachable resource and is owned
        // by the lifecycle below.
        let runtimeGraphSubscription = BrowserManagerRuntimeWiring.attach(
            to: browserManager
        )
        return BrowserRuntimeLifecycle(
            tabStructureEventBus: browserManager.tabManager.tabStructureEventBus,
            permissionObservation: browserManager.permissionRuntime,
            onPermissionEvent: { [weak browserManager] _ in
                await browserManager?.privacyBundle.permissionSidebarPinningOwner
                    .reconcile(reason: "permission-event")
            },
            protectionRestore: browserManager.startupProtectionRuntime,
            backgroundMediaOptimization: browserManager.backgroundMediaOptimizationService,
            runtimeGraphSubscription: runtimeGraphSubscription,
            handleTabManagerDataLoaded: { [weak browserManager] in
                browserManager?.handleTabManagerDataLoaded()
            },
            scheduleBrowsingDataRetentionCleanup: { [weak browserManager] in
                browserManager?.privacyBundle.automaticDataCleanupOwner
                    .scheduleAutomaticBrowsingDataCleanup(
                    reason: "retention-setting-changed",
                    force: true,
                    delayNanoseconds: 0
                )
            }
        )
    }
}
