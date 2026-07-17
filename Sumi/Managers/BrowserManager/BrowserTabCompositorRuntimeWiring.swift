import Foundation

@MainActor
extension TabCompositorRuntime {
    static func make(browserManager: BrowserManager) -> Self {
        let webViewCompositor = browserManager.webViewRuntime.compositorRuntime
        let membership = browserManager
            .tabCollectionMembershipOwner
        return Self(
            markTabAccessed: { [weak browserManager] tabId in
                if let tab = membership.tab(for: tabId) {
                    tab.noteAccess()
                    return
                }
                browserManager?.windowRegistry.windows.values
                    .flatMap(\.ephemeralTabs)
                    .first { $0.id == tabId }?
                    .noteAccess()
            },
            isTabDisplayedInAnyWindow: { [weak browserManager] tabId in
                browserManager?.shellRuntime.windowTabs.isTabDisplayedInAnyWindow(tabId) ?? false
            },
            registeredCompositorWindows: { [weak browserManager] in
                guard let browserManager else { return [] }
                let windowRegistry = browserManager.windowRegistry

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
