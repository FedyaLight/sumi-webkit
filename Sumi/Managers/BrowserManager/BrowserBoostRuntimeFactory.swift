import Foundation
import WebKit

@MainActor
enum BrowserBoostRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> SumiBoostsModule.Runtime {
        SumiBoostsModule.Runtime(
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            matchingLivePages: { [weak browserManager] profileId, host in
                guard let browserManager else { return [] }
                return matchingLivePages(
                    browserManager: browserManager,
                    profileId: profileId,
                    host: host
                )
            },
            allLivePages: { [weak browserManager] in
                guard let browserManager else { return [] }
                return allLivePages(browserManager: browserManager)
            },
            applyBoostAwareZoom: { [weak browserManager] tab, webView in
                browserManager?.chromeBundle.zoomCommandOwner.applyBoostAwareZoom(for: tab, webView: webView)
            },
            openWebInspector: { [weak browserManager] tab, windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.openWebInspector(for: tab, in: windowState)
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
        profileId: UUID,
        host: String
    ) -> [SumiBoostsModule.LivePage] {
        collectLivePages(browserManager: browserManager) { tab in
            (tab.resolveProfile()?.id ?? tab.profileId) == profileId
                && SumiBoostURLPolicy.normalizedBoostableHost(for: tab.url) == host
        }
    }

    private static func allLivePages(
        browserManager: BrowserManager
    ) -> [SumiBoostsModule.LivePage] {
        collectLivePages(browserManager: browserManager) { _ in true }
    }

    private static func collectLivePages(
        browserManager: BrowserManager,
        tabMatches: (Tab) -> Bool
    ) -> [SumiBoostsModule.LivePage] {
        var visited = Set<ObjectIdentifier>()
        var pages: [SumiBoostsModule.LivePage] = []

        func visit(_ tab: Tab, _ webView: WKWebView) {
            let identifier = ObjectIdentifier(webView)
            guard visited.insert(identifier).inserted else { return }
            pages.append(SumiBoostsModule.LivePage(tab: tab, webView: webView))
        }

        for windowState in browserManager.windowRegistry?.allWindows ?? [] {
            for tab in browserManager.windowSessionBundle.tabContextOwner.tabsForDisplay(in: windowState) where tabMatches(tab) {
                if let webView = browserManager.webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id) {
                    visit(tab, webView)
                }
            }
        }

        for tab in browserManager.tabManager.tabCollectionMembershipOwner.allTabs() where tabMatches(tab) {
            for webView in browserManager.webViewOwnershipQuery.trackedWebViews(for: tab.id) {
                visit(tab, webView)
            }
        }

        return pages
    }
}
