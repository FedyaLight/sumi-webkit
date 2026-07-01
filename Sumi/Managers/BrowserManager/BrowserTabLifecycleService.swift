import Foundation

@MainActor
final class BrowserTabLifecycleService {
    let selection = BrowserTabSelectionOwner()
    let closeFallbackPlanner: BrowserTabCloseFallbackPlanner
    let shortcutLiveTabClose: BrowserShortcutLiveTabCloseOwner
    let closeOrchestration: BrowserTabCloseOrchestrationOwner
    let opening: BrowserTabOpeningOwner

    init(browserManager: BrowserManager) {
        let closeFallbackPlanner = BrowserTabCloseFallbackPlanner(
            selectionService: browserManager.shellSelectionService
        )
        self.closeFallbackPlanner = closeFallbackPlanner

        let shortcutLiveTabClose = BrowserShortcutLiveTabCloseOwner(
            dependencies: BrowserShortcutLiveTabCloseOwner.Dependencies(
                tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                    browserManager?.tabManager ?? tabManager
                },
                recentlyClosedManager: { [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                    browserManager?.recentlyClosedManager ?? recentlyClosedManager
                },
                fallbackPlanner: { closeFallbackPlanner },
                selectTab: { [weak browserManager] tab, windowState in
                    browserManager?.selectTab(tab, in: windowState)
                },
                performImmediateVisualHandoffIfPossible: { [weak browserManager] windowState in
                    _ = browserManager?.performImmediateVisualHandoffIfPossible(in: windowState)
                },
                persistWindowSession: { [weak browserManager] windowState in
                    browserManager?.persistWindowSession(for: windowState)
                },
                showEmptyState: { [weak browserManager] windowState in
                    browserManager?.showEmptyState(in: windowState)
                },
                restoreShortcutSplitMember: { [weak browserManager] itemId, group, windowState, preserveLiveInstance in
                    browserManager?.sidebarCommandService.splitShortcutRouting.restoreShortcutSplitMember(
                        itemId,
                        from: group,
                        in: windowState,
                        preserveLiveInstance: preserveLiveInstance
                    )
                },
                unloadShortcutHostedSplitGroup: { [weak browserManager] group, windowState in
                    browserManager?.sidebarCommandService.splitShortcutRouting.unloadShortcutHostedSplitGroup(
                        group,
                        in: windowState
                    )
                }
            )
        )
        self.shortcutLiveTabClose = shortcutLiveTabClose

        closeOrchestration = BrowserTabCloseOrchestrationOwner(
            dependencies: BrowserTabCloseOrchestrationOwner.Dependencies(
                activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
                currentTab: { [weak browserManager] windowState in
                    browserManager?.currentTab(for: windowState)
                },
                glanceManager: browserManager.glanceManager,
                tabManager: { [weak browserManager, tabManager = browserManager.tabManager] in
                    browserManager?.tabManager ?? tabManager
                },
                fallbackPlanner: { closeFallbackPlanner },
                shortcutLiveTabCloseOwner: { shortcutLiveTabClose },
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
        )
        opening = BrowserTabOpeningOwner(
            dependencies: .live(browserManager: browserManager)
        )
    }
}
