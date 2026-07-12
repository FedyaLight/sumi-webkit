import Foundation

@MainActor
enum BrowserTabManagerWebViewLifecycleFactory {
    static func service(
        runtime: BrowserManagerRuntimeReference
    ) -> TabManagerWebViewLifecycleService {
        let browserManager = runtime.require()
        let webViewLifecycle = browserManager.webViewRuntime.lifecycleService
        let ownershipQuery = browserManager.webViewRuntime.ownershipQuery
        let rebuild = browserManager.webViewRuntime.rebuildService
        let profileAssignment = browserManager.webViewRuntime.profileAssignmentService
        let tabBrowserRuntime = TabBrowserRuntimeFactory.make(for: browserManager)
        return TabManagerWebViewLifecycleService(
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
                webViewLifecycle.removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia,
                    intent: .retirement
                )
            },
            windowIDsTrackingWebViews: { tabId in
                ownershipQuery.windowIDs(for: tabId)
            },
            primaryTrackedWindowId: { tabId in
                runtime.require().webViewRoutingService.primaryTrackedWindowId(for: tabId)
            },
            rebuildLiveWebViews: { tab, preferredPrimaryWindowId, url in
                if #available(macOS 15.5, *) {
                    rebuild.rebuildLiveWebViews(
                            for: tab,
                            preferredPrimaryWindowID: preferredPrimaryWindowId,
                            load: url
                        )
                }
            },
            prepareTab: { tab in
                tab.attachBrowserRuntime(tabBrowserRuntime)
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
                profileAssignment.abortProfileTransitions(
                        profileIDs: profileIDs
                    )
            },
            executeProfileTransition: { tab, profile, intent, settlement in
                profileAssignment.executeProfileAssignment(
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
                profileAssignment.executeSpaceProfileAssignment(
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
