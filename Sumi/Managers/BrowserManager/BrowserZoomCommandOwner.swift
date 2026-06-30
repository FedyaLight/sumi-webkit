import Foundation
import WebKit

@MainActor
final class BrowserZoomCommandOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let activePageTab: @MainActor (BrowserWindowState) -> Tab?
        let activePageWebView: @MainActor (BrowserWindowState) -> WKWebView?
        let tab: @MainActor (UUID) -> Tab?
        let windowStateContainingTab: @MainActor (Tab) -> BrowserWindowState?
        let webView: @MainActor (UUID, UUID) -> WKWebView?
        let zoomManager: @MainActor () -> ZoomManager
        let sizeOverride: @MainActor (URL, UUID?) -> Double
        let incrementZoomStateRevision: @MainActor () -> Void
        let setZoomPopoverRequest: @MainActor (ZoomPopoverRequest) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func zoomInCurrentTab() {
        guard let windowState = dependencies.activeWindow() else { return }
        zoomInCurrentTab(in: windowState, source: .menu)
    }

    func zoomInCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        applyUserZoomStep(.up, in: windowState, source: source)
    }

    func zoomOutCurrentTab() {
        guard let windowState = dependencies.activeWindow() else { return }
        zoomOutCurrentTab(in: windowState, source: .menu)
    }

    func zoomOutCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        applyUserZoomStep(.down, in: windowState, source: source)
    }

    func resetZoomCurrentTab() {
        guard let windowState = dependencies.activeWindow() else { return }
        resetZoomCurrentTab(in: windowState, source: .menu)
    }

    func resetZoomCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let context = activeZoomContext(in: windowState) else { return }

        dependencies.zoomManager().saveZoomLevel(
            1.0,
            for: context.domain,
            profileId: context.profileId
        )
        applyBoostAwareZoom(for: context.tab, webView: context.webView)
        didUpdateZoom(for: context.tab, in: windowState, source: source)
    }

    func loadZoomForTab(_ tabId: UUID) {
        guard let tab = dependencies.tab(tabId) else { return }

        let windowState = dependencies.windowStateContainingTab(tab) ?? dependencies.activeWindow()
        guard let windowState,
              let webView = dependencies.webView(tabId, windowState.id)
        else { return }

        applyBoostAwareZoom(for: tab, webView: webView)
        didUpdateZoom(for: tab, in: windowState, source: nil)
    }

    func cleanupZoomForTab(_ tabId: UUID) {
        dependencies.zoomManager().removeTabZoomLevel(for: tabId)
        dependencies.incrementZoomStateRevision()
    }

    func requestZoomPopover(for tab: Tab, in windowState: BrowserWindowState, source: ZoomPopoverSource) {
        dependencies.setZoomPopoverRequest(
            ZoomPopoverRequest(
                windowId: windowState.id,
                tabId: tab.id,
                source: source
            )
        )
    }

    func applyBoostAwareZoom(for tab: Tab, webView: WKWebView) {
        let context = zoomContext(for: tab)
        let savedZoom = dependencies.zoomManager().getZoomLevel(
            for: context.domain,
            profileId: context.profileId
        )
        let boostMultiplier = dependencies.sizeOverride(tab.url, context.profileId)
        let effectiveZoom = dependencies.zoomManager().effectiveZoom(
            baseZoom: savedZoom,
            multiplier: boostMultiplier
        )
        dependencies.zoomManager().applyTransientZoom(
            effectiveZoom,
            to: webView,
            domain: context.domain,
            tabId: tab.id
        )
    }

    private func applyUserZoomStep(
        _ direction: ZoomStepDirection,
        in windowState: BrowserWindowState,
        source: ZoomPopoverSource?
    ) {
        guard let context = activeZoomContext(in: windowState) else { return }

        let savedZoom = dependencies.zoomManager().getZoomLevel(
            for: context.domain,
            profileId: context.profileId
        )
        let nextBaseZoom = dependencies.zoomManager().nextZoomLevel(
            from: savedZoom,
            direction: direction
        )
        dependencies.zoomManager().saveZoomLevel(
            nextBaseZoom,
            for: context.domain,
            profileId: context.profileId
        )
        applyBoostAwareZoom(for: context.tab, webView: context.webView)
        didUpdateZoom(for: context.tab, in: windowState, source: source)
    }

    private func activeZoomContext(in windowState: BrowserWindowState) -> ActiveZoomContext? {
        guard let tab = dependencies.activePageTab(windowState),
              let webView = dependencies.activePageWebView(windowState)
        else { return nil }

        let context = zoomContext(for: tab)
        return ActiveZoomContext(
            tab: tab,
            webView: webView,
            domain: context.domain,
            profileId: context.profileId
        )
    }

    private func didUpdateZoom(for tab: Tab, in windowState: BrowserWindowState, source: ZoomPopoverSource?) {
        dependencies.incrementZoomStateRevision()
        if let source {
            requestZoomPopover(for: tab, in: windowState, source: source)
        }
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

extension BrowserZoomCommandOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let fallbackZoomManager = browserManager.zoomManager
        return Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            activePageTab: { [weak browserManager] windowState in
                browserManager?.activePageTab(for: windowState)
            },
            activePageWebView: { [weak browserManager] windowState in
                browserManager?.activePageWebView(for: windowState)
            },
            tab: { [weak browserManager] tabId in
                browserManager?.tabManager.tab(for: tabId)
            },
            windowStateContainingTab: { [weak browserManager] tab in
                browserManager?.windowState(containing: tab)
            },
            webView: { [weak browserManager] tabId, windowId in
                browserManager?.getWebView(for: tabId, in: windowId)
            },
            zoomManager: { [weak browserManager] in
                browserManager?.zoomManager ?? fallbackZoomManager
            },
            sizeOverride: { [weak browserManager] url, profileId in
                browserManager?.boostsModule.sizeOverride(for: url, profileId: profileId) ?? 1.0
            },
            incrementZoomStateRevision: { [weak browserManager] in
                guard let browserManager else { return }
                browserManager.zoomStateRevision += 1
            },
            setZoomPopoverRequest: { [weak browserManager] request in
                browserManager?.zoomPopoverRequest = request
            }
        )
    }
}
