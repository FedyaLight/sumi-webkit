import Foundation

@MainActor
extension TabCompositorRuntime {
    static func make(browserManager: BrowserManager) -> Self {
        Self(
            markTabAccessed: { [weak browserManager] tabId in
                if let tab = browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabId) {
                    tab.suspensionStateOwner.noteAccess()
                    return
                }
                browserManager?.windowRegistry?.windows.values
                    .flatMap(\.ephemeralTabs)
                    .first { $0.id == tabId }?
                    .suspensionStateOwner.noteAccess()
            },
            isTabDisplayedInAnyWindow: { [weak browserManager] tabId in
                browserManager?.windowTabContextOwner.isTabDisplayedInAnyWindow(tabId) ?? false
            },
            registeredCompositorWindows: { [weak browserManager] in
                guard let browserManager,
                      let windowRegistry = browserManager.windowRegistry,
                      let coordinator = browserManager.webViewCoordinator
                else { return [] }

                return coordinator.compositorContainers().compactMap { windowId, _ in
                    windowRegistry.windows[windowId]
                }
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowVisualMutationOwner.refreshCompositor(for: windowState)
            }
        )
    }
}
