import Combine
import Foundation

@MainActor
enum BrowserManagerRuntimeWiring {
    static func attach(
        to browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> AnyCancellable {
        precondition(
            browserManager.tabRuntimeLifecycle.canStart,
            "Browser tab runtime ports must attach exactly once"
        )
        attachWebViewRuntime(to: browserManager)
        attachShellRuntime(to: browserManager)
        browserManager.compositorManager.attach(runtime: .make(browserManager: browserManager))
        let tabRuntimeCompositionCancellable = attachTabResourceRuntimes(
            to: browserManager,
            splitQuery: splitQuery
        )
        let webViewCommandCancellable = attachWebViewCommands(
            windowCommands: browserManager.webViewWindowCommands,
            closeRequests: browserManager.webViewCloseRequests,
            windows: browserManager.windowRegistry,
            membership: browserManager.tabCollectionMembershipOwner,
            selection: browserManager.browserTabSelection,
            visuals: browserManager.shellRuntime.windowVisuals,
            closeRouter: browserManager.webViewCloseRouter
        )
        let runtimePortRegistry = BrowserTabManagerRuntimePortsFactory.registry(
            for: browserManager,
            splitQuery: splitQuery
        )
        precondition(
            browserManager.tabRuntimeLifecycle.start(with: runtimePortRegistry)
                == .attached,
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
            runtime: BrowserGlanceRuntimeService.runtime(
                for: browserManager,
                splitQuery: splitQuery
            )
        )
        browserManager.authenticationManager.attach(
            runtime: BrowserAuthenticationRuntimeFactory.runtime(for: browserManager)
        )
        return AnyCancellable {
            tabRuntimeCompositionCancellable.cancel()
            webViewCommandCancellable.cancel()
        }
    }

    private static func attachWebViewRuntime(to browserManager: BrowserManager) {
        let webViewRuntime = browserManager.webViewRuntime
        precondition(
            webViewRuntime.webViewSessions === browserManager.webViewSessions,
            "Browser session and WebView runtime must share one repository"
        )
        let extensions = browserManager.optionalModules.extensions
        webViewRuntime.websiteDataCleanupService.registerExtensionRuntime {
            [extensions] profileIDs in
            extensions
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

    private enum WebViewCommand {
        case window(BrowserWebViewWindowCommand)
        case close(BrowserWebViewCloseRequest)
    }

    private static func attachWebViewCommands(
        windowCommands: BrowserWebViewWindowCommandChannel,
        closeRequests: BrowserWebViewCloseRequestBroker,
        windows: WindowRegistry,
        membership: TabCollectionMembershipOwner,
        selection: BrowserTabSelectionOwner,
        visuals: BrowserWindowVisualCoordinator,
        closeRouter: BrowserWebViewCloseRouter
    ) -> AnyCancellable {
        Publishers.Merge(
            windowCommands.publisher.map(WebViewCommand.window),
            closeRequests.publisher.map(WebViewCommand.close)
        )
        .sink { command in
            switch command {
            case .window(.selectTab(let tabID, let windowID)):
                guard let window = windows.windows[windowID],
                      let tab = membership.tab(for: tabID) else {
                    return
                }
                _ = selection.selectTab(
                    tab,
                    in: window,
                    loadPolicy: .deferred
                )
            case .window(.refreshCompositor(let windowID)):
                guard let window = windows.windows[windowID] else { return }
                visuals.refreshCompositor(for: window)
            case .close(let request):
                closeRequests.resolve(
                    request,
                    handled: closeRouter.handleNormalWebViewDidClose(
                        request.webView
                    )
                )
            }
        }
    }

    private static func attachShellRuntime(to browserManager: BrowserManager) {
        browserManager.glanceManager.windowRegistry = browserManager.windowRegistry
        browserManager.privacyBundle.permissionSidebarPinningOwner
            .scheduleReconciliation(reason: "window-registry-attached")
        browserManager.backgroundMediaOptimizationService.scheduleReconcile(
            reason: "window-registry-attached"
        )
        browserManager.reconcileStartupSessionIfPossible()
        startPersistedStateLoadIfShellReady(browserManager)
    }

    private static func attachTabResourceRuntimes(
        to browserManager: BrowserManager,
        splitQuery: WindowSplitQuery
    ) -> AnyCancellable {
        let shellRuntime = browserManager.shellRuntime
        let webViewRuntime = browserManager.webViewRuntime
        let tabSuspension = browserManager.tabSuspensionController
        let backgroundMedia = browserManager.backgroundMediaOptimizationService
        let reconciliation = BrowserTabRuntimeReconcileOwner(
            tabSuspension: tabSuspension,
            backgroundMedia: backgroundMedia
        )
        let structuralObserver = BrowserTabStructuralRuntimeObserver(
            structuralChanges: browserManager.tabStructureEventBus.structureChangedPublisher,
            reconciliation: reconciliation
        )
        let tabSuspensionRuntime = BrowserTabSuspensionRuntimeFactory.ports(
            windowRegistry: { [weak shellRuntime] in
                shellRuntime?.windowRegistry
            },
            regularTabs: browserManager.tabCollectionMembershipOwner,
            lazyRestore: browserManager.lazyRestoreCoordinator,
            windowTabs: shellRuntime.windowTabs,
            splitQuery: splitQuery,
            webView: TabSuspensionWebViewRuntime(
                liveWebViews: { [ownership = webViewRuntime.ownershipQuery] tab in
                    ownership.suspensionLiveWebViews(for: tab)
                },
                suspendWebViews: { [lifecycle = webViewRuntime.lifecycleService] tab, reason in
                    lifecycle.suspendWebViews(for: tab, reason: reason)
                },
                isProtectedFromCompositorMutation: {
                    [protection = webViewRuntime.protectionRuntime] webView in
                    protection.isProtected(webView)
                }
            )
        )
        let backgroundMediaRuntime = BrowserBackgroundMediaRuntimeFactory.runtime(
            webViews: BrowserBackgroundMediaWebViewProjection(
                ownership: webViewRuntime.ownershipQuery
            ),
            energyPolicy: BrowserBackgroundMediaEnergyPolicy(
                settings: browserManager.settingsAttachment
            ),
            tabs: BrowserRuntimeTabCatalog(
                regularTabs: browserManager.tabCollectionMembershipOwner,
                windows: browserManager.windowRegistry
            ),
            visibility: BrowserBackgroundMediaVisibilityProjection(
                windows: browserManager.windowRegistry,
                windowTabs: shellRuntime.windowTabs,
                splitQuery: splitQuery
            )
        )

        return BrowserTabRuntimeCompositionService.attach(
            tabSuspension: tabSuspension,
            tabSuspensionRuntime: tabSuspensionRuntime,
            backgroundMedia: backgroundMedia,
            backgroundMediaRuntime: backgroundMediaRuntime,
            structuralObserver: structuralObserver
        )
    }

    private static func startPersistedStateLoadIfShellReady(
        _ browserManager: BrowserManager
    ) {
        browserManager.tabRuntimeLifecycle
            .startPersistedStateRestoreIfNeeded()
    }

    static func nativeNowPlayingRuntimeContext(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingRuntimeContext {
        BrowserNativeNowPlayingRuntimeFactory.context(for: browserManager)
    }
}
