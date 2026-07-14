import Foundation

@MainActor
enum TabBrowserExtensionRuntimeFactory {
    static func extensionPropertiesRuntime(
        for browserManager: BrowserManager
    ) -> TabExtensionPropertiesRuntime {
        .make(extensionsModule: { [weak browserManager] in
            browserManager?.optionalModules.extensions
        })
    }

    static func normalWebViewExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabNormalWebViewExtensionRuntime {
        .make(
            extensionsModule: { [weak browserManager] in
                browserManager?.optionalModules.extensions
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            primaryTrackedWindowId: { [weak browserManager] tabId in
                browserManager?.webViewRoutingService.primaryTrackedWindowId(for: tabId)
            }
        )
    }

    static func faviconExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabFaviconExtensionRuntime {
        .make(
            extensionsModule: { [weak browserManager] in
                browserManager?.optionalModules.extensions
            },
            extensionSurfaceStore: { [weak browserManager] in
                browserManager?.optionalModules.extensions.surfaceStore
            },
            shortcutLaunchURL: { [weak browserManager] shortcutPinId in
                browserManager?.tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: shortcutPinId)?.launchURL
            }
        )
    }
}

@MainActor
extension TabNormalWebViewExtensionRuntime {
    static func make(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        primaryTrackedWindowId: @escaping (UUID) -> UUID?
    ) -> Self {
        Self(
            registerTabWithExtensionRuntimeIfNeeded: { tab, reason in
                guard let extensionsModule = extensionsModule() else { return }

                extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
                    tab,
                    reason: reason
                )

                guard let windowId = primaryTrackedWindowId(tab.id),
                      let windowState = windowState(windowId),
                      currentTab(windowState)?.id == tab.id
                else {
                    return
                }

                extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            },
            prepareWebViewForExtensionRuntime: { webView, currentURL, reason in
                extensionsModule()?.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: currentURL,
                    reason: reason
                )
            },
            ensureInitialExtensionContextsIfNeeded: { profileId in
                await extensionsModule()?
                    .ensureInitialExtensionContextsIfNeeded(
                        profileId: profileId
                    )
            },
            pageContextMenuItems: { tab in
                extensionsModule()?.pageContextMenuItemsIfLoaded(for: tab) ?? []
            },
            reconcileOnUserGesture: { tab, reason in
                extensionsModule()?.reconcileExtensionRuntimeOnUserGestureIfNeeded(
                    tab,
                    reason: reason
                )
            }
        )
    }
}

@MainActor
extension TabFaviconExtensionRuntime {
    static func make(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        extensionSurfaceStore: @escaping () -> BrowserExtensionSurfaceStore?,
        shortcutLaunchURL: @escaping (UUID) -> URL?
    ) -> Self {
        Self(
            installedExtensions: {
                extensionsModule()?.installedExtensionsIfLoaded()
                    ?? extensionSurfaceStore()?.installedExtensions
                    ?? []
            },
            shortcutLaunchURL: shortcutLaunchURL
        )
    }
}

@MainActor
extension TabExtensionPropertiesRuntime {
    static func make(extensionsModule: @escaping () -> SumiExtensionsModule?) -> Self {
        Self(
            notifyTabPropertiesChanged: { tab, properties in
                extensionsModule()?.notifyTabPropertiesChangedIfLoaded(
                    tab,
                    properties: properties
                )
            }
        )
    }
}
