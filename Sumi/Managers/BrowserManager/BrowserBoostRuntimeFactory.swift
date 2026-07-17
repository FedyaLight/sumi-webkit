import Foundation
import WebKit

@MainActor
enum BrowserBoostRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiBoostsModule.Runtime {
        let inspector = WebInspectorService()
        let routing = browserManager.webViewRoutingService
        let ownershipQuery = browserManager.webViewRuntime.ownershipQuery
        return SumiBoostsModule.Runtime(
            windowOwnedWebView: { [routing] tab, windowId in
                routing.windowOwnedWebView(for: tab, in: windowId)
            },
            matchingLivePages: { [weak browserManager] profileId, host in
                guard let browserManager else { return [] }
                return matchingLivePages(
                    browserManager: browserManager,
                    routing: routing,
                    ownershipQuery: ownershipQuery,
                    profileId: profileId,
                    host: host
                )
            },
            allLivePages: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allLivePages(
                    browserManager: browserManager,
                    routing: routing,
                    ownershipQuery: ownershipQuery
                )
            },
            applyBoostAwareZoom: { [weak browserManager] tab, webView in
                browserManager?.chromeBundle.zoomCommandOwner.applyBoostAwareZoom(for: tab, webView: webView)
            },
            openWebInspector: { [weak browserManager, inspector] tab, windowState in
                guard !tab.representsSumiNativeSurface,
                      let webView = browserManager?.webViewRoutingService
                        .windowOwnedWebView(for: tab, in: windowState.id)
                else { return }
                _ = inspector.inspect(webView.sumiActivePresentationWebView)
            },
            sidebarPosition: { [weak browserManager] in
                browserManager?.sumiSettings?.sidebarPosition ?? .left
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            }
        )
    }

    private static func matchingLivePages(
        browserManager: BrowserManager,
        routing: BrowserWebViewRoutingService,
        ownershipQuery: WebViewOwnershipQuery,
        profileId: UUID,
        host: String
    ) -> [SumiBoostsModule.LivePage] {
        collectLivePages(
            browserManager: browserManager,
            routing: routing,
            ownershipQuery: ownershipQuery
        ) { tab in
            (tab.resolveProfile()?.id ?? tab.profileId) == profileId
                && SumiBoostURLPolicy.normalizedBoostableHost(for: tab.url) == host
        }
    }

    private static func allLivePages(
        browserManager: BrowserManager,
        routing: BrowserWebViewRoutingService,
        ownershipQuery: WebViewOwnershipQuery
    ) -> [SumiBoostsModule.LivePage] {
        collectLivePages(
            browserManager: browserManager,
            routing: routing,
            ownershipQuery: ownershipQuery
        ) { _ in true }
    }

    private static func collectLivePages(
        browserManager: BrowserManager,
        routing: BrowserWebViewRoutingService,
        ownershipQuery: WebViewOwnershipQuery,
        tabMatches: (Tab) -> Bool
    ) -> [SumiBoostsModule.LivePage] {
        let membership = browserManager
            .tabCollectionMembershipOwner
        var visited = Set<ObjectIdentifier>()
        var pages: [SumiBoostsModule.LivePage] = []

        func visit(_ tab: Tab, _ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard visited.insert(identifier).inserted else { return }
            pages.append(SumiBoostsModule.LivePage(tab: tab, webView: webView))
        }

        for windowState in browserManager.windowRegistry.allWindows {
            for tab in browserManager.shellRuntime.windowTabs.tabsForDisplay(in: windowState) where tabMatches(tab) {
                if let webView = routing.windowOwnedWebView(
                    for: tab,
                    in: windowState.id
                ) {
                    visit(tab, webView)
                }
            }
        }

        for tab in membership.allTabs() where tabMatches(tab) {
            for webView in ownershipQuery.trackedWebViews(for: tab.id) {
                visit(tab, webView)
            }
        }

        return pages
    }
}
