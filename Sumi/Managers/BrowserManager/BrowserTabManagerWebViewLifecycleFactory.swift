import Foundation

@MainActor
enum BrowserTabManagerWebViewLifecycleFactory {
    static func service(
        webViewLifecycle: WebViewLifecycleService,
        ownershipQuery: WebViewOwnershipQuery,
        trackedAdmission: TrackedWebViewAdmissionService,
        rebuild: WebViewRebuildService,
        profileAssignment: WebViewProfileAssignmentService,
        compositor: TabCompositorManager,
        webViewRouting: BrowserWebViewRoutingService,
        tabBrowserRuntime: TabBrowserRuntime
    ) -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: { tab, windowState in
                compositor.markTabAccessed(tab.id)
                guard ownershipQuery.webView(
                    for: tab.id,
                    in: windowState.id
                ) == nil else {
                    return
                }
                _ = trackedAdmission.webView(for: tab, in: windowState.id)
            },
            loadTab: { tab in
                compositor.loadTab(tab)
            },
            unloadTab: { tab in
                compositor.unloadTab(tab)
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
                webViewRouting.primaryTrackedWindowId(for: tabId)
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
                webViewRouting.anyLiveWebView(for: tab)
            },
            hasUntrackedOwnedWebView: { tab in
                webViewRouting.hasUntrackedOwnedWebView(for: tab)
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
