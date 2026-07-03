import Foundation
import WebKit

@MainActor
enum TabPopupRuntimeFactory {
    static func make(for browserManager: BrowserManager) -> TabPopupHandlingRuntime {
        .live(
            dependencies: TabPopupHandlingRuntime.LiveDependencies(
                isAvailable: { [weak browserManager] in
                    browserManager != nil
                },
                extensionsModule: { [weak browserManager] in
                    browserManager?.extensionsModule
                },
                popupPermissionBridge: { [weak browserManager] in
                    browserManager?.permissionRuntime.popupPermissionBridge
                },
                targetSpaceForOpener: { [weak browserManager] openerTab in
                    guard let browserManager else { return nil }
                    return TabPopupHandlingRuntime.targetSpace(
                        for: openerTab,
                        tabManager: browserManager.tabManager,
                        windowState: browserManager.windowTabContextOwner.windowState(containing: openerTab)
                    )
                },
                createNewTab: { [weak browserManager] url, space, activate in
                    browserManager?.tabManager.createNewTab(
                        url: url,
                        in: space,
                        activate: activate
                    )
                },
                materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                    browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
                },
                presentWebPopup: { [weak browserManager] configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                    browserManager?.auxiliaryWindowManager.presentWebPopup(
                        configuration: configuration,
                        request: request,
                        windowFeatures: windowFeatures,
                        openerTab: openerTab,
                        isExtensionOriginated: isExtensionOriginated,
                        shouldActivateApp: true
                    )
                },
                openerProfile: { [weak browserManager] openerTab in
                    guard let browserManager else { return nil }
                    return TabPopupHandlingRuntime.explicitPopupOpenerProfile(
                        for: openerTab,
                        windowRegistry: browserManager.windowRegistry,
                        profiles: browserManager.profileManager.profiles,
                        spaces: browserManager.tabManager.spaces
                    )
                },
                createPopupTab: { [weak browserManager] openerTab, activate in
                    browserManager?.tabLifecycleService.opening.createPopupTab(
                        from: openerTab,
                        activate: activate
                    )
                },
                windowStateContainingTab: { [weak browserManager] tab in
                    browserManager?.windowTabContextOwner.windowState(containing: tab)
                },
                selectTab: { [weak browserManager] tab, windowState in
                    browserManager?.selectTab(tab, in: windowState)
                }
            )
        )
    }
}

@MainActor
extension TabPopupHandlingRuntime {
    struct LiveDependencies {
        let isAvailable: () -> Bool
        let extensionsModule: () -> SumiExtensionsModule?
        let popupPermissionBridge: () -> SumiPopupPermissionBridge?
        let targetSpaceForOpener: (Tab) -> Space?
        let createNewTab: (_ url: String, _ space: Space?, _ activate: Bool) -> Tab?
        let materializeVisibleTabWebViewIfNeeded: (Tab, BrowserWindowState) -> Void
        let presentWebPopup: (
            _ configuration: WKWebViewConfiguration,
            _ request: URLRequest,
            _ windowFeatures: WKWindowFeatures,
            _ openerTab: Tab,
            _ isExtensionOriginated: Bool
        ) -> WKWebView?
        let openerProfile: (Tab) -> Profile?
        let createPopupTab: (_ openerTab: Tab, _ activate: Bool) -> Tab?
        let windowStateContainingTab: (Tab) -> BrowserWindowState?
        let selectTab: (Tab, BrowserWindowState) -> Void
    }

    static func live(dependencies: LiveDependencies) -> Self {
        Self(
            hasBrowserRuntime: dependencies.isAvailable,
            consumeRecentlyOpenedExtensionTabRequest: { requestURL in
                dependencies.extensionsModule()?
                    .consumeRecentlyOpenedExtensionTabRequestIfLoaded(for: requestURL) == true
            },
            evaluatePopupPermission: { request, tabContext in
                await dependencies.popupPermissionBridge()?.evaluate(
                    request,
                    tabContext: tabContext
                )
            },
            evaluatePopupPermissionForWebKitFallback: { request, tabContext in
                dependencies.popupPermissionBridge()?.evaluateSynchronouslyForWebKitFallback(
                    request,
                    tabContext: tabContext
                )
            },
            openExtensionExternalTab: { requestURL, openerTab in
                guard dependencies.isAvailable(),
                      let childTab = dependencies.createNewTab(
                          requestURL.absoluteString,
                          dependencies.targetSpaceForOpener(openerTab),
                          true
                      )
                else {
                    return false
                }
                if let windowState = dependencies.windowStateContainingTab(openerTab) {
                    dependencies.materializeVisibleTabWebViewIfNeeded(childTab, windowState)
                    dependencies.selectTab(childTab, windowState)
                }
                if childTab.isUnloaded {
                    childTab.loadWebViewIfNeeded()
                }
                dependencies.extensionsModule()?.registerExtensionCreatedTabWithExtensionRuntimeIfLoaded(
                    childTab,
                    reason: "SumiPopupHandlingNavigationResponder.extensionExternalTab"
                )
                return true
            },
            presentWebPopup: { configuration, request, windowFeatures, openerTab, isExtensionOriginated in
                dependencies.presentWebPopup(
                    configuration,
                    request,
                    windowFeatures,
                    openerTab,
                    isExtensionOriginated
                )
            },
            applyVisitedLinksToPopupConfiguration: { openerTab, configuration in
                guard let profile = dependencies.openerProfile(openerTab) else {
                    return
                }
                openerTab.visitedLinkStore.applyStore(
                    to: configuration,
                    for: profile
                )
            },
            createPopupTab: dependencies.createPopupTab,
            windowStateContainingTab: dependencies.windowStateContainingTab,
            selectTab: dependencies.selectTab
        )
    }

    static func targetSpace(
        for openerTab: Tab,
        tabManager: TabManager,
        windowState: BrowserWindowState?
    ) -> Space? {
        if let openerSpaceId = openerTab.spaceId,
           let openerSpace = tabManager.spaces.first(where: { $0.id == openerSpaceId }) {
            return openerSpace
        }

        if let windowSpaceId = windowState?.currentSpaceId,
           let windowSpace = tabManager.spaces.first(where: { $0.id == windowSpaceId }) {
            return windowSpace
        }

        if let windowProfileId = windowState?.currentProfileId,
           let windowProfileSpace = tabManager.spaces.first(where: { $0.profileId == windowProfileId }) {
            return windowProfileSpace
        }

        if let openerProfileId = openerTab.profileId,
           let openerProfileSpace = tabManager.spaces.first(where: { $0.profileId == openerProfileId }) {
            return openerProfileSpace
        }

        return tabManager.spaces.first
    }

    static func explicitPopupOpenerProfile(
        for tab: Tab,
        windowRegistry: WindowRegistry?,
        profiles: [Profile],
        spaces: [Space]
    ) -> Profile? {
        if let profileId = tab.profileId {
            if let windowState = windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == tab.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == profileId {
                return ephemeralProfile
            }

            return profiles.first { $0.id == profileId }
        }

        if let spaceId = tab.spaceId,
           let space = spaces.first(where: { $0.id == spaceId }),
           let profileId = space.profileId {
            return profiles.first { $0.id == profileId }
        }

        return nil
    }
}
