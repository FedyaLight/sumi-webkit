import Foundation

@MainActor
final class BrowserSidebarTabCommandOwner {
    struct Dependencies {
        let requestUserTabActivation: @MainActor (Tab, BrowserWindowState) -> Void
        let closeTab: @MainActor (Tab, BrowserWindowState) -> Void
        let moveTabUp: @MainActor (UUID) -> Void
        let moveTabDown: @MainActor (UUID) -> Void
        let openForegroundTab: @MainActor (String, BrowserWindowState, UUID?) -> Tab?
        let openNewTabOrFloatingBar: @MainActor (BrowserWindowState) -> Void
        let duplicateTab: @MainActor (Tab, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func requestUserTabActivation(_ tab: Tab, in windowState: BrowserWindowState) {
        dependencies.requestUserTabActivation(tab, windowState)
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        dependencies.closeTab(tab, windowState)
    }

    func moveTabUp(_ tabId: UUID) {
        dependencies.moveTabUp(tabId)
    }

    func moveTabDown(_ tabId: UUID) {
        dependencies.moveTabDown(tabId)
    }

    func openForegroundTab(
        _ url: String,
        in windowState: BrowserWindowState,
        preferredSpaceId: UUID?
    ) -> Tab? {
        dependencies.openForegroundTab(url, windowState, preferredSpaceId)
    }

    func openNewTabOrFloatingBar(in windowState: BrowserWindowState) {
        dependencies.openNewTabOrFloatingBar(windowState)
    }

    func duplicateTab(_ tab: Tab, in windowState: BrowserWindowState) {
        dependencies.duplicateTab(tab, windowState)
    }
}

extension BrowserSidebarTabCommandOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            requestUserTabActivation: { [weak browserManager] tab, windowState in
                browserManager?.requestUserTabActivation(tab, in: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.closeTab(tab, in: windowState)
            },
            moveTabUp: { [weak browserManager] tabId in
                browserManager?.tabManager.moveTabUp(tabId)
            },
            moveTabDown: { [weak browserManager] tabId in
                browserManager?.tabManager.moveTabDown(tabId)
            },
            openForegroundTab: { [weak browserManager] url, windowState, preferredSpaceId in
                browserManager?.openNewTab(
                    url: url,
                    context: .foreground(
                        windowState: windowState,
                        preferredSpaceId: preferredSpaceId
                    )
                )
            },
            openNewTabOrFloatingBar: { [weak browserManager] windowState in
                browserManager?.floatingBarRoutingOwner.openNewTabOrFloatingBar(in: windowState)
            },
            duplicateTab: { [weak browserManager] tab, windowState in
                browserManager?.duplicateTab(tab, in: windowState)
            }
        )
    }
}
