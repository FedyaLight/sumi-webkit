//
//  ExtensionBridge.swift
//  Sumi
//
//  WebKit bridge adapters that expose Sumi windows and tabs to WebExtensions.
//

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionBrowserBridgeContext: AnyObject {
    func extensionWindowState(for windowId: UUID) -> BrowserWindowState?
    var activeExtensionWindowState: BrowserWindowState? { get }
    func extensionTab(for tabId: UUID) -> Tab?
    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab?
    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab]
    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState?
    func setActiveExtensionWindow(_ windowState: BrowserWindowState)
    func isTransientExtensionTab(_ tab: Tab) -> Bool
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool
    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool
    func isPinnedExtensionTab(_ tab: Tab) -> Bool
    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState?)
    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession?
    func focusAuxiliaryWindowSession(_ sessionId: UUID)
    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession)
    func closeAuxiliaryWindowWebView(_ webView: WKWebView)
    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool
}

@available(macOS 15.5, *)
@MainActor
extension BrowserManager: ExtensionBrowserBridgeContext {
    func extensionWindowState(for windowId: UUID) -> BrowserWindowState? {
        windowRegistry?.windows[windowId]
    }

    var activeExtensionWindowState: BrowserWindowState? {
        windowRegistry?.activeWindow
    }

    func extensionTab(for tabId: UUID) -> Tab? {
        if let tab = tabManager.tab(for: tabId) {
            return tab
        }

        guard let windowStates = windowRegistry?.windows.values else {
            return nil
        }
        for windowState in windowStates {
            if let tab = windowState.ephemeralTabs.first(where: { $0.id == tabId }) {
                return tab
            }
        }
        return nil
    }

    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab? {
        currentTab(for: windowState)
    }

    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab] {
        shellSelectionService.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        if let primaryWindowId = tab.primaryWindowId,
           let primaryWindow = windowRegistry?.windows[primaryWindowId]
        {
            return primaryWindow
        }

        if let containing = windowState(containing: tab) {
            return containing
        }

        if let activeWindow = activeExtensionWindowState,
           tabsForExtensionWindow(activeWindow).contains(where: { $0.id == tab.id })
        {
            return activeWindow
        }

        return windowRegistry?.windows.values.first { windowState in
            tabsForExtensionWindow(windowState).contains(where: { $0.id == tab.id })
        }
    }

    func setActiveExtensionWindow(_ windowState: BrowserWindowState) {
        windowRegistry?.setActive(windowState)
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        tabManager.isTransientExtensionTab(tab)
    }

    @discardableResult
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool {
        guard tabManager.isTransientExtensionTab(tab) else {
            return false
        }

        let targetSpace = tab.spaceId.flatMap { spaceId in
            tabManager.spaces.first(where: { $0.id == spaceId })
        } ?? tabManager.currentSpace

        return tabManager.promoteTransientExtensionTab(
            tab,
            in: targetSpace,
            activate: false
        )
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        tabManager.isAuxiliaryMiniWindowTab(tab)
    }

    func isPinnedExtensionTab(_ tab: Tab) -> Bool {
        tab.isPinned || tabManager.pinnedTabs.contains(where: { $0.id == tab.id })
    }

    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState?) {
        if let windowState {
            selectTab(tab, in: windowState)
        } else {
            selectTab(tab)
        }
    }

    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager.session(for: tab)
    }

    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager.session(for: sessionId)
    }

    func focusAuxiliaryWindowSession(_ sessionId: UUID) {
        auxiliaryWindowManager.focus(sessionID: sessionId)
    }

    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession) {
        auxiliaryWindowManager.teardown(for: session.webView, reason: .extensionRequestedClose)
    }

    func closeAuxiliaryWindowWebView(_ webView: WKWebView) {
        auxiliaryWindowManager.teardown(for: webView, reason: .extensionRequestedClose)
    }

    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool {
        auxiliaryWindowManager.contains(webView: webView)
    }
}

