import AppKit
import Combine

@MainActor
struct TabCompositorRuntime {
    let markTabAccessed: @MainActor (UUID) -> Void
    let isTabDisplayedInAnyWindow: @MainActor (UUID) -> Bool
    let registeredCompositorWindows: @MainActor () -> [BrowserWindowState]
    let refreshCompositor: @MainActor (BrowserWindowState) -> Void
}

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

@MainActor
class TabCompositorManager: ObservableObject {
    private var runtime: TabCompositorRuntime?

    func attach(runtime: TabCompositorRuntime) {
        self.runtime = runtime
    }

    func markTabAccessed(_ tabId: UUID) {
        runtime?.markTabAccessed(tabId)
    }

    func unloadTab(_ tab: Tab) {
        if runtime?.isTabDisplayedInAnyWindow(tab.id) == true {
            markTabAccessed(tab.id)
            return
        }
        tab.unloadWebView()
    }

    func loadTab(_ tab: Tab) {
        guard tab.requiresPrimaryWebView else { return }
        tab.noteSuspensionAccess()
        tab.loadWebViewIfNeeded()
    }

    func updateTabVisibility() {
        guard let runtime else { return }
        for windowState in runtime.registeredCompositorWindows() {
            runtime.refreshCompositor(windowState)
        }
    }
}
