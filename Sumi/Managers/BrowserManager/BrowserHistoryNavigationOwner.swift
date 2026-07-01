import AppKit
import SwiftUI
import WebKit

@MainActor
final class BrowserHistoryNavigationOwner {
    private typealias NewWindowRegistrationAwaiter = @MainActor () async -> BrowserWindowState?

    struct Dependencies {
        let activeWindow: @MainActor @Sendable () -> BrowserWindowState?
        let activePageTab: @MainActor @Sendable (BrowserWindowState) -> Tab?
        let activePageWebView: @MainActor @Sendable (BrowserWindowState) -> WKWebView?
        let webView: @MainActor @Sendable (UUID, UUID) -> WKWebView?
        let openNativeBrowserSurface: @MainActor @Sendable (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState,
            UUID?
        ) -> Void
        let openNewTab: @MainActor @Sendable (String, BrowserTabOpenContext) -> Tab?
        let loadCurrentPageURL: @MainActor @Sendable (Tab, BrowserWindowState, URL) -> Void
        let windowIds: @MainActor @Sendable () -> [UUID]
        let createNewWindow: @MainActor @Sendable () -> Void
        let awaitNextRegisteredWindow: @MainActor @Sendable (Set<UUID>) async -> BrowserWindowState?
        let scheduleRuntimeStatePersistence: @MainActor @Sendable (Tab) -> Void
        let schedulePrepareVisibleWebViews: @MainActor @Sendable (BrowserWindowState) -> Void
        let refreshCompositor: @MainActor @Sendable (BrowserWindowState) -> Void
        let navigateBack: @MainActor @Sendable (WKWebView) -> Void
        let navigateForward: @MainActor @Sendable (WKWebView) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var canGoBackInActiveWindow: Bool {
        guard let activeWindow = dependencies.activeWindow() else { return false }
        return canGoBack(in: activeWindow)
    }

    var canGoForwardInActiveWindow: Bool {
        guard let activeWindow = dependencies.activeWindow() else { return false }
        return canGoForward(in: activeWindow)
    }

    func canGoBack(in windowState: BrowserWindowState) -> Bool {
        activePageWebView(in: windowState)?.canGoBack ?? false
    }

    func canGoForward(in windowState: BrowserWindowState) -> Bool {
        activePageWebView(in: windowState)?.canGoForward ?? false
    }

    func goBackInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow() else { return }
        goBack(in: activeWindow)
    }

    func goForwardInActiveWindow() {
        guard let activeWindow = dependencies.activeWindow() else { return }
        goForward(in: activeWindow)
    }

    func goBack(in windowState: BrowserWindowState) {
        guard let webView = activePageWebView(in: windowState),
              webView.canGoBack
        else { return }
        dependencies.navigateBack(webView)
    }

    func goForward(in windowState: BrowserWindowState) {
        guard let webView = activePageWebView(in: windowState),
              webView.canGoForward
        else { return }
        dependencies.navigateForward(webView)
    }

