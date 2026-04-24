import AppKit
import Combine

@MainActor
class TabCompositorManager: ObservableObject {
    weak var browserManager: BrowserManager?

    func markTabAccessed(_ tabId: UUID) {
        findTab(by: tabId)?.noteSuspensionAccess()
    }

    func unloadTab(_ tab: Tab) {
        if browserManager?.isTabDisplayedInAnyWindow(tab.id) == true {
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
        guard let browserManager = browserManager,
              let coordinator = browserManager.webViewCoordinator else { return }
        for (windowId, _) in coordinator.compositorContainers() {
            guard let windowState = browserManager.windowRegistry?.windows[windowId] else { continue }
            browserManager.refreshCompositor(for: windowState)
        }
    }

    private func findTab(by id: UUID) -> Tab? {
        guard let browserManager else { return nil }
        if let tab = browserManager.tabManager.tab(for: id) {
            return tab
        }
        return browserManager.windowRegistry?.windows.values
            .flatMap(\.ephemeralTabs)
            .first { $0.id == id }
    }
}
