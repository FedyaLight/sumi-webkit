import Foundation

@MainActor
extension TabCompositorRuntime {
    static func make(browserManager: BrowserManager) -> Self {
        let webViewCompositor = browserManager.webViewRuntime.compositorRuntime
        return Self(
            markTabAccessed: { [weak browserManager] tabId in
                if let tab = browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId) {
                    tab.noteAccess()
                    return
                }
                browserManager?.windowRegistry?.windows.values
                    .flatMap(\.ephemeralTabs)
                    .first { $0.id == tabId }?
                    .noteAccess()
            },
            isTabDisplayedInAnyWindow: { [weak browserManager] tabId in
                browserManager?.shellRuntime.windowTabs.isTabDisplayedInAnyWindow(tabId) ?? false
            },
            registeredCompositorWindows: { [weak browserManager] in
                guard let browserManager,
                      let windowRegistry = browserManager.windowRegistry
                else { return [] }

                return webViewCompositor.containers().compactMap { windowId, _ in
                    windowRegistry.windows[windowId]
                }
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            }
        )
    }
}