@available(macOS 15.5, *)
@MainActor
private enum ExtensionBridgeCallbackSupport {
    static func complete(
        _ completionHandler: @escaping (Error?) -> Void,
        api: SafariExtensionWebExtensionCallbackAPI,
        error: (any Error)?
    ) {
        if let error {
            let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
            SafariExtensionWebExtensionCallbackDiagnostics.recordFailure(
                api: api,
                extensionId: nil,
                error: mapped
            )
            completionHandler(mapped)
            return
        }

        SafariExtensionWebExtensionCallbackDiagnostics.recordSuccess(
            api: api,
            extensionId: nil,
            value: true
        )
        completionHandler(nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    let windowId: UUID

    private weak var browserContext: (any ExtensionBrowserBridgeContext)?
    private weak var extensionManager: ExtensionManager?

    init(
        windowId: UUID,
        browserContext: any ExtensionBrowserBridgeContext,
        extensionManager: ExtensionManager
    ) {
        self.windowId = windowId
        self.browserContext = browserContext
        self.extensionManager = extensionManager
        super.init()
    }

    private var windowState: BrowserWindowState? {
        browserContext?.extensionWindowState(for: windowId)
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
            let browserContext,
            let extensionManager,
            let windowState,
            let contextProfileId = extensionManager.profileId(for: extensionContext),
            extensionManager.windowMatchesProfile(windowState, profileId: contextProfileId),
            let tab = browserContext.currentExtensionTab(in: windowState),
            extensionManager.resolvedProfileId(for: tab) == contextProfileId,
            extensionManager.isTabEligibleForCurrentExtensionRuntime(tab)
        else {
            SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
                seesCurrentTab: false,
                extensionId: extensionManager?.extensionID(for: extensionContext),
                reason: "activeTabAdapterUnavailable"
            )
            return nil
        }

        let adapter = extensionManager.stableAdapter(for: tab)
        SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
            seesCurrentTab: adapter != nil,
            extensionId: extensionManager.extensionID(for: extensionContext),
            reason: "activeTabAdapterResolved"
        )
        return adapter
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browserContext,
              let extensionManager,
              let windowState,
              let contextProfileId = extensionManager.profileId(for: extensionContext),
              extensionManager.windowMatchesProfile(windowState, profileId: contextProfileId)
        else { return [] }

        return browserContext.tabsForExtensionWindow(windowState).filter {
            extensionManager.resolvedProfileId(for: $0) == contextProfileId
                && extensionManager.isTabEligibleForCurrentExtensionRuntime($0)
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
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        windowState.window?.makeKeyAndOrderFront(nil)
        browserContext?.setActiveExtensionWindow(windowState)
        NSApp.activate(ignoringOtherApps: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
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
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
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

        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func setFrame(
        _ frame: CGRect,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = windowState?.window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        window.setFrame(frame, display: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = windowState?.window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionWindowAdapter",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Window is no longer available"]
                )
            )
            return
        }

        window.performClose(nil)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionMiniWindowAdapter: NSObject, WKWebExtensionWindow {
    let sessionId: UUID
    let tabId: UUID

    private weak var browserContext: (any ExtensionBrowserBridgeContext)?
    private weak var extensionManager: ExtensionManager?
    private weak var window: NSWindow?
    private let isPrivateWindow: Bool
    private let shouldActivateApp: Bool

    init(
        sessionId: UUID,
        tabId: UUID,
        window: NSWindow,
        browserContext: any ExtensionBrowserBridgeContext,
        extensionManager: ExtensionManager,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) {
        self.sessionId = sessionId
        self.tabId = tabId
        self.window = window
        self.browserContext = browserContext
        self.extensionManager = extensionManager
        self.isPrivateWindow = isPrivate
        self.shouldActivateApp = shouldActivateApp
        super.init()
    }

    private var tab: Tab? {
        browserContext?.extensionTab(for: tabId)
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionMiniWindowAdapter else { return false }
        return other.sessionId == sessionId
    }

    override var hash: Int {
        sessionId.hashValue
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let extensionManager, let tab else { return [] }
        guard extensionManager.isTabEligibleForCurrentExtensionRuntime(tab) else { return [] }
        guard let adapter = extensionManager.stableAdapter(for: tab) else { return [] }
        return [adapter]
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tabs(for: extensionContext).first
    }

    func windowType(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .popup
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        isPrivateWindow
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .zero
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionMiniWindowAdapter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Mini-window is no longer available"]
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

        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func setFrame(
        _ frame: CGRect,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionMiniWindowAdapter",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Mini-window is no longer available"]
                )
            )
            return
        }

        window.setFrame(frame, display: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func focus(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        if shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        browserContext?.focusAuxiliaryWindowSession(sessionId)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browserContext,
              let session = browserContext.auxiliaryWindowSession(for: sessionId)
        else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: NSError(
                    domain: "ExtensionMiniWindowAdapter",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Mini-window is no longer available"]
                )
            )
            return
        }

        browserContext.closeAuxiliaryWindowSession(session)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let tabId: UUID

    private weak var browserContext: (any ExtensionBrowserBridgeContext)?
    private weak var extensionManager: ExtensionManager?

