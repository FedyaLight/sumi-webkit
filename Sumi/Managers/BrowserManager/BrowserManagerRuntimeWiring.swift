import Combine
import Foundation

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(to browserManager: BrowserManager) -> AnyCancellable {
        precondition(
            browserManager.tabManager.runtimePortsAttachmentOwner.canAttach,
            "Browser tab runtime ports must attach exactly once"
        )
        attachWebViewRuntime(to: browserManager)
        attachShellRuntime(to: browserManager)
        browserManager.compositorManager.attach(runtime: .make(browserManager: browserManager))
        let tabRuntimeCompositionCancellable = BrowserTabRuntimeCompositionService.attach(
            to: browserManager
        )
        let runtimePortRegistry = BrowserTabManagerRuntimePortsFactory.registry(
            for: browserManager
        )
        precondition(
            browserManager.tabManager.runtimePortsAttachmentOwner.attach(
                runtimePortRegistry
            ) == .attached,
            "Browser tab runtime ports must attach exactly once"
        )
        startPersistedStateLoadIfShellReady(browserManager)
        // Live Folders runtime attaches only when the module is enabled (W4/R9),
        // via OptionalModuleHost.attachEnabled.
        precondition(
            browserManager.downloadManager.attachRetryTransport(
                BrowserWebKitDownloadRetryTransport(
                    shellRuntime: browserManager.shellRuntime,
                    webViewRouting: browserManager.webViewRoutingService,
                    transportFactory: browserManager.downloadTransportFactory
                )
            ),
            "Download retry transport must be attached exactly once"
        )
        browserManager.optionalModules.attachEnabled(into: browserManager)
        browserManager.glanceManager.attach(
            runtime: BrowserGlanceRuntimeService.runtime(for: browserManager)
        )
        browserManager.authenticationManager.attach(
            runtime: BrowserAuthenticationRuntimeFactory.runtime(for: browserManager)
        )
        return tabRuntimeCompositionCancellable
    }

    private static func attachWebViewRuntime(to browserManager: BrowserManager) {
        let webViewRuntime = browserManager.webViewRuntime
        precondition(
            webViewRuntime.webViewSessions === browserManager.webViewSessions,
            "Browser session and WebView runtime must share one repository"
        )
        webViewRuntime.websiteDataCleanupService.registerExtensionRuntime {
            [weak browserManager] profileIDs in
            guard let browserManager else { return false }
            return browserManager.optionalModules.extensions
                .quiesceForWebsiteDataMutation(profileIDs: profileIDs)
        }

        let cleanup = webViewRuntime.websiteDataCleanupService
        browserManager.browsingDataCleanupService.destructiveCleanupPreparer = cleanup
        browserManager.dataServices.automaticBrowsingDataCleanupService
            .attachDestructiveCleanupPreparer(cleanup)
        browserManager.dataServices.siteDataPolicyEnforcementService
            .attachDestructiveCleanupPreparer(cleanup)
        browserManager.dataServices.privacyService
            .attachDestructiveCleanupPreparer(cleanup)
        browserManager.dataServices.profileWebsiteDataMutationService
            .attachDestructiveCleanupPreparer(cleanup)
    }

    private static func attachShellRuntime(to browserManager: BrowserManager) {
        browserManager.shellRuntime.attach(
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
        guard browserManager.windowRegistry != nil else { return }
        browserManager.tabManager.runtimePortsAttachmentOwner
            .startPersistedStateRestoreIfNeeded()
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
