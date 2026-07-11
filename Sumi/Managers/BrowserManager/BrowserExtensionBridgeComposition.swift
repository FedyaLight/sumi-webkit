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

    init(browserManager: BrowserManager) {
        let windows = BrowserExtensionWindowQueryAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            primaryTrackedWindowID: { [weak browserManager] tabID in
                browserManager?.webViewOwnershipQuery.primaryWindowID(
                    for: tabID
                )
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

        let tabMutation = BrowserExtensionTabMutationAdapter(
            createTab: { [weak browserManager] url, space, activate, context in
                guard let tabManager = browserManager?.tabManager else {
                    preconditionFailure(
                        "Browser runtime released before extension tab creation."
                    )
                }
                if let url {
                    return tabManager.regularTabLifecycleOwner.createNewTab(
                        url: url.absoluteString,
                        in: space,
                        activate: activate,
                        webExtensionContextOverride: context
                    )
                }
                return tabManager.regularTabLifecycleOwner.createNewTab(
                    in: space,
                    activate: activate,
                    webExtensionContextOverride: context
                )
            },
            createTransientTab: {
                [weak browserManager] url, space, context in
                guard let tabManager = browserManager?.tabManager else {
                    preconditionFailure(
                        "Browser runtime released before transient tab creation."
                    )
                }
                return tabManager.transientWebKitTabLifecycleOwner
                    .createTransientExtensionTab(
                        url: url.absoluteString,
                        in: space,
                        webExtensionContextOverride: context
                    )
            },
            pinTab: { [weak browserManager] tab, window, space in
                let targetSpaceID = space?.id ?? tab.spaceId
                browserManager?.tabManager.shortcutPinCommandOwner.pinTab(
                    tab,
                    context: .init(
                        windowState: window,
                        spaceId: targetSpaceID
                    )
                )
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            promoteTransientTab: { [weak browserManager] tab in
                guard let tabManager = browserManager?.tabManager,
                      tabManager.transientWebKitTabLifecycleOwner
                        .isTransientExtensionTab(tab),
                      let targetSpace = tab.spaceId.flatMap({ spaceID in
                        tabManager.spaceStateOwner.spaces.first {
                            $0.id == spaceID
                        }
                      })
                else {
                    return false
                }
                return tabManager.transientWebKitTabLifecycleOwner
                    .promoteTransientExtensionTab(
                        tab,
                        in: targetSpace,
                        activate: false
                    )
            }
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
                [weak browserManager]
                tab,
                windowID,
                reason,
                prepareConfiguration,
                prepareCommittedReplacement,
                validate in
                browserManager?.webViewOwnershipService?.replaceLiveWebView(
                    for: tab,
                    in: windowID,
                    reason: reason,
                    prepareConfiguration: prepareConfiguration,
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
            createWindow: { [weak browserManager] in
                browserManager?.windowCommands.createNewWindow()
            },
            urlHubAnchorView: { [weak browserManager] windowID in
                browserManager?.chromeBundle.commands
                    .urlBarHubPopoverPresenter.anchorView(for: windowID)
            },
            settings: { [weak browserManager] in
                browserManager?.sumiSettings
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
    }
}
