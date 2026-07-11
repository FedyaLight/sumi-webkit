import Foundation
import WebKit
import SumiWebRuntime

@MainActor
enum BrowserWebViewRuntimeFactory {
    static func environment(
        for browserManager: BrowserManager
    ) -> WebViewRuntimeEnvironment {
        WebViewRuntimeEnvironment(
            visible: visiblePreparationContext(for: browserManager),
            browser: browserRuntimeContext(for: browserManager),
            initialDocument: initialDocumentContext(for: browserManager),
            shutdown: shutdownContext(for: browserManager)
        )
    }

    private static func browserRuntimeContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorBrowserRuntimeContext {
        let tabSuspensionController = browserManager.tabSuspensionController
        return WebViewCoordinatorBrowserRuntimeContext(
            tab: { [weak browserManager] tabId in
                requireBrowserManager(browserManager, operation: "resolve tab").tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            regularTabs: { [weak browserManager] in
                requireBrowserManager(browserManager, operation: "list regular tabs").tabManager.tabCollectionMembershipOwner.allTabs()
            },
            pinnedTabs: { [weak browserManager] in
                requireBrowserManager(
                    browserManager,
                    operation: "list pinned tabs"
                ).tabManager.shortcutPresentationOwner.activeShortcutTabs(role: .essential)
            },
            allWindows: { [weak browserManager] in
                requireWindowRegistry(browserManager, operation: "list windows").allWindows
            },
            window: { [weak browserManager] windowId in
                requireWindowRegistry(browserManager, operation: "resolve window").windows[windowId]
            },
            windowContaining: { [weak browserManager] tabHandle in
                guard let tab = tabHandle.concreteTab else { return nil }
                return requireBrowserManager(browserManager, operation: "resolve tab window")
                    .shellRuntime.windowTabs.windowState(containing: tab)
            },
            currentTab: { [weak browserManager] windowHandle in
                guard let windowState = windowHandle.concreteWindowState else { return nil }
                return requireBrowserManager(browserManager, operation: "resolve current tab")
                    .shellRuntime.windowTabs.currentTab(for: windowState)
            },
            selectTab: { [weak browserManager] tabId, windowId in
                let manager = requireBrowserManager(
                    browserManager,
                    operation: "select fullscreen owner tab"
                )
                guard let windowState = manager.windowRegistry?.windows[windowId],
                      let tab = manager.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
                else { return }
                manager.selectTab(tab, in: windowState)
            },
            handleUnprotectedWebViewDidClose: { [weak browserManager] webView in
                requireBrowserManager(
                    browserManager,
                    operation: "handle unprotected WebKit close"
                ).webViewCloseRouter.handleNormalWebViewDidClose(webView)
            },
            refreshCompositor: { [weak browserManager] windowId in
                let manager = requireBrowserManager(
                    browserManager,
                    operation: "refresh compositor"
                )
                guard let windowState = manager.windowRegistry?.windows[windowId] else {
                    return
                }
                manager.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            },
            notifyTabActivatedIfLoaded: { [weak browserManager] tabHandle in
                guard let tab = tabHandle.concreteTab else { return }
                requireBrowserManager(
                    browserManager,
                    operation: "notify extension tab activation"
                ).optionalModules.extensions.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            },
            executeDeferredProfileAssignment: {
                [weak browserManager]
                tabID,
                _,
                intent in
                let manager = requireBrowserManager(
                    browserManager,
                    operation: "execute deferred profile assignment"
                )
                guard let tab = manager.tabManager.tabCollectionMembershipOwner
                    .tab(for: tabID) else {
                    return false
                }
                return manager.tabManager.profileAssignments.tabs
                    .executeDeferred(
                        tab: tab,
                        intent: intent
                    )
            },
            validateDeferredSpaceProfileAssignment: {
                [weak browserManager]
                intent in
                requireBrowserManager(
                    browserManager,
                    operation: "validate deferred space profile assignment"
                ).tabManager.profileAssignments.spaces
                    .isCurrentDeferred(intent)
            },
            executeDeferredSpaceProfileAssignment: {
                [weak browserManager]
                intent in
                requireBrowserManager(
                    browserManager,
                    operation: "execute deferred space profile assignment"
                ).tabManager.profileAssignments.spaces
                    .executeDeferred(intent)
            },
            globallyVisibleTabIDs: { [weak tabSuspensionController] in
                tabSuspensionController?.globallyVisibleTabIDs() ?? []
            }
        )
    }

    private static func initialDocumentContext(
        for browserManager: BrowserManager
    ) -> InitialDocumentWebViewRuntimeContext {
        InitialDocumentWebViewRuntimeContext(
            needsInitialDocumentExtensionContextLoad: { [weak browserManager] profileId in
                guard let browserManager else { return false }
                return browserManager.optionalModules.extensions
                    .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId)
            },
            ensureInitialExtensionContextsLoaded: { [weak browserManager] profileId in
                guard let browserManager else { return }
                await browserManager.optionalModules.extensions
                    .ensureInitialExtensionContextsIfNeeded(profileId: profileId)
            },
            refreshCompositorForWindow: { [weak browserManager] windowId in
                guard let browserManager = browserManager,
                      let windowState = browserManager.windowRegistry?.windows[windowId]
                else { return }
                browserManager.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            }
        )
    }