    func openHistoryTab(
        selecting range: HistoryRange = .all,
        in windowState: BrowserWindowState? = nil
    ) {
        if let targetWindow = windowState ?? dependencies.activeWindow() {
            openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
            return
        }

        let awaitNewWindow = createNewWindowRegistrationAwaiter()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await awaitNewWindow()
            else {
                return
            }
            self.openHistoryTab(inResolvedWindow: targetWindow, selecting: range)
        }
    }

    func openHistoryURLFromMenuItem(_ url: URL) {
        if let activeWindow = dependencies.activeWindow() {
            openHistoryURL(url, in: activeWindow, preferredOpenMode: .currentTab)
        } else {
            openHistoryURLsInNewWindow([url])
        }
    }

    func openHistoryURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        preferredOpenMode: BrowserManager.HistoryOpenMode
    ) {
        switch preferredOpenMode {
        case .currentTab:
            if let currentTab = dependencies.activePageTab(windowState),
               !currentTab.representsSumiEmptySurface {
                if currentTab.representsSumiHistorySurface {
                    replaceNativeHistoryTab(currentTab, with: url, in: windowState)
                } else {
                    dependencies.loadCurrentPageURL(currentTab, windowState, url)
                }
            } else {
                openForegroundTab(for: url, in: windowState)
            }
        case .newTab:
            openForegroundTab(for: url, in: windowState)
        case .newWindow:
            openHistoryURLsInNewWindow([url])
        }
    }

    func openURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        for (index, url) in uniqueURLs.enumerated() {
            let context: BrowserTabOpenContext
            if index == 0 {
                context = .foreground(windowState: windowState)
            } else {
                context = .background(
                    windowState: windowState,
                    preferredSpaceId: windowState.currentSpaceId
                )
            }
            guard let tab = dependencies.openNewTab(url.absoluteString, context) else {
                continue
            }
            tab.name = displayName(for: url)
        }
    }

    func openHistoryURLsInNewTabs(_ urls: [URL], in windowState: BrowserWindowState) {
        openURLsInNewTabs(urls, in: windowState)
    }

    func openURLsInNewWindow(_ urls: [URL]) {
        let uniqueURLs = Array(NSOrderedSet(array: urls)).compactMap { $0 as? URL }
        guard !uniqueURLs.isEmpty else { return }

        let awaitNewWindow = createNewWindowRegistrationAwaiter()
        Task { @MainActor [weak self] in
            guard let self,
                  let targetWindow = await awaitNewWindow()
            else {
                return
            }
            self.openURLsInNewTabs(uniqueURLs, in: targetWindow)
        }
    }

    func openHistoryURLsInNewWindow(_ urls: [URL]) {
        openURLsInNewWindow(urls)
    }

    private func activePageWebView(in windowState: BrowserWindowState) -> WKWebView? {
        guard let currentTab = dependencies.activePageTab(windowState)
        else {
            return nil
        }
        return dependencies.activePageWebView(windowState)
            ?? dependencies.webView(currentTab.id, windowState.id)
    }

    private func openHistoryTab(
        inResolvedWindow targetWindow: BrowserWindowState,
        selecting range: HistoryRange
    ) {
        dependencies.openNativeBrowserSurface(
            .history,
            SumiSurface.historySurfaceURL(rangeQuery: range.paneQueryValue),
            targetWindow,
            targetWindow.currentSpaceId
        )
    }

    private func openForegroundTab(for url: URL, in windowState: BrowserWindowState) {
        guard let newTab = dependencies.openNewTab(
            url.absoluteString,
            .foreground(windowState: windowState)
        ) else { return }
        newTab.name = displayName(for: url)
    }

    private func replaceNativeHistoryTab(
        _ tab: Tab,
        with url: URL,
        in windowState: BrowserWindowState
    ) {
        tab.name = displayName(for: url)
        tab.favicon = Image(systemName: "globe")
        tab.faviconIsTemplateGlobePlaceholder = true
        dependencies.loadCurrentPageURL(tab, windowState, url)
        windowState.invalidateNativeSurfaceRouting()
        dependencies.scheduleRuntimeStatePersistence(tab)
        dependencies.schedulePrepareVisibleWebViews(windowState)
        dependencies.refreshCompositor(windowState)

        Task { @MainActor [weak tab] in
            guard let tab else { return }
            await tab.fetchFaviconForVisiblePresentation()
        }
    }

    private func createNewWindowRegistrationAwaiter() -> NewWindowRegistrationAwaiter {
        let existingWindowIDs = Set(dependencies.windowIds())
        dependencies.createNewWindow()

        return { [dependencies] in
            await dependencies.awaitNextRegisteredWindow(existingWindowIDs)
        }
    }

    private func displayName(for url: URL) -> String {
        url.host ?? url.absoluteString
    }
}

extension BrowserHistoryNavigationOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in browserManager?.windowRegistry?.activeWindow },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.activePageTab(for: windowState)
            },
            activePageWebView: { [weak browserManager] windowState in
                browserManager?.activePageWebView(for: windowState)
            },
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.webViewCoordinator?.getWebView(for: tabId, in: windowId)
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState, preferredSpaceId in
                browserManager?.openNativeBrowserSurface(
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
                browserManager?.loadWindowScopedPage(
                    url,
                    tab: tab,
                    in: windowState,
                    reason: "BrowserHistoryNavigation.currentPage"
                )
            },
            windowIds: { [weak browserManager] in
                browserManager?.windowRegistry?.windows.keys.map { $0 } ?? []
            },
            createNewWindow: { [weak browserManager] in
                browserManager?.createNewWindow()
            },
            awaitNextRegisteredWindow: { [weak browserManager] existingWindowIDs in
                await browserManager?.windowRegistry?.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            scheduleRuntimeStatePersistence: { [weak browserManager] tab in
                browserManager?.tabManager.scheduleRuntimeStatePersistence(for: tab)
            },
            schedulePrepareVisibleWebViews: { [weak browserManager] windowState in
                browserManager?.schedulePrepareVisibleWebViews(for: windowState)
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            },
            navigateBack: { webView in
                SumiWebViewNavigator.goBack(on: webView)
            },
            navigateForward: { webView in
                SumiWebViewNavigator.goForward(on: webView)
            }
        )
    }
}
