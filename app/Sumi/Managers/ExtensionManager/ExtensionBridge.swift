//
//  ExtensionBridge.swift
//  Sumi
//
//  WebKit bridge adapters that expose Sumi windows and tabs to Safari extensions.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let windowId: UUID

    private weak var browserManager: BrowserManager?
    private weak var extensionManager: ExtensionManager?

    init(
        windowId: UUID,
        browserManager: BrowserManager,
        extensionManager: ExtensionManager
    ) {
        self.windowId = windowId
        self.browserManager = browserManager
        self.extensionManager = extensionManager
        super.init()
    }

    private var windowState: BrowserWindowState? {
        browserManager?.windowRegistry?.windows[windowId]
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionWindowAdapter else { return false }
        return other.windowId == windowId
    }

    override var hash: Int {
        windowId.hashValue
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard
            let browserManager,
            let extensionManager,
            let windowState,
            let tab = browserManager.currentTab(for: windowState),
            extensionManager.isTabEligibleForCurrentExtensionRuntime(tab)
        else {
            return nil
        }

        return extensionManager.stableAdapter(for: tab)
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browserManager, let extensionManager, let windowState else { return [] }

        return browserManager.shellSelectionService.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: browserManager.tabManager.runtimeStore
        ).filter {
            extensionManager.isTabEligibleForCurrentExtensionRuntime($0)
        }.compactMap {
            extensionManager.stableAdapter(for: $0)
        }
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        windowState?.window?.frame ?? .zero
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        windowState?.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    func focus(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let windowState else {
            completionHandler(
                NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        windowState.window?.makeKeyAndOrderFront(nil)
        browserManager?.windowRegistry?.setActive(windowState)
        NSApp.activate(ignoringOtherApps: true)
        completionHandler(nil)
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        windowState?.isIncognito ?? false
    }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = windowState?.window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = self.windowState?.window else {
            completionHandler(
                NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        switch windowState {
        case .minimized:
            window.miniaturize(nil)
        case .maximized:
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.zoom(nil)
        case .fullscreen:
            if !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        case .normal:
            if window.isMiniaturized {
                window.deminiaturize(nil)
            } else if window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
        @unknown default:
            break
        }

        completionHandler(nil)
    }

    func setFrame(
        _ frame: CGRect,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = windowState?.window else {
            completionHandler(
                NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        window.setFrame(frame, display: true)
        completionHandler(nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = windowState?.window else {
            completionHandler(
                NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        window.performClose(nil)
        completionHandler(nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let tabId: UUID

    private weak var browserManager: BrowserManager?
    private weak var extensionManager: ExtensionManager?

    init(
        tabId: UUID,
        browserManager: BrowserManager,
        extensionManager: ExtensionManager
    ) {
        self.tabId = tabId
        self.browserManager = browserManager
        self.extensionManager = extensionManager
        super.init()
    }

    var tab: Tab? {
        browserManager?.tabManager.tab(for: tabId)
            ?? browserManager?.windowRegistry?.windows.values.lazy
                .flatMap(\.ephemeralTabs)
                .first(where: { $0.id == tabId })
    }

    private var tabUnavailableUntilReloadError: NSError {
        NSError(
            domain: "ExtensionTabAdapter",
            code: 3,
            userInfo: [
                NSLocalizedDescriptionKey: "Tab is not available to extensions until it is reloaded or navigates to a new document"
            ]
        )
    }

    private var tabUnavailableError: NSError {
        if tab != nil {
            return tabUnavailableUntilReloadError
        }
        return NSError(
            domain: "ExtensionTabAdapter",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Tab is no longer available"]
        )
    }

    private func eligibleTab() -> Tab? {
        guard let tab, extensionManager?.isTabEligibleForCurrentExtensionRuntime(tab) == true else {
            return nil
        }
        return tab
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionTabAdapter else { return false }
        return other.tabId == tabId
    }

    override var hash: Int {
        tabId.hashValue
    }

    private func resolvedWindowState() -> BrowserWindowState? {
        guard let browserManager, let tab else { return nil }

        if let primaryWindowId = tab.primaryWindowId,
           let primaryWindow = browserManager.windowRegistry?.windows[primaryWindowId]
        {
            return primaryWindow
        }

        if let containing = browserManager.windowState(containing: tab) {
            return containing
        }

        if let activeWindow = browserManager.windowRegistry?.activeWindow,
           browserManager.shellSelectionService.tabsForWebExtensionWindow(
                in: activeWindow,
                tabStore: browserManager.tabManager.runtimeStore
           ).contains(where: { $0.id == tab.id })
        {
            return activeWindow
        }

        return browserManager.windowRegistry?.windows.values.first { windowState in
            browserManager.shellSelectionService.tabsForWebExtensionWindow(
                in: windowState,
                tabStore: browserManager.tabManager.runtimeStore
            ).contains(where: { $0.id == tab.id })
        }
    }

    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        eligibleTab()?.url
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        eligibleTab()?.name
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        guard
            let browserManager,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return false
        }

        return browserManager.currentTab(for: windowState)?.id == tab.id
    }

    func indexInWindow(for extensionContext: WKWebExtensionContext) -> Int {
        guard
            let browserManager,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return 0
        }

        return browserManager.shellSelectionService.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: browserManager.tabManager.runtimeStore
        ).firstIndex(where: { $0.id == tab.id }) ?? 0
    }

    func isLoadingComplete(for extensionContext: WKWebExtensionContext) -> Bool {
        !(eligibleTab()?.isLoading ?? false)
    }

    func isPinned(for extensionContext: WKWebExtensionContext) -> Bool {
        guard let tab = eligibleTab() else { return false }
        return tab.isPinned || browserManager?.tabManager.pinnedTabs.contains(where: { $0.id == tabId }) == true
    }

    func isMuted(for extensionContext: WKWebExtensionContext) -> Bool {
        eligibleTab()?.audioState.isMuted ?? false
    }

    func isPlayingAudio(for extensionContext: WKWebExtensionContext) -> Bool {
        eligibleTab()?.audioState.isPlayingAudio ?? false
    }

    func isReaderModeActive(for extensionContext: WKWebExtensionContext) -> Bool {
        false
    }

    func webView(for extensionContext: WKWebExtensionContext) -> WKWebView? {
        guard
            let browserManager,
            let tab = eligibleTab()
        else {
            return nil
        }
        if let windowState = resolvedWindowState() {
            return browserManager.getWebView(for: tab.id, in: windowState.id)
                ?? tab.assignedWebView
                ?? tab.existingWebView
        }
        return tab.assignedWebView ?? tab.existingWebView
    }

    func activate(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browserManager, let tab = eligibleTab() else {
            completionHandler(tabUnavailableError)
            return
        }

        if let windowState = resolvedWindowState() {
            browserManager.selectTab(tab, in: windowState)
        } else {
            browserManager.selectTab(tab)
        }
        completionHandler(nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            completionHandler(tabUnavailableUntilReloadError)
            return
        }
        tab.closeTab()
        completionHandler(nil)
    }

    func reload(
        fromOrigin: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard eligibleTab() != nil else {
            completionHandler(tabUnavailableUntilReloadError)
            return
        }
        guard let webView = webView(for: extensionContext) else {
            completionHandler(
                NSError(
                    domain: "ExtensionTabAdapter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No live web view is available for this tab"]
                )
            )
            return
        }

        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }

        completionHandler(nil)
    }

    func loadURL(
        _ url: URL,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            completionHandler(tabUnavailableUntilReloadError)
            return
        }
        tab.loadURL(url)
        completionHandler(nil)
    }

    func setMuted(
        _ muted: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            completionHandler(tabUnavailableUntilReloadError)
            return
        }
        tab.setMuted(muted)
        completionHandler(nil)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: extensionContext) else {
            completionHandler(tabUnavailableError)
            return
        }
        webView.pageZoom = zoomFactor
        completionHandler(nil)
    }

    func zoomFactor(for extensionContext: WKWebExtensionContext) -> Double {
        Double(webView(for: extensionContext)?.pageZoom ?? 1)
    }

    func shouldGrantPermissionsOnUserGesture(for extensionContext: WKWebExtensionContext) -> Bool {
        true
    }

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard eligibleTab() != nil else { return nil }
        guard let windowId = resolvedWindowState()?.id else { return nil }
        return extensionManager?.windowAdapter(for: windowId)
    }
}
