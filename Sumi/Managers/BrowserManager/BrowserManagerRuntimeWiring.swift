import Combine
import Foundation

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        attachShellRuntime(to: browserManager)
        browserManager.compositorManager.attach(runtime: .make(browserManager: browserManager))
        let tabRuntimeCompositionCancellable = BrowserTabRuntimeCompositionService.attach(
            to: browserManager
        )
        let runtimePortRegistry = BrowserTabManagerRuntimePortsFactory.registry(for: browserManager)
        browserManager.tabManager.runtimePortsAttachmentOwner.attach(runtimePortRegistry)
        // Live Folders runtime attaches only when the module is enabled (W4/R9),
        // via OptionalModuleHost.attachEnabled.
        browserManager.downloadManager.retryRuntime = BrowserDownloadRetryRuntimeFactory.runtime(for: browserManager)
        browserManager.optionalModules.attachEnabled(into: browserManager)
        browserManager.glanceManager.attach(
            runtime: BrowserGlanceRuntimeService.runtime(for: browserManager)
        )
        browserManager.authenticationManager.attach(
            runtime: BrowserAuthenticationRuntimeFactory.runtime(for: browserManager)
        )
        return tabRuntimeCompositionCancellable
    }

    private static func attachShellRuntime(to browserManager: BrowserManager) {
        browserManager.shellRuntime.attach(
            adoptWebViewCoordinator: { [weak browserManager] coordinator in
                guard let browserManager, let coordinator else { return }
                precondition(
                    coordinator.webViewSessions === browserManager.webViewSessions,
                    "Browser session and coordinator must share one WebView repository"
                )
                coordinator.runtimeContextStore.attach(
                    BrowserWebViewRuntimeFactory.environment(for: browserManager)
                )
                coordinator.websiteDataCleanupService.registerExtensionRuntime {
                    [weak browserManager] profileIDs in
                    guard let browserManager else { return false }
                    return browserManager.optionalModules.extensions
                        .quiesceForWebsiteDataMutation(profileIDs: profileIDs)
                }
                startPersistedStateLoadIfShellReady(browserManager)
            },
            setDestructiveCleanupPreparer: { [weak browserManager] coordinator in
                guard let browserManager else { return }
                let cleanupService = coordinator?.websiteDataCleanupService
                browserManager.browsingDataCleanupService.destructiveCleanupPreparer = cleanupService
                browserManager.dataServices.automaticBrowsingDataCleanupService
                    .attachDestructiveCleanupPreparer(cleanupService)
                browserManager.dataServices.siteDataPolicyEnforcementService
                    .attachDestructiveCleanupPreparer(cleanupService)
                browserManager.dataServices.privacyService
                    .attachDestructiveCleanupPreparer(cleanupService)
                browserManager.dataServices.profileWebsiteDataMutationService
                    .attachDestructiveCleanupPreparer(cleanupService)
            },
            windowRegistryChanged: { [weak browserManager] registry in
                guard let browserManager else { return }
                browserManager.glanceManager.windowRegistry = registry
                Task { @MainActor [weak browserManager] in
                    await browserManager?.privacyBundle.permissionSidebarPinningOwner.reconcile(
                        reason: "window-registry-updated"
                    )
                }
                browserManager.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: "window-registry-updated"
                )
                browserManager.reconcileStartupSessionIfPossible()
                startPersistedStateLoadIfShellReady(browserManager)
            }
        )
    }

    private static func startPersistedStateLoadIfShellReady(
        _ browserManager: BrowserManager
    ) {
        guard browserManager.webViewCoordinator != nil,
              browserManager.windowRegistry != nil else { return }
        let tabManager = browserManager.tabManager
        tabManager.startupRestoreLifecycle.startIfNeeded(
            runtimeIsAttached: tabManager.runtimePorts != nil,
            restore: { [weak tabManager] revision in
                tabManager?.storeRestore.loadFromStore(
                    expectedStructuralRevision: revision
                )
            }
        )
    }

    static func tabSelectionRuntimeNotifications(
        for browserManager: BrowserManager
    ) -> BrowserTabSelectionOwner.RuntimeNotifications {
        BrowserTabRuntimeCompositionService.tabSelectionRuntimeNotifications(
            for: browserManager
        )
    }

    static func nativeNowPlayingRuntimeContext(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingRuntimeContext {
        BrowserNativeNowPlayingRuntimeFactory.context(for: browserManager)
    }
}
