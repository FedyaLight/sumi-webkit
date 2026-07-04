import Foundation

@available(macOS 15.5, *)
@MainActor
enum BrowserExtensionManagerRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> ExtensionManagerRuntime {
        ExtensionManagerRuntime(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            ephemeralProfile: { [weak browserManager] profileId in
                browserManager?.windowRegistry?.windows.values
                    .compactMap(\.ephemeralProfile)
                    .first { $0.id == profileId }
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            activeWindowState: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            allTabs: { [weak browserManager] in
                browserManager?.tabManager.tabCollectionMembershipOwner.allTabs() ?? []
            },
            allWindowStates: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowTabContextOwner.windowState(containing: tab)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            trackedWebViews: { [weak browserManager] tabId in
                browserManager?.webViewCoordinator?.getAllWebViews(for: tabId) ?? []
            },
            rebuildLiveWebViews: { [weak browserManager] tab in
                browserManager?.webViewCoordinator?.rebuildLiveWebViews(for: tab)
            },
            browserRuntimeAvailable: { [weak browserManager] in
                browserManager != nil
            },
            extensionsModuleEnabled: { [weak browserManager] in
                guard let browserManager else { return .unavailable }
                return .enabled(browserManager.extensionsModule.isEnabled)
            }
        )
    }
}
