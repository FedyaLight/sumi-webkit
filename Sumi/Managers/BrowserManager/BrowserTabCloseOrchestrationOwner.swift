import Foundation

@MainActor
final class BrowserTabCloseOrchestrationOwner {
    private let activeWindow: () -> BrowserWindowState?
    private let currentTab: (BrowserWindowState) -> Tab?
    private let glanceManager: GlanceManager
    private let tabManager: () -> TabManager
    private let fallbackPlanner: () -> BrowserTabCloseFallbackPlanner
    private let shortcutLiveTabCloseOwner: () -> BrowserShortcutLiveTabCloseOwner
    private let selectTab: (Tab, BrowserWindowState) -> Void
    private let performImmediateVisualHandoffIfPossible: (BrowserWindowState) -> Void
    private let showEmptyState: (BrowserWindowState) -> Void
    private let persistWindowSession: (BrowserWindowState) -> Void

    init(
        activeWindow: @escaping () -> BrowserWindowState?,
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        glanceManager: GlanceManager,
        tabManager: @escaping () -> TabManager,
        fallbackPlanner: @escaping () -> BrowserTabCloseFallbackPlanner,
        shortcutLiveTabCloseOwner: @escaping () -> BrowserShortcutLiveTabCloseOwner,
        selectTab: @escaping (Tab, BrowserWindowState) -> Void,
        performImmediateVisualHandoffIfPossible: @escaping (BrowserWindowState) -> Void,
        showEmptyState: @escaping (BrowserWindowState) -> Void,
        persistWindowSession: @escaping (BrowserWindowState) -> Void
    ) {
        self.activeWindow = activeWindow
        self.currentTab = currentTab
        self.glanceManager = glanceManager
        self.tabManager = tabManager
        self.fallbackPlanner = fallbackPlanner
        self.shortcutLiveTabCloseOwner = shortcutLiveTabCloseOwner
        self.selectTab = selectTab
        self.performImmediateVisualHandoffIfPossible = performImmediateVisualHandoffIfPossible
        self.showEmptyState = showEmptyState
        self.persistWindowSession = persistWindowSession
    }

    func closeCurrentTab() {
        guard let activeWindow = activeWindow() else {
            return
        }

        closeCurrentTab(in: activeWindow)
    }

    func closeCurrentTab(in windowState: BrowserWindowState) {
        if windowState.isFloatingBarVisible {
            return
        }

        if glanceManager.activePreviewTab(for: windowState) != nil {
            glanceManager.dismissGlance()
            return
        }

        guard let currentTab = currentTab(windowState) else {
            showEmptyState(windowState)
            return
        }

        closeTab(currentTab, in: windowState)
    }

    func closeTab(_ tab: Tab, in windowState: BrowserWindowState) {
        if glanceManager.currentSession?.sourceTab?.id == tab.id {
            glanceManager.dismissGlance()
        }

        if windowState.isIncognito {
            closeIncognitoTab(tab, in: windowState)
            return
        }

        if tab.isShortcutLiveInstance {
            shortcutLiveTabCloseOwner().close(tab, in: windowState)
            return
        }

        closeRegularTab(tab, in: windowState)
    }

    private func closeRegularTab(_ tab: Tab, in windowState: BrowserWindowState) {
        let tabManager = tabManager()
        let wasCurrent = windowState.currentTabId == tab.id
        let fallback = wasCurrent
            ? fallbackPlanner().fallbackAfterClosingRegularTab(
                tab,
                in: windowState,
                tabStore: tabManager.runtimeStore
            )
            : nil
        if let fallback {
            selectTab(fallback, windowState)
            performImmediateVisualHandoffIfPossible(windowState)
        }
        tabManager.tabRemovalOwner.removeTab(tab.id)
        windowState.selectionHistory.removeFromRegularTabHistory(tab.id)

        if wasCurrent {
            if fallback == nil {
                showEmptyState(windowState)
            }
        } else {
            persistWindowSession(windowState)
        }
    }

    private func closeIncognitoTab(_ tab: Tab, in windowState: BrowserWindowState) {
        tab.performComprehensiveWebViewCleanup()

        if let index = windowState.ephemeralTabs.firstIndex(where: { $0.id == tab.id }) {
            windowState.ephemeralTabs.remove(at: index)
        }

        if let nextTab = windowState.ephemeralTabs.last {
            selectTab(nextTab, windowState)
        } else {
            showEmptyState(windowState)
        }
    }
}
