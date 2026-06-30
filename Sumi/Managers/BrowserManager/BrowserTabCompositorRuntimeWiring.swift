import Foundation

@MainActor
extension TabCompositorRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            markTabAccessed: { [weak browserManager] tabId in
                if let tab = browserManager?.tabManager.tab(for: tabId) {
                    tab.noteSuspensionAccess()
                    return
                }
                browserManager?.windowRegistry?.windows.values
                    .flatMap(\.ephemeralTabs)
                    .first { $0.id == tabId }?
                    .noteSuspensionAccess()
            },
            isTabDisplayedInAnyWindow: { [weak browserManager] tabId in
                browserManager?.isTabDisplayedInAnyWindow(tabId) ?? false
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
                browserManager?.refreshCompositor(for: windowState)
            }
        )
    }
}
