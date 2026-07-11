import AppKit
import Foundation
import SwiftUI
import WebKit

@MainActor
enum TabBrowserActionServiceFactory {
    static func make(for browserManager: BrowserManager) -> TabBrowserActionService {
        TabBrowserActionService(
            hasBrowserRuntime: { [weak browserManager] in
                browserManager != nil
            },
            webPageMenuAppearance: { [weak browserManager] tab, fallback in
                guard let browserManager else { return fallback }
                return webPageMenuAppearance(
                    for: tab,
                    fallback: fallback,
                    browserManager: browserManager
                )
            },
            canBookmark: { [weak browserManager] tab in
                browserManager?.bookmarkManager.canBookmark(tab) ?? false
            },
            requestBookmarkEditorFromMenu: { [weak browserManager] in
                browserManager?.bookmarkBundle.bookmarkCommandOwner.requestBookmarkEditorForActiveWindowFromMenu()
            },
            canStartContextMenuDownload: { [weak browserManager] in
                browserManager != nil
            },
            startContextMenuDownload: { [weak browserManager] webView, request in
                guard let browserManager else { return }
                startContextMenuDownload(
                    webView: webView,
                    request: request,
                    browserManager: browserManager
                )
            },
            openURLInForegroundTab: { [weak browserManager] url, tab in
                guard let browserManager else { return }
                openURLInForegroundTab(url, from: tab, browserManager: browserManager)
            },
            openURLsInNewWindow: { [weak browserManager] urls in
                browserManager?.historyBundle.historyNavigationOwner.openURLsInNewWindow(urls)
            },
            notificationPermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.notificationPermissionBridge
            },
            shortcutLaunchURL: { [weak browserManager] shortcutPinId in
                browserManager?.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: shortcutPinId)?.launchURL
            },
            reconcileExtensionRuntimeOnUserGesture: { [weak browserManager] tab, reason in
                browserManager?.optionalModules.extensions.reconcileExtensionRuntimeOnUserGestureIfNeeded(
                    tab,
                    reason: reason
                )
            },
            isCurrentTab: { [weak browserManager] tab in
                guard let browserManager else { return false }
                return isCurrentTab(tab, browserManager: browserManager)
            },
            activate: { [weak browserManager] tab in
                browserManager?.tabManager.activeSelectionOwner.setActiveTab(tab)
            }
        )
    }

    private static func webPageMenuAppearance(
        for tab: Tab,
        fallback: NSAppearance?,
        browserManager: BrowserManager
    ) -> NSAppearance? {
        guard let windowState = browserManager.shellRuntime.windowTabs.windowState(containing: tab),
              let settings = browserManager.sumiSettings
        else {
            return fallback
        }
        return windowState.nativeSurfaceAppearance(
            settings: settings,
            fallback: fallback,
            in: browserManager.windowRegistry
        )
    }

    private static func startContextMenuDownload(
        webView: WKWebView,
        request: URLRequest,
        browserManager: BrowserManager
    ) {
        guard let url = request.url else { return }

        let callback: @MainActor @Sendable (WKDownload) -> Void = { [weak browserManager] download in
            _ = browserManager?.downloadManager.addDownload(
                download,
                originalURL: url,
                suggestedFilename: DownloadFileUtilities.suggestedFilename(
                    response: nil,
                    requestURL: url,
                    fallback: "download"
                )
            )
        }
        webView.startDownload(using: request, completionHandler: callback)
    }

    private static func openURLInForegroundTab(
        _ url: URL,
        from tab: Tab,
        browserManager: BrowserManager
    ) {
        guard let windowState = browserManager.shellRuntime.windowTabs.windowState(containing: tab) else { return }

        _ = browserManager.tabLifecycleService.opening.openNewTab(
            url: url.absoluteString,
            context: .foreground(
                windowState: windowState,
                preferredSpaceId: tab.spaceId
            )
        )
    }

    private static func isCurrentTab(_ tab: Tab, browserManager: BrowserManager) -> Bool {
        guard let windowState = browserManager.shellRuntime.windowTabs.windowState(containing: tab) else { return false }
        return browserManager.shellRuntime.windowTabs.currentTab(for: windowState)?.id == tab.id
    }
}
