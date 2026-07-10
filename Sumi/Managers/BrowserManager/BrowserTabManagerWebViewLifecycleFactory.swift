import Foundation

@MainActor
enum BrowserTabManagerWebViewLifecycleFactory {
    static func service(
        runtime: BrowserManagerRuntimeReference
    ) -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: { tab, windowState in
                runtime.require().materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            loadTab: { tab in
                runtime.require().compositorManager.loadTab(tab)
            },
            unloadTab: { tab in
                runtime.require().compositorManager.unloadTab(tab)
            },
            requireRemoveAllWebViews: { tab, closeActiveFullscreenMedia in
                runtime.require().shellRuntime.requireWebViewCoordinator()
                    .lifecycleService.removeAllWebViews(
                        for: tab,
                        closeActiveFullscreenMedia: closeActiveFullscreenMedia
                    )
            },
            windowIDsTrackingWebViews: { tabId in
                runtime.require().webViewOwnershipQuery.windowIDs(for: tabId)
            },
            primaryTrackedWindowId: { tabId in
                runtime.require().webViewRoutingService.primaryTrackedWindowId(for: tabId)
            },
            rebuildLiveWebViews: { tab, preferredPrimaryWindowId, url in
                if #available(macOS 15.5, *) {
                    runtime.require().webViewCoordinator?.rebuildService
                        .rebuildLiveWebViews(
                            for: tab,
                            preferredPrimaryWindowID: preferredPrimaryWindowId,
                            load: url
                        )
                }
            },
            prepareTab: { tab in
                tab.attachBrowserRuntime(
                    TabBrowserRuntimeFactory.make(for: runtime.require())
                )
                if tab.hasCurrentWebView == false {
                    _ = tab.navigationCommandOwner
                        .prepareMainFrameConfigurationPolicyIfNeeded(
                            tab.url,
                            for: tab,
                            reason: "BrowserTabManagerWebViewLifecycleFactory.prepareTab"
                        )
                }
            },
            anyLiveWebView: { tab in
                runtime.require().webViewRoutingService.anyLiveWebView(for: tab)
            },
            hasUntrackedOwnedWebView: { tab in
                runtime.require().webViewRoutingService.hasUntrackedOwnedWebView(for: tab)
            },
            abortProfileTransitions: { profileIDs in
                runtime.require().shellRuntime.requireWebViewCoordinator()
                    .profileAssignmentService.abortProfileTransitions(
                        profileIDs: profileIDs
                    )
            },
            executeProfileTransition: { tab, profile, intent, settlement in
                runtime.require().shellRuntime.requireWebViewCoordinator()
                    .profileAssignmentService.executeProfileAssignment(
                        for: tab,
                        targetProfile: profile,
                        intent: intent,
                        settlement: settlement
                    )
            },
            executeSpaceProfileTransition: {
                space,
                profile,
                intent,
                validateModel,
                modelCommit,
                modelFinish,
                modelRollback,
                settlement in
                runtime.require().shellRuntime.requireWebViewCoordinator()
                    .profileAssignmentService.executeSpaceProfileAssignment(
                        space: space,
                        targetProfile: profile,
                        intent: intent,
                        validateModel: validateModel,
                        modelCommit: modelCommit,
                        modelFinish: modelFinish,
                        modelRollback: modelRollback,
                        settlement: settlement
                    )
            }
        )
    }
}
