//
//  BrowserExtensionBridgeBundle.swift
//  Sumi
//
//  Phase 5A capability bag: extension ↔ browser bridge adapter.
//

import Foundation

/// Holds the extension bridge adapter so BrowserManager does not grow another
/// peer lazy for extension surface wiring.
@MainActor
final class BrowserExtensionBridgeBundle {
    let adapter: BrowserExtensionBridgeAdapter

    init(browserManager: BrowserManager) {
        self.adapter = BrowserExtensionBridgeAdapter(
            windowRegistry: { [weak browserManager] in
                browserManager?.windowRegistry
            },
            tabManager: { [weak browserManager] in
                browserManager?.tabManager
            },
            auxiliaryWindowManager: { [weak browserManager] in
                browserManager?.auxiliaryWindowManager
            },
            webViewCoordinator: { [weak browserManager] in
                browserManager?.webViewCoordinator
            },
            tabsForWebExtensionWindow: { [weak browserManager] windowState in
                guard let browserManager else { return [] }
                return browserManager.shellSelectionService.tabsForWebExtensionWindow(
                    in: windowState,
                    tabStore: browserManager.tabManager.runtimeStore
                )
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.tabContextOwner.currentTab(for: windowState)
            },
            currentTabForActiveWindow: { [weak browserManager] in
                browserManager?.urlBarBundle.activePageRoutingOwner.currentTabForActiveWindow()
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowSessionBundle.tabContextOwner.windowState(containing: tab)
            },
            selectTab: { [weak browserManager] tab, windowState in
                browserManager?.selectTab(tab, in: windowState)
            },
            materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            windowOwnedWebView: { [weak browserManager] tab, windowId in
                browserManager?.webViewRoutingService.windowOwnedWebView(for: tab, in: windowId)
            },
            assignWebView: { [weak browserManager] webView, tab, windowId in
                browserManager?.webViewRoutingService.assignWebView(webView, to: tab, in: windowId)
            },
            installUntrackedOwnedWebView: { [weak browserManager] webView, tab in
                browserManager?.webViewRoutingService.installUntrackedOwnedWebView(webView, for: tab)
            },
            replaceLiveWebView: { [weak browserManager] tab, windowId, reason, prepareConfiguration, prepareReplacement, validate in
                browserManager?.webViewRoutingService.replaceLiveWebView(
                    for: tab,
                    in: windowId,
                    reason: reason,
                    prepareConfiguration: prepareConfiguration,
                    prepareReplacement: prepareReplacement,
                    validate: validate
                )
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowSessionBundle.commands.createNewWindow()
            },
            urlBarHubAnchorView: { [weak browserManager] windowId in
                browserManager?.chromeBundle.commands.urlBarHubPopoverPresenter.anchorView(
                    for: windowId
                )
            },
            sumiSettings: { [weak browserManager] in
                browserManager?.sumiSettings
            }
        )
    }
}
