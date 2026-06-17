//
//  BrowserManager+Updates.swift
//  Sumi
//
//

import Foundation
import WebKit

enum ZoomPopoverSource {
    case toolbar
    case menu

    var autoCloseInterval: TimeInterval? {
        switch self {
        case .toolbar:
            return nil
        case .menu:
            return 2
        }
    }
}

struct ZoomPopoverRequest: Equatable, Identifiable {
    let id = UUID()
    let windowId: UUID
    let tabId: UUID
    let source: ZoomPopoverSource
}

@MainActor
extension BrowserManager {
    // MARK: - Zoom Management

    func zoomInCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        zoomInCurrentTab(in: windowState, source: .menu)
    }

    func zoomInCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = activePageTab(for: windowState),
              let webView = activePageWebView(for: windowState)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        applyUserZoomStep(.up, for: currentTab, webView: webView, domain: domain)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func zoomOutCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        zoomOutCurrentTab(in: windowState, source: .menu)
    }

    func zoomOutCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = activePageTab(for: windowState),
              let webView = activePageWebView(for: windowState)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        applyUserZoomStep(.down, for: currentTab, webView: webView, domain: domain)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func resetZoomCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        resetZoomCurrentTab(in: windowState, source: .menu)
    }

    func resetZoomCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = activePageTab(for: windowState),
              let webView = activePageWebView(for: windowState)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        let profileId = currentTab.resolveProfile()?.id ?? currentTab.profileId
        zoomManager.saveZoomLevel(1.0, for: domain, profileId: profileId)
        applyBoostAwareZoom(for: currentTab, webView: webView)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func loadZoomForTab(_ tabId: UUID) {
        guard let tab = tabManager.tab(for: tabId) else { return }

        let windowState = windowState(containing: tab) ?? windowRegistry?.activeWindow
        guard let windowState,
              let webView = getWebView(for: tabId, in: windowState.id)
        else { return }

        applyBoostAwareZoom(for: tab, webView: webView)
        didUpdateZoom(for: tab, in: windowState, source: nil)
    }

    func cleanupZoomForTab(_ tabId: UUID) {
        zoomManager.removeTabZoomLevel(for: tabId)
        zoomStateRevision += 1
    }

    // MARK: - Default Browser

    func setAsDefaultBrowser() {
        Task {
            _ = await SumiDefaultBrowserService.shared.requestBecomeDefault()
        }
    }

    func requestZoomPopover(for tab: Tab, in windowState: BrowserWindowState, source: ZoomPopoverSource) {
        zoomPopoverRequest = ZoomPopoverRequest(
            windowId: windowState.id,
            tabId: tab.id,
            source: source
        )
    }

    private func didUpdateZoom(for tab: Tab, in windowState: BrowserWindowState, source: ZoomPopoverSource?) {
        zoomStateRevision += 1
        if let source {
            requestZoomPopover(for: tab, in: windowState, source: source)
        }
    }

    func applyBoostAwareZoom(for tab: Tab, webView: WKWebView) {
        let domain = tab.url.host ?? tab.url.absoluteString
        let profileId = tab.resolveProfile()?.id ?? tab.profileId
        let savedZoom = zoomManager.getZoomLevel(for: domain, profileId: profileId)
        let boostMultiplier = boostsModule.sizeOverride(for: tab.url, profileId: profileId)
        let effectiveZoom = zoomManager.effectiveZoom(
            baseZoom: savedZoom,
            multiplier: boostMultiplier
        )
        zoomManager.applyTransientZoom(
            effectiveZoom,
            to: webView,
            domain: domain,
            tabId: tab.id
        )
    }

    private func applyUserZoomStep(
        _ direction: ZoomStepDirection,
        for tab: Tab,
        webView: WKWebView,
        domain: String
    ) {
        let profileId = tab.resolveProfile()?.id ?? tab.profileId
        let savedZoom = zoomManager.getZoomLevel(for: domain, profileId: profileId)
        let nextBaseZoom = zoomManager.nextZoomLevel(
            from: savedZoom,
            direction: direction
        )
        zoomManager.saveZoomLevel(nextBaseZoom, for: domain, profileId: profileId)
        applyBoostAwareZoom(for: tab, webView: webView)
    }
}
