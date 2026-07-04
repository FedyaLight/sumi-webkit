import Foundation

@MainActor
enum BrowserNativeNowPlayingRuntimeFactory {
    static func context(for browserManager: BrowserManager) -> SumiNativeNowPlayingRuntimeContext {
        SumiNativeNowPlayingRuntimeContext.live(
            runtime: runtime(for: browserManager)
        )
    }

    private static func runtime(
        for browserManager: BrowserManager
    ) -> SumiNativeNowPlayingBrowserRuntime {
        SumiNativeNowPlayingBrowserRuntime(
            windowStates: { [weak browserManager] in
                browserManager?.windowRegistry.map { Array($0.windows.values) } ?? []
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            mediaCandidateTabs: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.windowScopedMediaCandidateTabs(in: windowState) ?? []
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            resolvedNowPlayingWebView: { [weak browserManager] tab, windowState in
                guard let browserManager else { return nil }
                return browserManager.webViewRoutingService.windowOwnedWebView(for: tab, in: windowState.id)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            }
        )
    }
}
