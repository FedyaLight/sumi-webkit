import OSLog

/// Strong, single-quit lease over the live browser runtime. AppDelegate creates
/// it synchronously after confirmation, and the finalizer releases it only
/// after persistence, site cleanup, and WebKit teardown have finished.
@MainActor
final class BrowserTerminationRuntimeLease: BrowserTerminationFinalizing {
    private static let log = Logger.sumi(category: "AppTermination")

    private let browserRuntime: BrowserManager
    private let tabPersistence: TabStructuralPersistenceService
    private let windowPersistence: WindowSessionPersistenceCoordinator
    private let cleanup: BrowserShutdownCleanupService
    private let siteDataPolicy: any BrowserSiteDataPolicyEnforcing
    private let profiles: ProfileManager

    convenience init(browserRuntime: BrowserManager) {
        self.init(
            browserRuntime: browserRuntime,
            tabPersistence: browserRuntime.structuralPersistence,
            windowPersistence: browserRuntime.windowSessionPersistenceCoordinator,
            cleanup: browserRuntime.shutdownCleanupService,
            siteDataPolicy: browserRuntime.dataServices.siteDataPolicyEnforcementService,
            profiles: browserRuntime.profileManager
        )
    }

    init(
        browserRuntime: BrowserManager,
        tabPersistence: TabStructuralPersistenceService,
        windowPersistence: WindowSessionPersistenceCoordinator,
        cleanup: BrowserShutdownCleanupService,
        siteDataPolicy: any BrowserSiteDataPolicyEnforcing,
        profiles: ProfileManager
    ) {
        self.browserRuntime = browserRuntime
        self.tabPersistence = tabPersistence
        self.windowPersistence = windowPersistence
        self.cleanup = cleanup
        self.siteDataPolicy = siteDataPolicy
        self.profiles = profiles
    }

    func finalizeTermination() async {
        Self.log.info("Termination persistence began")
        windowPersistence.flush()
        let didFlushPermissions = await browserRuntime.permissionRuntime
            .flushPermissionPersistence()
        Self.log.info(
            "Permission persistence \(didFlushPermissions ? "succeeded" : "failed")"
        )

        let runtimePersistStart = CFAbsoluteTimeGetCurrent()
        let flushedRuntimeStates = await tabPersistence
            .flushRuntimeStatePersistenceAwaitingResult()
        let runtimePersistDuration = CFAbsoluteTimeGetCurrent() - runtimePersistStart
        Self.log.info(
            "Runtime-state persistence flushed \(flushedRuntimeStates) tab(s) in \(String(format: "%.3f", runtimePersistDuration))s"
        )

        let reconcileStart = CFAbsoluteTimeGetCurrent()
        let didReconcile = await tabPersistence
            .persistFullReconcileAwaitingResult(reason: "app termination")
        let reconcileDuration = CFAbsoluteTimeGetCurrent() - reconcileStart
        Self.log.info(
            "Full reconcile persistence \(didReconcile ? "succeeded" : "failed") in \(String(format: "%.3f", reconcileDuration))s"
        )

        let profileSnapshot = profiles.profiles
        await siteDataPolicy.performAllWindowsClosedCleanup(
            profiles: profileSnapshot
        )
        cleanup.cleanupAllTabs()
        withExtendedLifetime(browserRuntime) {}
        Self.log.info("Termination cleanup completed; WebKit resources released")
    }
}
