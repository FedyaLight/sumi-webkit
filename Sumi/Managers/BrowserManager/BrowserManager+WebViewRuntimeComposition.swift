import Foundation
import SumiWebRuntime
import WebKit

extension BrowserManager {
    func composeWebViewRuntime() -> WebViewRuntimeGraph {
        WebViewRuntimeGraph(
            webViewSessions: webViewSessions,
            resolveRuntimeTab: webViewRuntimeTabResolver(),
            resolveCollectionTab: { [weak tabManager] tabID in
                tabManager?.tabCollectionMembershipOwner.tab(for: tabID)
            },
            windowServices: webViewWindowServices(),
            deferredServices: deferredWebViewServices(),
            visibleContext: visibleWebViewRuntimeContext(),
            initialDocumentContext: initialDocumentWebViewRuntimeContext()
        )
    }

    private func webViewRuntimeTabResolver() -> WebViewRuntimeTabRegistry.RuntimeTabResolver {
        let browserManager = self
        return { [weak browserManager] tabID in
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

    private func webViewWindowServices() -> WebViewWindowServices {
        let browserManager = self
        return WebViewWindowServices(
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
                let manager = BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "select fullscreen owner tab"
                )
                guard let windowState = manager.windowRegistry?.windows[windowId],
                      let tab = manager.tabManager.tabCollectionMembershipOwner.tab(for: tabId)
                else { return }
                manager.selectTab(tab, in: windowState)
            },
            refreshCompositor: { [weak browserManager] windowId in
                let manager = BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "refresh compositor"
                )
                guard let windowState = manager.windowRegistry?.windows[windowId] else {
                    return
                }
                manager.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            },
            notifyTabActivatedIfCurrent: { [weak browserManager] tab, windowID in
                let manager = BrowserManager.requireBrowserManager(
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

    private func deferredWebViewServices() -> DeferredWebViewServices {
        let browserManager = self
        return DeferredWebViewServices(
            handleWebKitClose: { [weak browserManager] webView in
                BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "handle unprotected WebKit close"
                ).webViewCloseRouter.handleNormalWebViewDidClose(webView)
            },
            executeProfileAssignment: {
                [weak browserManager]
                tab,
                _,
                intent in
                let manager = BrowserManager.requireBrowserManager(
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
                BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "validate deferred space profile assignment"
                ).tabManager.profileAssignments.spaceLifecycle.isCurrent(intent)
            },
            executeSpaceProfileAssignment: {
                [weak browserManager]
                intent in
                BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "execute deferred space profile assignment"
                ).tabManager.profileAssignments.spaces
                    .executeDeferred(intent)
            }
        )
    }

    private func initialDocumentWebViewRuntimeContext() -> InitialDocumentWebViewRuntimeContext {
        let browserManager = self
        return InitialDocumentWebViewRuntimeContext(
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

    private func visibleWebViewRuntimeContext() -> WebViewVisibleRuntimeContext {
        let browserManager = self
        let tabSuspensionController = browserManager.tabSuspensionController
        let splitQuery = browserManager.splitComposition.query
        return WebViewVisibleRuntimeContext(
            windowState: { [weak browserManager] windowId in
                BrowserManager.requireWindowRegistry(
                    browserManager,
                    operation: "resolve visible window"
                ).windows[windowId]
            },
            currentTabId: { [weak browserManager] windowHandle in
                guard let windowState = windowHandle.concreteWindowState else { return nil }
                return BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "resolve visible current tab"
                )
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
                return BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "resolve visible tab"
                )
                    .tabManager.tabCollectionMembershipOwner.tab(for: tabId)
            },
            canMaterializeWebViewDuringStartup: { [weak browserManager] tabHandle, windowHandle in
                guard let windowState = windowHandle.concreteWindowState else {
                    return false
                }
                let manager = BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "check visible WebView startup materialization"
                )
                guard let tab = resolveVisibleTab(
                    matching: tabHandle,
                    in: windowState,
                    regularTab: manager.tabManager.tabCollectionMembershipOwner.tab(for:)
                ) else {
                    return false
                }
                return manager.startupProtectionRuntime.canMaterializeWebViewDuringStartup(tab)
            },
            markTabAccessed: { [weak browserManager] tabId in
                BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "mark visible tab accessed"
                )
                    .compositorManager.markTabAccessed(tabId)
            },
            globallyVisibleTabIDs: { [weak tabSuspensionController] in
                tabSuspensionController?.globallyVisibleTabIDs() ?? []
            },
            scheduleTabSuspensionReconcile: { [weak tabSuspensionController] reason in
                tabSuspensionController?.scheduleReconciliation(reason: reason)
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "schedule background media reconcile"
                )
                    .backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            refreshCompositor: { [weak browserManager] windowId in
                let manager = BrowserManager.requireBrowserManager(
                    browserManager,
                    operation: "refresh visible compositor"
                )
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
