import Foundation
import WebKit

@MainActor
enum BrowserUserscriptRuntimeFactory {
    private struct SourceContext {
        let tab: Tab
        let openerTab: Tab?
        let windowState: BrowserWindowState?
        let spaceId: UUID?

        var tabForOpeningPlacement: Tab {
            openerTab ?? tab
        }
    }

    static func runtime(for browserManager: BrowserManager) -> SumiScriptsManagerRuntime {
        SumiScriptsManagerRuntime(
            injectorRuntime: { [weak browserManager] in
                guard let browserManager else { return .inactive }
                return injectorRuntime(for: browserManager)
            },
            openTab: { [weak browserManager] url, background, sourceWebView in
                guard let browserManager else { return }
                openUserscriptTab(
                    url: url,
                    background: background,
                    sourceWebView: sourceWebView,
                    browserManager: browserManager
                )
            },
            closeTab: { [weak browserManager] tabId, sourceWebView in
                guard let browserManager else { return }
                closeUserscriptTab(
                    tabId: tabId,
                    sourceWebView: sourceWebView,
                    browserManager: browserManager
                )
            }
        )
    }

    static func injectorRuntime(for browserManager: BrowserManager) -> UserScriptInjectorRuntime {
        UserScriptInjectorRuntime(
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            },
            notificationPermissionBridge: { [weak browserManager] in
                browserManager?.permissionRuntime.notificationPermissionBridge
            },
            notificationTabContext: { [weak browserManager] webViewId, webView in
                browserManager?.tabManager.tab(for: webViewId)?
                    .webNotificationTabContext(for: webView)
            }
        )
    }

    private static func openUserscriptTab(
        url: String,
        background: Bool,
        sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) {
        let sourceContext = userscriptSourceContext(
            for: sourceWebView,
            browserManager: browserManager
        )
        let fallbackWindow = sourceWebView == nil ? browserManager.windowRegistry?.activeWindow : nil
        let targetWindow = sourceContext?.windowState ?? fallbackWindow
        let preferredSpaceId = sourceContext?.spaceId ?? targetWindow?.currentSpaceId
        let openContext: BrowserTabOpenContext
        if background {
            openContext = .background(
                windowState: targetWindow,
                sourceTab: sourceContext?.tabForOpeningPlacement,
                preferredSpaceId: preferredSpaceId
            )
        } else if let targetWindow {
            openContext = .foreground(
                windowState: targetWindow,
                sourceTab: sourceContext?.tabForOpeningPlacement,
                preferredSpaceId: preferredSpaceId
            )
        } else {
            guard let targetSpace = preferredSpaceId.flatMap({ spaceId in
                browserManager.tabManager.spaces.first { $0.id == spaceId }
            }) else { return }
            _ = browserManager.tabManager.createNewTab(
                url: url,
                in: targetSpace,
                activate: false
            )
            return
        }
        browserManager.openNewTab(url: url, context: openContext)
    }

    private static func closeUserscriptTab(
        tabId: String?,
        sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) {
        if let tabId, let uuid = UUID(uuidString: tabId) {
            closeUserscriptTab(
                uuid,
                sourceWebView: sourceWebView,
                browserManager: browserManager
            )
        } else if let sourceContext = userscriptSourceContext(
            for: sourceWebView,
            browserManager: browserManager
        ) {
            closeUserscriptTab(sourceContext.tab, sourceContext.windowState, browserManager)
        } else if sourceWebView == nil,
                  let activeWindow = browserManager.windowRegistry?.activeWindow,
                  let activeTab = browserManager.currentTab(for: activeWindow) {
            browserManager.closeTab(activeTab, in: activeWindow)
        }
    }

    private static func userscriptSourceContext(
        for sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) -> SourceContext? {
        guard let sourceWebView else { return nil }

        if let auxiliarySession = browserManager.auxiliaryWindowManager.session(for: sourceWebView) {
            let openerWindowState = auxiliarySession.openerWindow.flatMap {
                browserManager.windowRegistry?.windowState(containing: $0)
            }
            let sourceTab = auxiliarySession.openerTab ?? auxiliarySession.tab
            return SourceContext(
                tab: auxiliarySession.tab,
                openerTab: auxiliarySession.openerTab,
                windowState: openerWindowState,
                spaceId: auxiliarySession.tab.spaceId ?? sourceTab.spaceId ?? openerWindowState?.currentSpaceId
            )
        }

        guard let owner = browserManager.trackedWebViewOwner(containing: sourceWebView),
              let tab = browserManager.tabManager.tab(for: owner.tabID)
        else {
            return nil
        }

        let windowState = browserManager.windowRegistry?.windows[owner.windowID]
        return SourceContext(
            tab: tab,
            openerTab: nil,
            windowState: windowState,
            spaceId: tab.spaceId ?? windowState?.currentSpaceId
        )
    }

    private static func closeUserscriptTab(
        _ tabId: UUID,
        sourceWebView: WKWebView?,
        browserManager: BrowserManager
    ) {
        guard let tab = browserManager.tabManager.tab(for: tabId) else { return }
        let sourceWindow = userscriptSourceContext(
            for: sourceWebView,
            browserManager: browserManager
        )?.windowState
        let windowState = browserManager.windowState(containing: tab) ?? sourceWindow
        closeUserscriptTab(tab, windowState, browserManager)
    }

    private static func closeUserscriptTab(
        _ tab: Tab,
        _ windowState: BrowserWindowState?,
        _ browserManager: BrowserManager
    ) {
        if browserManager.tabManager.isAuxiliaryMiniWindowTab(tab) {
            browserManager.webViewCloseRouter.closeAuxiliaryMiniWindow(for: tab, reason: .extensionRequestedClose)
            return
        }

        if let windowState {
            browserManager.closeTab(tab, in: windowState)
        } else {
            browserManager.tabManager.removeTab(tab.id)
        }
    }
}
