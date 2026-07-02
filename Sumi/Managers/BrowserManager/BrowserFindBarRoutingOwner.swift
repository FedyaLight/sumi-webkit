import Foundation

@MainActor
final class BrowserFindBarRoutingOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let activePageTab: @MainActor (BrowserWindowState) -> Tab?
        let showFindBar: @MainActor (Tab?, UUID?) -> Void
        let updateCurrentTab: @MainActor (Tab?, UUID?) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func showFindBar() {
        let session = activeFindSession()
        dependencies.showFindBar(session.tab, session.windowId)
    }

    func updateCurrentTab() {
        let session = activeFindSession()
        dependencies.updateCurrentTab(session.tab, session.windowId)
    }

    private func activeFindSession() -> (tab: Tab?, windowId: UUID?) {
        guard let windowState = dependencies.activeWindow() else {
            return (nil, nil)
        }

        return (dependencies.activePageTab(windowState), windowState.id)
    }
}

extension BrowserFindBarRoutingOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.activePageRoutingOwner.activePageTab(for: windowState)
            },
            showFindBar: { [weak browserManager] tab, windowId in
                browserManager?.findManager.showFindBar(for: tab, in: windowId)
            },
            updateCurrentTab: { [weak browserManager] tab, windowId in
                browserManager?.findManager.updateCurrentTab(tab, in: windowId)
            }
        )
    }
}