    init(
        tabId: UUID,
        browserContext: any ExtensionBrowserBridgeContext,
        extensionManager: ExtensionManager
    ) {
        self.tabId = tabId
        self.browserContext = browserContext
        self.extensionManager = extensionManager
        super.init()
    }

    var tab: Tab? {
        browserContext?.extensionTab(for: tabId)
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
        guard let tab else { return nil }
        return browserContext?.preferredExtensionWindowState(containing: tab)
    }

    @discardableResult
    private func promoteTransientExtensionTabIfNeeded(_ tab: Tab) -> Bool {
        browserContext?.promoteTransientExtensionTab(tab) ?? false
    }

    func url(for extensionContext: WKWebExtensionContext) -> URL? {
        return eligibleTab()?.url
    }

    func title(for extensionContext: WKWebExtensionContext) -> String? {
        return eligibleTab()?.name
    }

    func isSelected(for extensionContext: WKWebExtensionContext) -> Bool {
        guard
            let browserContext,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return false
        }

        return browserContext.currentExtensionTab(in: windowState)?.id == tab.id
    }

    func indexInWindow(for extensionContext: WKWebExtensionContext) -> Int {
        guard
            let browserContext,
            let tab = eligibleTab(),
            let windowState = resolvedWindowState()
        else {
            return 0
        }

        return browserContext.tabsForExtensionWindow(windowState)
            .firstIndex(where: { $0.id == tab.id }) ?? 0
    }

    func isLoadingComplete(for extensionContext: WKWebExtensionContext) -> Bool {
        !(eligibleTab()?.isLoading ?? false)
    }

    func isPinned(for extensionContext: WKWebExtensionContext) -> Bool {
        guard let tab = eligibleTab() else { return false }
        return browserContext?.isPinnedExtensionTab(tab) == true
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
        guard let tab = eligibleTab(),
              let extensionManager
        else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: extensionManager?.extensionID(for: extensionContext),
                reason: "tabAdapterWebViewUnavailable"
            )
            return nil
        }
        let webView = extensionManager.extensionWebView(
            for: tab,
            extensionContext: extensionContext
        )
        SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
            resolved: webView != nil,
            extensionId: extensionManager.extensionID(for: extensionContext),
            reason: "tabAdapterWebView"
        )
        return webView
    }

    func activate(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let browserContext, let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }

        promoteTransientExtensionTabIfNeeded(tab)
        browserContext.selectExtensionTab(tab, in: resolvedWindowState())
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }

        if let browserContext,
           browserContext.isAuxiliaryMiniWindowTab(tab),
           let webView = tab.existingWebView,
           browserContext.containsAuxiliaryWebView(webView)
        {
            browserContext.closeAuxiliaryWindowWebView(webView)
            ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
            return
        }

        tab.closeTab()
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func reload(
        fromOrigin: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        guard let webView = webView(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: NSError(
                    domain: "ExtensionTabAdapter",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No live web view is available for this tab"]
                )
            )
            return
        }

        let reloadTargetURL = webView.url ?? tab.url
        if tab.protectionAttachmentRequiresNormalWebViewRebuild(for: reloadTargetURL)
            || tab.autoplayPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            tab.refresh()
        } else if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }

        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func loadURL(
        _ url: URL,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        if ExtensionUtils.isExtensionOwnedURL(url) == false {
            promoteTransientExtensionTabIfNeeded(tab)
        }
        tab.loadURL(url)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func setMuted(
        _ muted: Bool,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let tab = eligibleTab() else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableUntilReloadError
            )
            return
        }
        tab.setMuted(muted)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .tabAdapterCompletion,
                error: tabUnavailableError
            )
            return
        }
        webView.pageZoom = zoomFactor
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .tabAdapterCompletion, error: nil)
    }

    func zoomFactor(for extensionContext: WKWebExtensionContext) -> Double {
        Double(webView(for: extensionContext)?.pageZoom ?? 1)
    }

    func shouldGrantPermissionsOnUserGesture(for extensionContext: WKWebExtensionContext) -> Bool {
        true
    }

    func shouldBypassPermissions(for extensionContext: WKWebExtensionContext) -> Bool {
        false
    }

    func window(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let tab = eligibleTab() else { return nil }
        if browserContext?.isAuxiliaryMiniWindowTab(tab) == true {
            return extensionManager?.miniWindowAdapter(for: tab)
        }
        if let miniWindowAdapter = extensionManager?.miniWindowAdapter(for: tab) {
            return miniWindowAdapter
        }
        guard let windowId = resolvedWindowState()?.id else { return nil }
        return extensionManager?.windowAdapter(for: windowId)
    }
}
