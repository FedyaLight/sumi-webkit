import Foundation
import WebKit

@MainActor
final class BrowserZoomCommandOwner {
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let activePageTab: @MainActor (BrowserWindowState) -> Tab?
    private let activePresentationWebView: @MainActor (BrowserWindowState) -> WKWebView?
    private let tab: @MainActor (UUID) -> Tab?
    private let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
    private let webView: @MainActor (UUID, UUID) -> WKWebView?
    private let zoomManager: @MainActor () -> ZoomManager?
    private let sizeOverride: @MainActor (URL, UUID?) -> Double
    private let incrementZoomStateRevision: @MainActor () -> Void
    private let notifications: @MainActor () -> (any BrowserNotificationPresenting)?

    init(
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        activePageTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        activePresentationWebView: @escaping @MainActor (BrowserWindowState) -> WKWebView?,
        tab: @escaping @MainActor (UUID) -> Tab?,
        windowStateContainingTab: @escaping @MainActor (Tab) -> BrowserWindowState?,
        webView: @escaping @MainActor (UUID, UUID) -> WKWebView?,
        zoomManager: @escaping @MainActor () -> ZoomManager?,
        sizeOverride: @escaping @MainActor (URL, UUID?) -> Double,
        incrementZoomStateRevision: @escaping @MainActor () -> Void,
        notifications: @escaping @MainActor () -> (any BrowserNotificationPresenting)?
    ) {
        self.activeWindow = activeWindow
        self.activePageTab = activePageTab
        self.activePresentationWebView = activePresentationWebView
        self.tab = tab
        self.windowStateContainingTab = windowStateContainingTab
        self.webView = webView
        self.zoomManager = zoomManager
        self.sizeOverride = sizeOverride
        self.incrementZoomStateRevision = incrementZoomStateRevision
        self.notifications = notifications
    }

    func zoomInCurrentTab() {
        guard let windowState = activeWindow() else { return }
        zoomInCurrentTab(in: windowState)
    }

    func zoomInCurrentTab(in windowState: BrowserWindowState) {
        applyUserZoomStep(.up, in: windowState)
    }

    func zoomOutCurrentTab() {
        guard let windowState = activeWindow() else { return }
        zoomOutCurrentTab(in: windowState)
    }

    func zoomOutCurrentTab(in windowState: BrowserWindowState) {
        applyUserZoomStep(.down, in: windowState)
    }

    func resetZoomCurrentTab() {
        guard let windowState = activeWindow() else { return }
        resetZoomCurrentTab(in: windowState)
    }

    func resetZoomCurrentTab(in windowState: BrowserWindowState) {
        guard let context = activeZoomContext(in: windowState) else { return }

        guard let zoomManager = zoomManager() else { return }
        zoomManager.saveZoomLevel(
            1.0,
            for: context.domain,
            profileId: context.profileId
        )
        applyBoostAwareZoom(
            for: context.tab,
            webView: context.webView,
            zoomManager: zoomManager
        )
        didUpdateZoom(
            for: context.tab,
            in: windowState,
            zoomManager: zoomManager,
            showNotification: true
        )
    }

    func loadZoomForTab(_ tabId: UUID) {
        guard let tab = tab(tabId) else { return }

        let windowState = windowStateContainingTab(tab) ?? activeWindow()
        guard let windowState,
              let webView = webView(tabId, windowState.id)
        else { return }

        guard let zoomManager = zoomManager() else { return }
        applyBoostAwareZoom(for: tab, webView: webView, zoomManager: zoomManager)
        didUpdateZoom(
            for: tab,
            in: windowState,
            zoomManager: zoomManager,
            showNotification: false
        )
    }

    func loadZoomForTab(_ tabId: UUID, on webView: WKWebView) {
        guard let tab = tab(tabId) else { return }
        guard let zoomManager = zoomManager() else { return }
        let previousZoom = webView.pageZoom
        applyBoostAwareZoom(for: tab, webView: webView, zoomManager: zoomManager)
        if webView.pageZoom != previousZoom {
            incrementZoomStateRevision()
        }
    }

