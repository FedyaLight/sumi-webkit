import Foundation

@available(macOS 15.5, *)
@MainActor
enum BrowserExtensionManagerRuntimeFactory {
    static func runtime(for browserManager: BrowserManager) -> ExtensionManagerRuntime {
        let currentProfileAuthority = browserManager.currentProfileAuthority
        return ExtensionManagerRuntime(
            currentProfile: { [currentProfileAuthority] in
                currentProfileAuthority.currentProfile
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
            windowRegistrationReceipt: { [weak browserManager] window in
                browserManager?.windowRegistry?.registrationReceipt(for: window)
            },
            registeredWindow: { [weak browserManager] receipt in
                browserManager?.windowRegistry?.window(ifCurrent: receipt)
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
            untrackedOwnedWebView: { [weak browserManager] tab in
                browserManager?.webViewRuntime.ownershipQuery
                    .untrackedOwnedWebView(for: tab)
            },
            trackedWebViews: { [weak browserManager] tabId in
                browserManager?.webViewRuntime.ownershipQuery
                    .trackedWebViews(for: tabId) ?? []
            },
            rebuildLiveWebViews: { [weak browserManager] tab in
                guard let browserManager else { return .failed }
                switch browserManager.webViewRuntime.rebuildService
                    .rebuildLiveWebViewsResult(
                        for: tab,
                        reason: "ExtensionRuntimeTabRebuildPlan"
                    ) {
                case .committed:
                    return .committed
                case .deferred:
                    return .deferred
                case .noLiveWindows:
                    return .noLiveWindows
                case .failed:
                    return .failed
                }
            },
            websiteDataMutationAdmissionIsBlocked: { [weak browserManager] profileID in
                browserManager?.webViewRuntime.websiteDataCleanupService
                    .admissionIsBlocked(profileID: profileID) ?? false
            },
            waitForWebsiteDataMutationAdmission: { [weak browserManager] profileID in
                guard let browserManager else { return true }
                return await browserManager.webViewRuntime
                    .websiteDataCleanupService
                    .waitForAdmission(profileID: profileID)
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
