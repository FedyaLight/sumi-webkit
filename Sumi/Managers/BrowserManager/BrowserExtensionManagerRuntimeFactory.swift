import Foundation

@available(macOS 15.5, *)
@MainActor
enum BrowserExtensionManagerRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> ExtensionManagerRuntime {
        let ownershipQuery = browserManager.webViewRuntime.ownershipQuery
        let rebuild = browserManager.webViewRuntime.rebuildService
        let websiteDataCleanup = browserManager.webViewRuntime.websiteDataCleanupService
        return ExtensionManagerRuntime(
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
                browserManager?.shellRuntime.windowTabs.windowState(containing: tab)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            primaryTrackedWindowId: { [weak browserManager] tabId in
                browserManager?.webViewRoutingService.primaryTrackedWindowId(for: tabId)
            },
            untrackedOwnedWebView: { [ownershipQuery] tab in
                ownershipQuery.untrackedOwnedWebView(for: tab)
            },
            trackedWebViews: { [ownershipQuery] tabId in
                ownershipQuery.trackedWebViews(for: tabId)
            },
            rebuildLiveWebViews: { [rebuild] tab in
                rebuild.rebuildLiveWebViews(for: tab)
            },
            websiteDataMutationAdmissionIsBlocked: { [websiteDataCleanup] profileID in
                websiteDataCleanup.admissionIsBlocked(profileID: profileID)
            },
            waitForWebsiteDataMutationAdmission: { [websiteDataCleanup] profileID in
                await websiteDataCleanup.waitForAdmission(profileID: profileID)
            },
            browserRuntimeAvailable: { [weak browserManager] in
                browserManager != nil
            },
            extensionsModuleEnabled: { [weak browserManager] in
                guard let browserManager else { return .unavailable }
                return .enabled(browserManager.optionalModules.extensions.isEnabled)
            }
        )
    }
}
