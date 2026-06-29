import Foundation

@MainActor
final class BrowserTabCloseOrchestrationOwner {
    struct Dependencies {
        let activeWindow: () -> BrowserWindowState?
        let currentTab: (BrowserWindowState) -> Tab?
        let glanceManager: GlanceManager
        let tabManager: () -> TabManager
        let fallbackPlanner: () -> BrowserTabCloseFallbackPlanner
        let shortcutLiveTabCloseOwner: () -> BrowserShortcutLiveTabCloseOwner
        let selectTab: (Tab, BrowserWindowState) -> Void
        let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
        let showEmptyState: (BrowserWindowState) -> Void
        let persistWindowSession: (BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func closeCurrentTab() {
        guard let activeWindow = dependencies.activeWindow() else {
            return
        }

        if activeWindow.isFloatingBarVisible {
            return
        }

        if dependencies.glanceManager.activePreviewTab(for: activeWindow) != nil {
            dependencies.glanceManager.dismissGlance()
            return
        }

        guard let currentTab = dependencies.currentTab(activeWindow) else {
            dependencies.showEmptyState(activeWindow)
            return
        }

        closeTab(currentTab, in: activeWindow)
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        if dependencies.glanceManager.currentSession?.sourceTab?.id == tab.id {
            dependencies.glanceManager.dismissGlance()
        }

        if windowState.isIncognito {
            closeIncognitoTab(tab, in: windowState)
            return
        }

        if tab.isShortcutLiveInstance {
            dependencies.shortcutLiveTabCloseOwner().close(tab, in: windowState)
            return
        }

        closeRegularTab(tab, in: windowState)
    }

    private func closeRegularTab(_ tab: Tab, in windowState: BrowserWindowState) {
        let tabManager = dependencies.tabManager()
        let wasCurrent = windowState.currentTabId == tab.id
        let fallback = wasCurrent
            ? dependencies.fallbackPlanner().fallbackAfterClosingRegularTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil
        if let fallback {
            dependencies.selectTab(fallback, windowState)
            dependencies.performImmediateVisualHandoffIfPossible(windowState)
        }
        tabManager.removeTab(tab.id)
        windowState.removeFromRegularTabHistory(tab.id)

        if wasCurrent {
            if fallback == nil {
                dependencies.showEmptyState(windowState)
            }
        } else {
            dependencies.persistWindowSession(windowState)
        }
    }

    private func closeIncognitoTab(_ tab: Tab, in windowState: BrowserWindowState) {
        tab.performComprehensiveWebViewCleanup()

        if let index = windowState.ephemeralTabs.firstIndex(where: { $0.id == tab.id }) {
            windowState.ephemeralTabs.remove(at: index)
        }

        if let nextTab = windowState.ephemeralTabs.last {
            dependencies.selectTab(nextTab, windowState)
        } else {
            dependencies.showEmptyState(windowState)
        }
    }
}

extension BrowserTabCloseOrchestrationOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let fallbackPlanner = browserManager.tabCloseFallbackPlanner
        let shortcutLiveTabCloseOwner = browserManager.shortcutLiveTabCloseOwner
        return Self(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            glanceManager: browserManager.glanceManager,
            tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                browserManager?.tabManager ?? tabManager
            },
            fallbackPlanner: { fallbackPlanner },
            shortcutLiveTabCloseOwner: { shortcutLiveTabCloseOwner },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.performImmediateVisualHandoffIfPossible(in: windowState)
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.persistWindowSession(for: windowState)
            }
        )
    }
}