    func cleanupZoomForTab(_ tabId: UUID) {
        guard let zoomManager = zoomManager() else { return }
        zoomManager.removeTabZoomLevel(for: tabId)
        incrementZoomStateRevision()
    }

    func applyBoostAwareZoom(for tab: Tab, webView: WKWebView) {
        guard let zoomManager = zoomManager() else { return }
        applyBoostAwareZoom(for: tab, webView: webView, zoomManager: zoomManager)
    }

    private func applyBoostAwareZoom(
        for tab: Tab,
        webView: WKWebView,
        zoomManager: ZoomManager
    ) {
        let context = zoomContext(for: tab)
        let savedZoom = zoomManager.getZoomLevel(
            for: context.domain,
            profileId: context.profileId
        )
        let boostMultiplier = sizeOverride(tab.url, context.profileId)
        let effectiveZoom = zoomManager.effectiveZoom(
            baseZoom: savedZoom,
            multiplier: boostMultiplier
        )
        zoomManager.applyTransientZoom(
            effectiveZoom,
            to: webView,
            domain: context.domain,
            tabId: tab.id
        )
    }

    private func applyUserZoomStep(
        _ direction: ZoomStepDirection,
        in windowState: BrowserWindowState
    ) {
        guard let context = activeZoomContext(in: windowState),
              let zoomManager = zoomManager() else { return }

        let savedZoom = zoomManager.getZoomLevel(
            for: context.domain,
            profileId: context.profileId
        )
        let nextBaseZoom = zoomManager.nextZoomLevel(
            from: savedZoom,
            direction: direction
        )
        zoomManager.saveZoomLevel(
            nextBaseZoom,
            for: context.domain,
            profileId: context.profileId
        )
        applyBoostAwareZoom(
            for: context.tab,
            webView: context.webView,
            zoomManager: zoomManager
        )
        didUpdateZoom(
            for: context.tab,
            in: windowState,
            zoomManager: zoomManager,
            showNotification: true
        )
    }

    private func activeZoomContext(in windowState: BrowserWindowState) -> ActiveZoomContext? {
        guard let tab = activePageTab(windowState),
              let webView = activePresentationWebView(windowState)
        else { return nil }

        let context = zoomContext(for: tab)
        return ActiveZoomContext(
            tab: tab,
            webView: webView,
            domain: context.domain,
            profileId: context.profileId
        )
    }

    private func didUpdateZoom(
        for tab: Tab,
        in windowState: BrowserWindowState,
        zoomManager: ZoomManager,
        showNotification: Bool
    ) {
        incrementZoomStateRevision()
        guard showNotification else { return }

        let tabId = tab.id
        notifications()?.presentNotification(
            .zoom(
                percentage: zoomManager.getZoomPercentageDisplay(for: tabId),
                isAtMinimum: zoomManager.isAtMinimumZoom(for: tabId),
                isAtMaximum: zoomManager.isAtMaximumZoom(for: tabId),
                zoomOut: { [weak self] in
                    self?.zoomOutCurrentTab(in: windowState)
                },
                resetZoom: { [weak self] in
                    self?.resetZoomCurrentTab(in: windowState)
                },
                zoomIn: { [weak self] in
                    self?.zoomInCurrentTab(in: windowState)
                }
            ),
            in: windowState
        )
    }

    private func zoomContext(for tab: Tab) -> ZoomContext {
        ZoomContext(
            domain: tab.url.host ?? tab.url.absoluteString,
            profileId: tab.resolveProfile()?.id ?? tab.profileId
        )
    }
}

private struct ActiveZoomContext {
    let tab: Tab
    let webView: WKWebView
    let domain: String
    let profileId: UUID?
}

private struct ZoomContext {
    let domain: String
    let profileId: UUID?
}
