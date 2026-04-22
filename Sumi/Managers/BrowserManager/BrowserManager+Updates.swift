//
//  BrowserManager+Updates.swift
//  Sumi
//
//  Created by OpenAI Codex on 06/04/2026.
//

import CoreServices
import Sparkle

enum SumiUpdateConfiguration {
    static var configuredFeedURL: URL? {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let url = URL(string: rawValue),
            rawValue.contains("example.com") == false
        else {
            return nil
        }
        return url
    }

    static var isConfigured: Bool {
        configuredFeedURL != nil
    }
}

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
    // MARK: - Update Handling

    struct UpdateAvailability: Equatable {
        var isDownloaded: Bool
    }

    func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem) {
        _ = item
        updateAvailability = UpdateAvailability(
            isDownloaded: updateAvailability?.isDownloaded ?? false
        )
    }

    func handleUpdaterFinishedDownloading(_ item: SUAppcastItem) {
        _ = item
        if var availability = updateAvailability {
            availability.isDownloaded = true
            updateAvailability = availability
        } else {
            updateAvailability = UpdateAvailability(isDownloaded: true)
        }
    }

    func handleUpdaterDidNotFindUpdate() {
        updateAvailability = nil
    }

    func handleUpdaterAbortedUpdate() {
        updateAvailability = nil
    }

    func handleUpdaterWillInstallOnQuit(_ item: SUAppcastItem) {
        handleUpdaterFinishedDownloading(item)
    }

    func checkForUpdates() {
        appDelegate?.updaterController.checkForUpdates(nil)
    }

    func installPendingUpdateIfAvailable() {
        checkForUpdates()
    }

    // MARK: - Zoom Management

    func zoomInCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        zoomInCurrentTab(in: windowState, source: .menu)
    }

    func zoomInCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = currentTab(for: windowState),
              let webView = getWebView(for: currentTab.id, in: windowState.id)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.zoomIn(for: webView, domain: domain, tabId: currentTab.id)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func zoomOutCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        zoomOutCurrentTab(in: windowState, source: .menu)
    }

    func zoomOutCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = currentTab(for: windowState),
              let webView = getWebView(for: currentTab.id, in: windowState.id)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.zoomOut(for: webView, domain: domain, tabId: currentTab.id)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func resetZoomCurrentTab() {
        guard let windowState = windowRegistry?.activeWindow else { return }
        resetZoomCurrentTab(in: windowState, source: .menu)
    }

    func resetZoomCurrentTab(in windowState: BrowserWindowState, source: ZoomPopoverSource? = nil) {
        guard let currentTab = currentTab(for: windowState),
              let webView = getWebView(for: currentTab.id, in: windowState.id)
        else { return }

        let domain = currentTab.url.host ?? currentTab.url.absoluteString
        zoomManager.resetZoom(for: webView, domain: domain, tabId: currentTab.id)
        didUpdateZoom(for: currentTab, in: windowState, source: source)
    }

    func loadZoomForTab(_ tabId: UUID) {
        guard let tab = tabManager.tab(for: tabId) else { return }

        let windowState = windowState(containing: tab) ?? windowRegistry?.activeWindow
        guard let windowState,
              let webView = getWebView(for: tabId, in: windowState.id)
        else { return }

        let domain = tab.url.host ?? tab.url.absoluteString
        zoomManager.loadSavedZoom(for: webView, domain: domain, tabId: tabId)
        didUpdateZoom(for: tab, in: windowState, source: nil)
    }

    func cleanupZoomForTab(_ tabId: UUID) {
        zoomManager.removeTabZoomLevel(for: tabId)
        zoomStateRevision += 1
    }

    // MARK: - Default Browser

    func setAsDefaultBrowser() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        LSSetDefaultHandlerForURLScheme("http" as CFString, bundleIdentifier as CFString)
        LSSetDefaultHandlerForURLScheme("https" as CFString, bundleIdentifier as CFString)
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
}
