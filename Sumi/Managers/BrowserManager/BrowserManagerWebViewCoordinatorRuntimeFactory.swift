import Foundation
import WebKit

@MainActor
enum BrowserWebViewRuntimeFactory {
    static func browserRuntimeContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorBrowserRuntimeContext {
        WebViewCoordinatorBrowserRuntimeContext(
            tabManager: { [weak browserManager] in
                requireBrowserManager(browserManager, operation: "resolve TabManager").tabManager
            },
            tab: { [weak browserManager] tabId in
                requireBrowserManager(browserManager, operation: "resolve tab").tabManager.tab(for: tabId)
            },
            regularTabs: { [weak browserManager] in
                requireBrowserManager(browserManager, operation: "list regular tabs").tabManager.allTabs()
            },
            pinnedTabs: { [weak browserManager] in
                requireBrowserManager(
                    browserManager,
                    operation: "list pinned tabs"
                ).tabManager.allPinnedTabsAllProfiles
            },
            allWindows: { [weak browserManager] in
                requireWindowRegistry(browserManager, operation: "list windows").allWindows
            },
            window: { [weak browserManager] windowId in
                requireWindowRegistry(browserManager, operation: "resolve window").windows[windowId]
            },
            windowContaining: { [weak browserManager] tab in
                requireBrowserManager(browserManager, operation: "resolve tab window").windowState(containing: tab)
            },
            currentTab: { [weak browserManager] windowState in
                requireBrowserManager(browserManager, operation: "resolve current tab").currentTab(for: windowState)
            },
            handleUnprotectedWebViewDidClose: { [weak browserManager] webView in
                requireBrowserManager(
                    browserManager,
                    operation: "handle unprotected WebKit close"
                ).webViewCloseRouter.handleNormalWebViewDidClose(webView)
            },
            refreshCompositor: { [weak browserManager] windowState in
                requireBrowserManager(
                    browserManager,
                    operation: "refresh compositor"
                ).refreshCompositor(for: windowState)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] tab in
                requireBrowserManager(
                    browserManager,
                    operation: "notify extension tab activation"
                ).extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            },
            globallyVisibleTabIDs: { [weak browserManager] in
                requireBrowserManager(
                    browserManager,
                    operation: "resolve globally visible tabs"
                ).tabSuspensionService.suspensionEvaluationContext().visibleTabIDs
            }
        )
    }

    static func initialDocumentContext(
        for browserManager: BrowserManager
    ) -> InitialDocumentWebViewRuntimeContext {
        InitialDocumentWebViewRuntimeContext(
            needsInitialDocumentExtensionContextLoad: { [weak browserManager] profileId in
                guard let browserManager else { return false }
                return browserManager.extensionsModule
                    .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId)
            },
            ensureInitialExtensionContextsLoaded: { [weak browserManager] profileId in
                guard let browserManager else { return }
                await browserManager.extensionsModule
                    .ensureInitialExtensionContextsIfNeeded(profileId: profileId)
            },
            refreshCompositorForWindow: { [weak browserManager] windowId in
                guard let browserManager = browserManager,
                      let windowState = browserManager.windowRegistry?.windows[windowId]
                else { return }
                browserManager.refreshCompositor(for: windowState)
            }
        )
    }

    static func shutdownContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorShutdownRuntimeContext {
        WebViewCoordinatorShutdownRuntimeContext(
            cleanupUserScripts: { [weak browserManager] controller, webViewId in
                requireBrowserManager(
                    browserManager,
                    operation: "cleanup user scripts"
                ).userscriptsModule.cleanupWebViewIfLoaded(
                    controller: controller,
                    webViewId: webViewId
                )
            }
        )
    }

    static func visiblePreparationContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorVisibleRuntimeContext {
        WebViewCoordinatorVisibleRuntimeContext(
            windowState: { [weak browserManager] windowId in
                requireWindowRegistry(browserManager, operation: "resolve visible window").windows[windowId]
            },
            currentTabId: { [weak browserManager] windowState in
                requireBrowserManager(browserManager, operation: "resolve visible current tab")
                    .currentTab(for: windowState)?.id
            },
            splitVisibleTabIds: { [weak browserManager] windowId in
                requireBrowserManager(browserManager, operation: "resolve split visible tabs")
                    .splitManager.visibleTabIds(for: windowId)
            },
            resolveTab: { [weak browserManager] tabId, windowState in
                if windowState.isIncognito,
                   let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                    return ephemeralTab
                }
                return requireBrowserManager(browserManager, operation: "resolve visible tab")
                    .tabManager.tab(for: tabId)
            },
            canMaterializeWebViewDuringStartup: { [weak browserManager] tab in
                requireBrowserManager(
                    browserManager,
                    operation: "check visible WebView startup materialization"
                ).canMaterializeWebViewDuringStartup(tab)
            },
            markTabAccessed: { [weak browserManager] tabId in
                requireBrowserManager(browserManager, operation: "mark visible tab accessed")
                    .compositorManager.markTabAccessed(tabId)
            },
            globallyVisibleTabIDs: { [weak browserManager] in
                requireBrowserManager(
                    browserManager,
                    operation: "resolve globally visible tabs"
                ).tabSuspensionService.suspensionEvaluationContext().visibleTabIDs
            },
            scheduleTabSuspensionReconcile: { [weak browserManager] reason in
                requireBrowserManager(browserManager, operation: "schedule tab suspension reconcile")
                    .tabSuspensionService.scheduleProactiveTimerReconcile(reason: reason)
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                requireBrowserManager(browserManager, operation: "schedule background media reconcile")
                    .backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            refreshCompositor: { [weak browserManager] windowState in
                requireBrowserManager(browserManager, operation: "refresh visible compositor")
                    .refreshCompositor(for: windowState)
            }
        )
    }

    private static func requireBrowserManager(
        _ browserManager: BrowserManager?,
        operation: String
    ) -> BrowserManager {
        guard let browserManager else {
            preconditionFailure(
                "WebViewCoordinator runtime cannot \(operation): BrowserManager was released."
            )
        }
        return browserManager
    }

    private static func requireWindowRegistry(
        _ browserManager: BrowserManager?,
        operation: String
    ) -> WindowRegistry {
        let browserManager = requireBrowserManager(browserManager, operation: operation)
        guard let windowRegistry = browserManager.windowRegistry else {
            preconditionFailure(
                "WebViewCoordinator runtime cannot \(operation): BrowserManager.windowRegistry is nil."
            )
        }
        return windowRegistry
    }
}
