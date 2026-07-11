//
//  BrowserHistoryBundle.swift
//  Sumi
//
//  Phase T3/T7 capability bag: history navigation and clear-history command.
//

import Foundation

/// Groups history navigation with the user-facing clear-history command.
///
/// Navigation is a thin façade over back/forward and open-URL collaborators
/// constructed inside `BrowserHistoryNavigationOwner` (not BM lazy Owners).
@MainActor
final class BrowserHistoryBundle {
    let historyNavigationOwner: BrowserHistoryNavigationOwner
    let clearHistory: BrowserHistoryClearCommand

    init(browserManager: BrowserManager) {
        self.historyNavigationOwner = BrowserHistoryNavigationOwner(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            activePage: { [weak browserManager] windowState in
                browserManager?.shellRuntime.activePageResolver
                    .resolve(in: windowState)
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
                browserManager?.webViewRoutingService.loadPage(
                    url,
                    for: tab,
                    in: windowState,
                    reason: "BrowserHistoryNavigation.currentPage"
                )
            },
            windowIds: { [weak browserManager] in
                browserManager?.windowRegistry.map { Array($0.windows.keys) } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.windowCommands.createNewWindow()
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
                browserManager?.shellRuntime.windowVisuals.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.shellRuntime.windowVisuals.refreshCompositor(for: windowState)
            },
            navigateBack: { webView in
                SumiWebViewNavigator.goBack(on: webView)
            },
            navigateForward: { webView in
                SumiWebViewNavigator.goForward(on: webView)
            }
        )
        self.clearHistory = BrowserHistoryClearCommand(
            browserManager: browserManager
        )
    }
}
