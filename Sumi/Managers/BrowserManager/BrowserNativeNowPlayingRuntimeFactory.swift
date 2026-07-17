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
        let membership = browserManager
            .tabCollectionMembershipOwner
        return SumiNativeNowPlayingBrowserRuntime(
            windowStates: { [weak browserManager] in
                browserManager.map { Array($0.windowRegistry.windows.values) } ?? []
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry.windows[windowId]
            },
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            mediaCandidateTabs: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.windowScopedMediaCandidateTabs(in: windowState) ?? []
            },
            tab: { [membership] tabId in
                membership.tab(for: tabId)
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
