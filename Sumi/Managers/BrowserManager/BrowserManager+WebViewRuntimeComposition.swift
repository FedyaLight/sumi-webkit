import Foundation
import SumiWebRuntime
import WebKit

extension BrowserManager {
    func composeWebViewRuntime() -> WebViewRuntimeGraph {
        let membership = tabCollectionMembershipOwner
        let windowTabs = windowTabContext
        let splitQuery = self.splitQuery
        let windowCommands = webViewWindowCommands
        return WebViewRuntimeGraph(
            webViewSessions: webViewSessions,
            resolveRuntimeTab: webViewRuntimeTabResolver(
                membership: membership
            ),
            resolveCollectionTab: { [membership] tabID in
                membership.tab(for: tabID)
            },
            windowServices: webViewWindowServices(
                windowTabs: windowTabs,
                commands: windowCommands
            ),
            deferredServices: deferredWebViewServices(
                tabAssignments: tabProfileTransitions,
                spaceAssignments: spaceProfileTransitions
            ),
            visibleContext: visibleWebViewRuntimeContext(
                membership: membership,
                windowTabs: windowTabs,
                splitQuery: splitQuery,
                commands: windowCommands
            ),
            initialDocumentContext: initialDocumentWebViewRuntimeContext(
                commands: windowCommands
            ),
            profileReferenceAdmission: profileReferenceAdmission,
            pageActivationPerformance: pageActivationPerformance
        )
    }

    private func webViewRuntimeTabResolver(
        membership: TabCollectionMembershipOwner
    ) -> WebViewRuntimeTabRegistry.RuntimeTabResolver {
        let windows = windowRegistry
        return { [membership, weak windows] tabID in
            if let tab = membership.tab(for: tabID) {
                return tab
            }
            return windows?.allWindows
                .lazy
                .flatMap(\.ephemeralTabs)
                .first { $0.id == tabID }
        }
    }

    private func webViewWindowServices(
        windowTabs: BrowserWindowTabContext,
        commands: BrowserWebViewWindowCommandChannel
    ) -> WebViewWindowServices {
        let windows = windowRegistry
        let extensions = optionalModules.extensions
        return WebViewWindowServices(
            liveWindowIDs: { [weak windows] in
                windows.map { Set($0.windows.keys) } ?? []
            },
            containsWindow: { [weak windows] windowID in
                windows?.windows[windowID] != nil
            },
            currentTabID: { [weak windows, weak windowTabs] windowID in
                guard let window = windows?.windows[windowID],
                      let windowTabs
                else { return nil }
                return windowTabs.currentTab(for: window)?.id
            },
            selectTab: { [commands] tabID, windowID in
                commands.selectTab(tabID, in: windowID)
            },
            refreshCompositor: { [commands] windowID in
                commands.refreshCompositor(in: windowID)
            },
            notifyTabActivatedIfCurrent: {
                [weak windows, weak windowTabs, extensions] tab, windowID in
                guard let window = windows?.windows[windowID],
                      windowTabs?.currentTab(for: window)?.id == tab.id else {
                    return
                }
                extensions.notifyTabActivatedIfLoaded(
                    newTab: tab,
                    previous: nil
                )
            }
        )
    }

    private func deferredWebViewServices(
        tabAssignments: TabProfileTransitionService,
        spaceAssignments: SpaceProfileTransitionService
    ) -> DeferredWebViewServices {
        let closeRequests = webViewCloseRequests
        return DeferredWebViewServices(
            handleWebKitClose: { [closeRequests] webView in
                closeRequests.requestClose(webView)
            },
            executeProfileAssignment: {
                [tabAssignments]
                tab,
                _,
                intent in
                tabAssignments.executeDeferred(
                        tab: tab,
                        intent: intent
                    )
            },
            validateSpaceProfileAssignment: {
                [spaceAssignments]
                intent in
                spaceAssignments.isCurrent(intent)
            },
            executeSpaceProfileAssignment: {
                [spaceAssignments]
                intent in
                spaceAssignments.executeDeferred(intent)
            }
        )
    }

    private func initialDocumentWebViewRuntimeContext(
        commands: BrowserWebViewWindowCommandChannel
    ) -> InitialDocumentWebViewRuntimeContext {
        let extensions = optionalModules.extensions
        return InitialDocumentWebViewRuntimeContext(
            needsInitialDocumentExtensionContextLoad: { [extensions] profileId in
                extensions
                    .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId)
            },
            ensureInitialExtensionContextsLoaded: { [extensions] profileId in
                await extensions
                    .ensureInitialExtensionContextsIfNeeded(profileId: profileId)
            },
            refreshCompositorForWindow: { [commands] windowID in
                commands.refreshCompositor(in: windowID)
            }
        )
    }

    private func visibleWebViewRuntimeContext(
        membership: TabCollectionMembershipOwner,
        windowTabs: BrowserWindowTabContext,
        splitQuery: WindowSplitQuery,
        commands: BrowserWebViewWindowCommandChannel
    ) -> WebViewVisibleRuntimeContext {
        let windows = windowRegistry
        let tabSuspensionController = tabSuspensionController
        let startupGate = startupMaterializationGate
        let compositor = compositorManager
        let pageResidency = pageResidency
        return WebViewVisibleRuntimeContext(
            windowState: { [weak windows] windowID in
                windows?.windows[windowID]
            },
            currentTabId: { [weak windowTabs] windowHandle in
                guard let windowState = windowHandle.concreteWindowState,
                      let windowTabs else { return nil }
                return windowTabs.currentTab(for: windowState)?.id
            },
            splitVisibleTabIds: { [weak splitQuery] windowId in
                splitQuery?.visibleTabIDs(in: windowId) ?? []
            },
            resolveTab: { [membership] tabId, windowHandle in
                guard let windowState = windowHandle.concreteWindowState else { return nil }
                if windowState.isIncognito,
                   let ephemeralTab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                    return ephemeralTab
                }
                return membership.tab(for: tabId)
            },
            canMaterializeWebViewDuringStartup: { [startupGate, membership] tabHandle, windowHandle in
                guard let windowState = windowHandle.concreteWindowState else {
                    return false
                }
                guard let tab = resolveVisibleTab(
                    matching: tabHandle,
                    in: windowState,
                    regularTab: membership.tab(for:)
                ) else {
                    return false
                }
                return startupGate.canMaterialize(tab)
            },
            markTabAccessed: { [compositor] tabID in
                compositor.markTabAccessed(tabID)
            },
            globallyVisibleTabIDs: { [weak tabSuspensionController] in
                tabSuspensionController?.globallyVisibleTabIDs() ?? []
            },
            scheduleTabSuspensionReconcile: { [weak pageResidency] reason in
                pageResidency?.schedule(reason: reason)
            },
            refreshCompositor: { [commands] windowID in
                commands.refreshCompositor(in: windowID)
            }
        )
    }
}
