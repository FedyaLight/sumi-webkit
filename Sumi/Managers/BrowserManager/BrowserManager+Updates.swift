//
//  BrowserManager+Updates.swift
//  Sumi
//
//  Created by OpenAI Codex on 06/04/2026.
//

import CoreServices
import Sparkle

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
        let version: String
        let shortVersion: String
        let releaseNotesURL: URL?
        var isDownloaded: Bool

        init(version: String, shortVersion: String, releaseNotesURL: URL?, isDownloaded: Bool) {
            self.version = version
            self.shortVersion = shortVersion
            self.releaseNotesURL = releaseNotesURL
            self.isDownloaded = isDownloaded
        }

        init(item: SUAppcastItem, isDownloaded: Bool) {
            self.init(
                version: item.versionString,
                shortVersion: item.displayVersionString,
                releaseNotesURL: item.releaseNotesURL,
                isDownloaded: isDownloaded
            )
        }
    }

    func handleUpdaterFoundValidUpdate(_ item: SUAppcastItem) {
        updateAvailability = UpdateAvailability(
            item: item,
            isDownloaded: updateAvailability?.isDownloaded ?? false
        )
    }

    func handleUpdaterFinishedDownloading(_ item: SUAppcastItem) {
        if var availability = updateAvailability {
            availability.isDownloaded = true
            updateAvailability = availability
        } else {
            updateAvailability = UpdateAvailability(item: item, isDownloaded: true)
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

    func installPendingUpdateIfAvailable() {
        appDelegate?.updaterController.checkForUpdates(nil)
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

    func applyZoomLevel(_ zoomLevel: Double, to tabId: UUID? = nil, in windowState: BrowserWindowState? = nil) {
        guard let windowState = windowState ?? windowRegistry?.activeWindow else { return }

        let targetTabId = tabId ?? currentTab(for: windowState)?.id
        guard let tabId = targetTabId,
              let webView = getWebView(for: tabId, in: windowState.id),
              let tab = tabManager.tab(for: tabId)
        else { return }

        let domain = tab.url.host ?? tab.url.absoluteString
        zoomManager.applyZoom(zoomLevel, to: webView, domain: domain, tabId: tabId)
        didUpdateZoom(for: tab, in: windowState, source: nil)
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

    func getCurrentZoomLevel() -> Double {
        zoomManager.currentZoomLevel
    }

    func getCurrentZoomPercentage() -> String {
        zoomManager.getZoomPercentageDisplay()
    }

    func showZoomPopup() {
        guard let windowState = windowRegistry?.activeWindow,
              let currentTab = currentTab(for: windowState)
        else { return }
        requestZoomPopover(for: currentTab, in: windowState, source: .menu)
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
