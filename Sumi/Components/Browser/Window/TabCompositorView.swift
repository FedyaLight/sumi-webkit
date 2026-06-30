import Combine
import Foundation

@MainActor
struct TabCompositorRuntime {
    let markTabAccessed: @MainActor (UUID) -> Void
    let isTabDisplayedInAnyWindow: @MainActor (UUID) -> Bool
    let registeredCompositorWindows: @MainActor () -> [BrowserWindowState]
    let refreshCompositor: @MainActor (BrowserWindowState) -> Void
}

@MainActor
class TabCompositorManager: ObservableObject {
    private var runtime: TabCompositorRuntime?

    func attach(runtime: TabCompositorRuntime) {
        self.runtime = runtime
    }

    func markTabAccessed(_ tabId: UUID) {
        requireRuntime().markTabAccessed(tabId)
    }

    func unloadTab(_ tab: Tab) {
        let runtime = requireRuntime()
        if runtime.isTabDisplayedInAnyWindow(tab.id) {
            runtime.markTabAccessed(tab.id)
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
        let runtime = requireRuntime()
        for windowState in runtime.registeredCompositorWindows() {
            runtime.refreshCompositor(windowState)
        }
    }

    private func requireRuntime() -> TabCompositorRuntime {
        guard let runtime else {
            preconditionFailure(
                "TabCompositorManager runtime is not attached. BrowserManagerRuntimeWiring.attach(to:) must run before compositor operations."
            )
        }
        return runtime
    }
}
