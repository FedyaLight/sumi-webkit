//
//  BrowserHistoryBundle.swift
//  Sumi
//
//  Phase T3/T7 capability bag: history navigation (back/forward + open) + history menu.
//

import Foundation

/// Groups history-adjacent BrowserManager owners so BM no longer holds separate
/// peer `lazy var` Owners for navigation and menu restore.
///
/// Navigation is a thin façade over back/forward and open-URL collaborators
/// constructed inside `BrowserHistoryNavigationOwner` (not BM lazy Owners).
@MainActor
final class BrowserHistoryBundle {
    let historyNavigationOwner: BrowserHistoryNavigationOwner
    let historyMenuOwner: BrowserHistoryMenuOwner

    init(browserManager: BrowserManager) {
        self.historyNavigationOwner = BrowserHistoryNavigationOwner(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePageTab(for: windowState)
            },
            activePageWebView: { [weak browserManager] windowState in
                browserManager?.urlBarBundle.activePageRoutingOwner.activePageWebView(for: windowState)
            },
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.webViewCoordinator?.getWebView(for: tabId, in: windowId)
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState, preferredSpaceId in
                browserManager?.chromeBundle.nativeSurfaceRoutingOwner.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: windowState,
                    preferredSpaceId: preferredSpaceId
                )
            },
            openNewTab: { [weak browserManager] url, context in
                browserManager?.tabLifecycleService.opening.openNewTab(url: url, context: context)
            },
            loadCurrentPageURL: { [weak browserManager] tab, windowState, url in
                browserManager?.windowSessionBundle.scopedNavigationOwner.loadWindowScopedPage(
                    url,
                    tab: tab,
                    in: windowState,
                    reason: "BrowserHistoryNavigation.currentPage"
                )
            },
            windowIds: { [weak browserManager] in
                browserManager?.windowRegistry.map { Array($0.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowSessionBundle.commands.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIDs in
                await browserManager?.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.visualMutationOwner.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.visualMutationOwner.refreshCompositor(for: windowState)
            },
            navigateBack: { webView in
                SumiWebViewNavigator.goBack(on: webView)
            },
            navigateForward: { webView in
                SumiWebViewNavigator.goForward(on: webView)
            }
        )
        self.historyMenuOwner = BrowserHistoryMenuOwner(
            browserManager: browserManager
        )
    }
}
