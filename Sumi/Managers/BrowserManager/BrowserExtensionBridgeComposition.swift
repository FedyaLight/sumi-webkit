//
//  BrowserExtensionBridgeComposition.swift
//  Sumi
//
//  App-level construction of the browser capabilities exposed to WebExtensions.
//

import Foundation

/// Composition root only. Extension consumers receive the exact capability
/// they need; this type intentionally exposes no forwarding methods.
@MainActor
final class BrowserExtensionBridgeComposition {
    let windows: BrowserExtensionWindowQueryAdapter
    let tabs: BrowserExtensionTabQueryAdapter
    let requestedTabTargets: BrowserRequestedTabTargetAdapter
    let tabMutation: BrowserExtensionTabMutationAdapter
    let windowActivation: BrowserExtensionWindowActivationAdapter
    let webViews: BrowserExtensionWebViewAdapter
    let auxiliaryWindows: BrowserExtensionAuxiliaryWindowAdapter
    let presentation: BrowserExtensionWindowPresentationAdapter
    let requestedWindows: BrowserExtensionRequestedWindowTransaction

    init(browserManager: BrowserManager) {
        let webViewOwnershipQuery = browserManager.webViewRuntime.ownershipQuery
        let webViewOwnership = browserManager.webViewRuntime.ownershipService
        let windows = BrowserExtensionWindowQueryAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            primaryTrackedWindowID: { [webViewOwnershipQuery] tabID in
                webViewOwnershipQuery.primaryWindowID(for: tabID)
            },
            tabs: { [weak browserManager] windowState in
                guard let browserManager else { return [] }
                return browserManager.shellRuntime.windowSelection
                    .tabsForWebExtensionWindow(
                        in: windowState,
                        tabStore: browserManager.tabManager.runtimeStore
                    )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowTabs
                    .currentTab(for: windowState)
            },
            currentTabForActiveWindow: { [weak browserManager] in
                guard let browserManager,
                      let activeWindow = browserManager.windowRegistry?.activeWindow
                else { return nil }
                return browserManager.shellRuntime.windowTabs.currentTab(for: activeWindow)
            },
            windowContainingTab: { [weak browserManager] tab in
                browserManager?.shellRuntime.windowTabs
                    .windowState(containing: tab)
            }
        )

