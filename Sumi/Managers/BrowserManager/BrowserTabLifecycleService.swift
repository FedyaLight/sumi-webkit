import Foundation

@MainActor
final class BrowserTabLifecycleService {
    let selection = BrowserTabSelectionOwner()
    let closeFallbackPlanner: BrowserTabCloseFallbackPlanner
    let shortcutLiveTabClose: ShortcutLiveTabCloseService
    let closeOrchestration: BrowserTabCloseOrchestrationOwner
    let opening: BrowserTabOpeningOwner

    init(browserManager: BrowserManager) {
        let closeFallbackPlanner = BrowserTabCloseFallbackPlanner(
            selectionService: browserManager.shellRuntime.windowSelection
        )
        self.closeFallbackPlanner = closeFallbackPlanner

        let shortcutLiveTabClose = ShortcutLiveTabCloseService(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            // Recently-closed history is durable close-path state. Keeping it
            // available during terminal cleanup is intentional; live tab
            // mutation still requires the weak browser kernel above.
            recentlyClosedManager: { [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            fallbackPlanner: { closeFallbackPlanner },
            selectTabWithoutPersistence: { [weak browserManager] tab, windowState in
                Self.selectTabWithoutPersistence(
                    tab,
                    in: windowState,
                    browserManager: browserManager
                )
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.shellRuntime.windowVisuals.performImmediateVisualHandoffIfPossible(
                    in: windowState
                )
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            },
            showEmptyStateWithoutPersistence: { [weak browserManager] windowState in
                browserManager?.showEmptyStateWithoutPersistence(in: windowState)
            },
            splitShortcuts: { [weak browserManager] in
                browserManager?.sidebarCommandService.splitShortcuts
            },
            notifications: { [weak browserManager] in
                browserManager?.notificationPresenter
            }
        )
        self.shortcutLiveTabClose = shortcutLiveTabClose

        closeOrchestration = BrowserTabCloseOrchestrationOwner(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs.currentTab(for: windowState)
            },
            glanceManager: browserManager.glanceManager,
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            fallbackPlanner: { closeFallbackPlanner },
            shortcutLiveTabCloseService: { shortcutLiveTabClose },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                _ = browserManager?.shellRuntime.windowVisuals.performImmediateVisualHandoffIfPossible(
                    in: windowState
                )
            },
            showEmptyState: { [weak browserManager] windowState in
                browserManager?.showEmptyState(in: windowState)
            },
            persistWindowSession: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            }
        )
        opening = BrowserTabOpeningOwner(
            browserManager: browserManager
        )
    }

    private static func selectTabWithoutPersistence(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        browserManager: BrowserManager?
    ) {
        browserManager?.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: false
        )
    }
}