    private static func shutdownContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorShutdownRuntimeContext {
        // Shutdown outlives BrowserManager in the app-shell fallback. Retain
        // only the manager-independent module that owns the injected script
        // bookkeeping; its own runtime ports reference BrowserManager weakly.
        let userscriptsModule = browserManager.optionalModules.userscripts
        return WebViewCoordinatorShutdownRuntimeContext(
            cleanupUserScripts: { controller, webViewId in
                userscriptsModule.cleanupWebViewIfLoaded(
                    controller: controller,
                    webViewId: webViewId
                )
            }
        )
    }

    private static func visiblePreparationContext(
        for browserManager: BrowserManager
    ) -> WebViewCoordinatorVisibleRuntimeContext {
        let tabSuspensionController = browserManager.tabSuspensionController
        let splitQuery = browserManager.splitComposition.query
        return WebViewCoordinatorVisibleRuntimeContext(
            windowState: { [weak browserManager] windowId in
                requireWindowRegistry(browserManager, operation: "resolve visible window").windows[windowId]
            },
            currentTabId: { [weak browserManager] windowHandle in
                guard let windowState = windowHandle.concreteWindowState else { return nil }
                return requireBrowserManager(browserManager, operation: "resolve visible current tab")
                    .shellRuntime.windowTabs.currentTab(for: windowState)?.id
            },
            splitVisibleTabIds: { [weak splitQuery] windowId in
                splitQuery?.visibleTabIDs(in: windowId) ?? []
            },
            resolveTab: { [weak browserManager] tabId, windowHandle in
                guard let windowState = windowHandle.concreteWindowState else { return nil }
                if windowState.isIncognito,
                   let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                    return ephemeralTab
                }
                return requireBrowserManager(browserManager, operation: "resolve visible tab")
                    .tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            canMaterializeWebViewDuringStartup: { [weak browserManager] tabHandle in
                guard let tab = tabHandle.concreteTab else { return false }
                return requireBrowserManager(
                    browserManager,
                    operation: "check visible WebView startup materialization"
                ).startupProtectionRuntime.canMaterializeWebViewDuringStartup(tab)
            },
            markTabAccessed: { [weak browserManager] tabId in
                requireBrowserManager(browserManager, operation: "mark visible tab accessed")
                    .compositorManager.markTabAccessed(tabId)
            },
            globallyVisibleTabIDs: { [weak tabSuspensionController] in
                tabSuspensionController?.globallyVisibleTabIDs() ?? []
            },
            scheduleTabSuspensionReconcile: { [weak tabSuspensionController] reason in
                tabSuspensionController?.scheduleReconciliation(reason: reason)
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                requireBrowserManager(browserManager, operation: "schedule background media reconcile")
                    .backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            refreshCompositor: { [weak browserManager] windowId in
                let manager = requireBrowserManager(browserManager, operation: "refresh visible compositor")
                guard let windowState = manager.windowRegistry?.windows[windowId] else {
                    return
                }
                manager.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
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
