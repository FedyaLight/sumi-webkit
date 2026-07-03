import Foundation

@MainActor
enum TabBrowserExtensionRuntimeFactory {
    static func extensionPropertiesRuntime(
        for browserManager: BrowserManager
    ) -> TabExtensionPropertiesRuntime {
        .live(extensionsModule: { [weak browserManager] in
            browserManager?.extensionsModule
        })
    }

    static func normalWebViewExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabNormalWebViewExtensionRuntime {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            }
        )
    }

    static func faviconExtensionRuntime(
        for browserManager: BrowserManager
    ) -> TabFaviconExtensionRuntime {
        .live(
            extensionsModule: { [weak browserManager] in
                browserManager?.extensionsModule
            },
            extensionSurfaceStore: { [weak browserManager] in
                browserManager?.extensionsModule.surfaceStore
            }
        )
    }
}

@MainActor
extension TabNormalWebViewExtensionRuntime {
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        currentTab: @escaping (BrowserWindowState) -> Tab?
    ) -> Self {
        Self(
            registerTabWithExtensionRuntimeIfNeeded: { tab, reason in
                guard let extensionsModule = extensionsModule() else { return }

                extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
                    tab,
                    reason: reason
                )

                guard let windowId = tab.primaryWindowId,
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
            }
        )
    }
}

@MainActor
extension TabFaviconExtensionRuntime {
    static func live(
        extensionsModule: @escaping () -> SumiExtensionsModule?,
        extensionSurfaceStore: @escaping () -> BrowserExtensionSurfaceStore?
    ) -> Self {
        Self(
            installedExtensions: {
                extensionsModule()?.managerIfLoadedAndEnabled()?.installedExtensions
                    ?? extensionSurfaceStore()?.installedExtensions
                    ?? []
            }
        )
    }
}

@MainActor
extension TabExtensionPropertiesRuntime {
    static func live(extensionsModule: @escaping () -> SumiExtensionsModule?) -> Self {
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
