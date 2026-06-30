import Foundation
import WebKit

@MainActor
enum BrowserManagerWebViewCoordinatorRuntimeFactory {
    static func browserRuntimeContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorBrowserRuntimeContext {
        WebViewCoordinatorBrowserRuntimeContext(
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            regularTabs: { [weak browserManager] in
                browserManager?.tabManager.allTabs() ?? []
            },
            pinnedTabs: { [weak browserManager] in
                browserManager?.tabManager.allPinnedTabsAllProfiles ?? []
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            window: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            windowContaining: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)
            },
            closeTab: { [weak browserManager] tab, windowState in
                browserManager?.closeTab(tab, in: windowState)
            },
            removeTab: { [weak browserManager] tabId in
                browserManager?.tabManager.removeTab(tabId)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] tab in
                browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            },
            needsInitialDocumentExtensionContextLoad: { [weak browserManager] profileId in
                browserManager?.extensionsModule
                    .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId) == true
            },
            ensureInitialDocumentExtensionContextsLoaded: { [weak browserManager] profileId in
                await browserManager?.extensionsModule
                    .ensureInitialDocumentExtensionContextsLoadedIfNeeded(profileId: profileId)
            },
            cleanupUserScripts: { [weak browserManager] controller, webViewId in
                browserManager?.userscriptsModule.cleanupWebViewIfLoaded(
                    controller: controller,
                    webViewId: webViewId
                )
            },
            globallyVisibleTabIDs: { [weak browserManager] in
                browserManager?.tabSuspensionService.suspensionEvaluationContext().visibleTabIDs ?? []
            }
        )
    }

    static func visiblePreparationContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorVisibleRuntimeContext {
        WebViewCoordinatorVisibleRuntimeContext(
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTabId: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)?.id
            },
            splitVisibleTabIds: { [weak browserManager] windowId in
                browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
            },
            resolveTab: { [weak browserManager] tabId, windowState in
                if windowState.isIncognito,
                   let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                    return ephemeralTab
                }
                return browserManager?.tabManager.tab(for: tabId)
            },
            canMaterializeNormalTabWebViewDuringStartup: { [weak browserManager] tab in
                browserManager?.canMaterializeNormalTabWebViewDuringStartup(tab) == true
            },
            markTabAccessed: { [weak browserManager] tabId in
                browserManager?.compositorManager.markTabAccessed(tabId)
            },
            globallyVisibleTabIDs: { [weak browserManager] in
                browserManager?.tabSuspensionService.suspensionEvaluationContext().visibleTabIDs ?? []
            },
            scheduleTabSuspensionReconcile: { [weak browserManager] reason in
                browserManager?.tabSuspensionService.scheduleProactiveTimerReconcile(reason: reason)
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            }
        )
    }
}
