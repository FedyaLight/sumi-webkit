import Foundation
import WebKit
import SumiWebRuntime

@MainActor
enum BrowserWebViewRuntimeFactory {
    static func make(
        for browserManager: BrowserManager
    ) -> WebViewRuntimeGraph {
        WebViewRuntimeGraph(
            webViewSessions: browserManager.webViewSessions,
            resolveRuntimeTab: runtimeTabResolver(for: browserManager),
            resolveCollectionTab: { [weak browserManager] tabID in
                browserManager?.tabManager.tabCollectionMembershipOwner.tab(for: tabID)
            },
            windowServices: windowServices(for: browserManager),
            deferredServices: deferredServices(for: browserManager),
            visibleContext: visiblePreparationContext(for: browserManager),
            initialDocumentContext: initialDocumentContext(for: browserManager)
        )
    }

    private static func runtimeTabResolver(
        for browserManager: BrowserManager
    ) -> WebViewRuntimeTabRegistry.RuntimeTabResolver {
        { [weak browserManager] tabID in
            guard let manager = browserManager else { return nil }
            if let tab = manager.tabManager.tabCollectionMembershipOwner
                .tab(for: tabID) {
                return tab
            }
            return manager.windowRegistry?.allWindows
                .lazy
                .flatMap(\.ephemeralTabs)
                .first { $0.id == tabID }
        }
    }

    private static func windowServices(
        for browserManager: BrowserManager
    ) -> WebViewWindowServices {
        WebViewWindowServices(
            liveWindowIDs: { [weak browserManager] in
                guard let windowIDs = browserManager?.windowRegistry?.windows.keys
                else { return [] }
                return Set(windowIDs)
            },
            containsWindow: { [weak browserManager] windowID in
                browserManager?.windowRegistry?.windows[windowID] != nil
            },
            currentTabID: { [weak browserManager] windowID in
                guard let manager = browserManager,
                      let window = manager.windowRegistry?.windows[windowID]
                else { return nil }
                return manager.shellRuntime.windowTabs.currentTab(for: window)?.id
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
            notifyTabActivatedIfCurrent: { [weak browserManager] tab, windowID in
                let manager = requireBrowserManager(
                    browserManager,
                    operation: "notify extension tab activation"
                )
                guard let window = manager.windowRegistry?.windows[windowID],
                      manager.shellRuntime.windowTabs.currentTab(for: window)?.id
                        == tab.id else {
                    return
                }
                manager.optionalModules.extensions.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            }
        )
    }

    private static func deferredServices(
        for browserManager: BrowserManager
    ) -> DeferredWebViewServices {
        DeferredWebViewServices(
            handleWebKitClose: { [weak browserManager] webView in
                requireBrowserManager(
                    browserManager,
                    operation: "handle unprotected WebKit close"
                ).webViewCloseRouter.handleNormalWebViewDidClose(webView)
            },
            executeProfileAssignment: {
                [weak browserManager]
                tab,
                _,
                intent in
                let manager = requireBrowserManager(
                    browserManager,
                    operation: "execute deferred profile assignment"
                )
                return manager.tabManager.profileAssignments.tabs
                    .executeDeferred(
                        tab: tab,
                        intent: intent
                    )
            },
            validateSpaceProfileAssignment: {
                [weak browserManager]
                intent in
                requireBrowserManager(
                    browserManager,
                    operation: "validate deferred space profile assignment"
                ).tabManager.profileAssignments.spaces
                    .isCurrentDeferred(intent)
            },
            executeSpaceProfileAssignment: {
                [weak browserManager]
                intent in
                requireBrowserManager(
                    browserManager,
                    operation: "execute deferred space profile assignment"
                ).tabManager.profileAssignments.spaces
                    .executeDeferred(intent)
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

    private static func visiblePreparationContext(
        for browserManager: BrowserManager
    ) -> WebViewVisibleRuntimeContext {
        let tabSuspensionController = browserManager.tabSuspensionController
        let splitQuery = browserManager.splitComposition.query
        return WebViewVisibleRuntimeContext(
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
                "WebView runtime cannot \(operation): BrowserManager was released."
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
                "WebView runtime cannot \(operation): BrowserManager.windowRegistry is nil."
            )
        }
        return windowRegistry
    }
}
