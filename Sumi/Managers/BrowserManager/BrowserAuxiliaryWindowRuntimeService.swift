import Foundation

@MainActor
enum BrowserAuxiliaryWindowRuntimeService {
    static func runtime(for browserManager: BrowserManager) -> AuxiliaryWindowRuntime {
        AuxiliaryWindowRuntime(
            loadedEnabledExtensionManager: { [weak browserManager] in
                browserManager?.extensionsModule.managerIfLoadedAndEnabled()
            },
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            currentProfileID: { [weak browserManager] in
                browserManager?.currentProfile?.id
            },
            currentSpace: { [weak browserManager] in
                browserManager?.tabManager.spaceStateOwner.currentSpace
            },
            windowContainingTab: { [weak browserManager] tab in
                browserManager?.windowTabContextOwner.windowState(containing: tab)
            },
            createMiniWindowTab: { [weak browserManager] openerTab, profileId, urlString, contextOverride in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.createAuxiliaryMiniWindowTab(
                    openerTab: openerTab,
                    profileId: profileId,
                    urlString: urlString,
                    webExtensionContextOverride: contextOverride
                )
            },
            removeMiniWindowTab: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner.removeAuxiliaryMiniWindowTab(tab)
            },
            notifyTabClosedIfLoaded: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
            },
            registerExtensionCreatedTabIfLoaded: { [weak browserManager] tab, reason in
                browserManager?.extensionsModule.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    tab,
                    reason: reason
                )
            },
            installUntrackedOwnedWebView: { [weak browserManager] webView, tab in
                browserManager?.webViewRoutingService.installUntrackedOwnedWebView(
                    webView,
                    for: tab
                )
            },
            popupPermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.popupPermissionBridge
            },
            filePickerPermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.filePickerPermissionBridge
            }
        )
    }
}