        let tabs = BrowserExtensionTabQueryAdapter(
            regularTab: { [weak browserManager] tabID in
                browserManager?.tabManager.tabCollectionMembershipOwner
                    .tab(for: tabID)
            },
            windows: {
                windows.allExtensionWindowStates
            },
            isTransient: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner
                    .isTransientExtensionTab(tab) ?? false
            },
            isAuxiliaryMiniWindow: { [weak browserManager] tab in
                browserManager?.tabManager.transientWebKitTabLifecycleOwner
                    .isAuxiliaryMiniWindowTab(tab) ?? false
            },
            isPinned: { [weak browserManager] tab in
                tab.isPinned || browserManager?.tabManager
                    .shortcutPresentationOwner.activeShortcutTabs()
                    .contains(where: { $0.id == tab.id }) == true
            }
        )

        let requestedTabTargets = BrowserRequestedTabTargetAdapter(
            windows: windows,
            space: { [weak browserManager] spaceID in
                browserManager?.tabManager.spaceStateOwner.space(
                    with: spaceID
                )
            },
            firstSpace: { [weak browserManager] profileID in
                browserManager?.tabManager.spaceStateOwner.firstSpace(
                    forProfile: profileID
                )
            },
            auxiliarySessions: browserManager.auxiliaryWindows.sessions
        )

        let tabMutation = BrowserExtensionTabMutationComposition.make(
            browserManager: browserManager
        )

        let windowActivation = BrowserExtensionWindowActivationAdapter(
            activate: { [weak browserManager] windowState in
                browserManager?.windowRegistry?.setActive(windowState)
            }
        )

        let webViews = BrowserExtensionWebViewAdapter(
            materializeVisible: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(
                    tab,
                    in: windowState
                )
            },
            windowOwnedWebView: { [weak browserManager] tab, windowID in
                browserManager?.webViewRoutingService.windowOwnedWebView(
                    for: tab,
                    in: windowID
                )
            },
            replaceLiveWebView: {
                [webViewOwnership]
                tab,
                windowID,
                reason,
                prepareCandidateConfiguration,
                prepareCommittedReplacement,
                validate in
                webViewOwnership.replaceLiveWebView(
                    for: tab,
                    in: windowID,
                    reason: reason,
                    prepareCandidateConfiguration: prepareCandidateConfiguration,
                    prepareCommittedReplacement: prepareCommittedReplacement,
                    validate: validate
                )
            },
            reload: { [weak browserManager] tab, webView, window, policy in
                guard let browserManager else { return .failed }
                if let window {
                    guard browserManager.webViewRoutingService
                        .windowOwnedWebView(for: tab, in: window.id) === webView
                    else {
                        return .failed
                    }
                    return browserManager.webViewRoutingService.refreshPage(
                        for: tab,
                        in: window,
                        reason: "ExtensionTabAdapter.reload",
                        policy: policy
                    )
                }

                guard tab.webViewSession.untrackedWebView === webView else {
                    return .failed
                }
                return tab.navigationCommandOwner.refresh(
                    tab,
                    resolvedWebView: { [weak tab] in
                        tab?.webViewSession.untrackedWebView
                    },
                    reason: "ExtensionTabAdapter.reload.untracked",
                    policy: policy,
                    deliverTrackedReload: { [weak tab] intent, policy in
                        guard let tab,
                              let currentWebView =
                                tab.webViewSession.untrackedWebView
                        else {
                            return .failed
                        }
                        return tab.navigationCommandOwner.submitExactReload(
                            on: currentWebView,
                            tab: tab,
                            intent: intent,
                            policy: policy
                        )
                    }
                )
            }
        )

        let auxiliaryWindows = BrowserExtensionAuxiliaryWindowAdapter(
            sessions: browserManager.auxiliaryWindows.sessions,
            focus: browserManager.auxiliaryWindows.focus,
            teardown: browserManager.auxiliaryWindows.teardown
        )

        let presentation = BrowserExtensionWindowPresentationAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            windowQuery: windows,
            popups: browserManager.auxiliaryWindows.popups,
            extensionWindows: browserManager.auxiliaryWindows.extensionWindows,
            urlHubAnchorView: { [weak browserManager] windowID in
                browserManager?.chromeBundle.commands
                    .urlBarHubPopoverPresenter.anchorView(for: windowID)
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
        let requestedWindows = BrowserExtensionRequestedWindowTransaction(
            commands: browserManager.windowCommands,
            restoration: browserManager.windowSessionBundle.restoreService,
            extensionPublication: browserManager.windowExtensionPublication,
            tabs: browserManager.tabManager,
            webViews: browserManager.webViewRuntime.lifecycleService,
            ownership: webViewOwnershipQuery,
            registeredWindow: { [weak browserManager] windowID in
                browserManager?.windowRegistry?.windows[windowID]
            },
            materialize: { [weak browserManager] tab, window in
                guard let browserManager else { return nil }
                browserManager.materializeVisibleTabWebViewIfNeeded(
                    tab,
                    in: window
                )
                return browserManager.webViewRuntime.ownershipQuery.webView(
                    for: tab.id,
                    in: window.id
                ) as? FocusableWKWebView
            },
            rollbackRegisteredWindow: { [weak browserManager] window in
                guard let registry = browserManager?.windowRegistry,
                      registry.windows[window.id] === window
                else {
                    return false
                }
                let appKitWindow = registry.appKitWindow(for: window)
                guard registry.discardRejectedRegistration(window) else {
                    return false
                }
                appKitWindow?.close()
                return registry.windows[window.id] !== window
            },
            persistWindow: { [weak browserManager] window in
                browserManager?.windowSessionBundle.persistence.persist(window)
            }
        )

        self.windows = windows
        self.tabs = tabs
        self.requestedTabTargets = requestedTabTargets
        self.tabMutation = tabMutation
        self.windowActivation = windowActivation
        self.webViews = webViews
        self.auxiliaryWindows = auxiliaryWindows
        self.presentation = presentation
        self.requestedWindows = requestedWindows
    }
}
