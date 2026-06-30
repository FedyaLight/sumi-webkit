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
        zoomCommandOwner.zoomInCurrentTab()
    }

    func zoomInCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        zoomCommandOwner.zoomInCurrentTab(in: windowState, source: source)
    }

    func zoomOutCurrentTab() {
        zoomCommandOwner.zoomOutCurrentTab()
    }

    func zoomOutCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        zoomCommandOwner.zoomOutCurrentTab(in: windowState, source: source)
    }

    func resetZoomCurrentTab() {
        zoomCommandOwner.resetZoomCurrentTab()
    }

    func resetZoomCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        zoomCommandOwner.resetZoomCurrentTab(in: windowState, source: source)
    }

    func loadZoomForTab(_ tabId: UUID) {
        zoomCommandOwner.loadZoomForTab(tabId)
    }

    func cleanupZoomForTab(_ tabId: UUID) {
        zoomCommandOwner.cleanupZoomForTab(tabId)
    }

    // MARK: - Default Browser

    func setAsDefaultBrowser() {
        Task {
            _ = await SumiDefaultBrowserService.shared.requestBecomeDefault()
        }
    }

    func requestZoomPopover(for tab: Tab, in windowState: BrowserWindowState, source: ZoomPopoverSource) {
        zoomCommandOwner.requestZoomPopover(for: tab, in: windowState, source: source)
    }

    func applyBoostAwareZoom(for tab: Tab, webView: WKWebView) {
        zoomCommandOwner.applyBoostAwareZoom(for: tab, webView: webView)
    }
}
