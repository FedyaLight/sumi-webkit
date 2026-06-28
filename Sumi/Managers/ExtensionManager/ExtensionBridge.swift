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
    var allExtensionWindowStates: [BrowserWindowState] { get }
    func extensionTab(for tabId: UUID) -> Tab?
    func extensionWindowState(containing tab: Tab) -> BrowserWindowState?
    func extensionWindowState(forAppKitWindow window: NSWindow) -> BrowserWindowState?
    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab?
    func currentExtensionTabForActiveWindow() -> Tab?
    func currentExtensionTabForPopup() -> Tab?
    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab]
    func extensionSpace(for spaceId: UUID?) -> Space?
    var currentExtensionSpace: Space? { get }
    func extensionTargetSpace(for windowState: BrowserWindowState?) -> Space?
    func extensionTargetSpace(for tab: Tab) -> Space?
    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState?
    func setActiveExtensionWindow(_ windowState: BrowserWindowState)
    func createExtensionWindow()
    func awaitNextExtensionWindow(excluding existingWindowIDs: Set<UUID>) async -> BrowserWindowState?
    func createExtensionTab(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab
    func createTransientExtensionTab(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab
    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    )
    func isTransientExtensionTab(_ tab: Tab) -> Bool
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool
    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool
    func isPinnedExtensionTab(_ tab: Tab) -> Bool
    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState?)
    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    )
    func assignExtensionWebView(
        _ webView: WKWebView,
        to tab: Tab,
        in windowState: BrowserWindowState
    )
    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for window: NSWindow) -> AuxiliaryWindowSession?
    func focusedExtensionMiniWindowAdapter(forOwnerExtensionID ownerExtensionID: String) -> ExtensionMiniWindowAdapter?
    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID)
    func focusAuxiliaryWindowSession(_ sessionId: UUID)
    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession)
    func closeAuxiliaryWindowWebView(_ webView: WKWebView)
    func closeAuxiliaryWindowSessions(
        forExtensionId extensionId: String,
        reason: AuxiliaryWindowCloseReason
    )
    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool
    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        shouldActivateApp: Bool,
        extensionOwnedSourceURL: URL?,
        ownerExtensionID: String?
    ) -> WKWebView?
    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter?
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

    var allExtensionWindowStates: [BrowserWindowState] {
        windowRegistry?.allWindows ?? []
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

    func extensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        windowState(containing: tab)
    }

    func extensionWindowState(forAppKitWindow window: NSWindow) -> BrowserWindowState? {
        windowRegistry?.windows.values.first { $0.window === window }
    }

    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab? {
        currentTab(for: windowState)
    }

    func currentExtensionTabForActiveWindow() -> Tab? {
        currentTabForActiveWindow()
    }

    func currentExtensionTabForPopup() -> Tab? {
        currentTabForActiveWindow() ?? tabManager.currentTab
    }

    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab] {
        shellSelectionService.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: tabManager.runtimeStore
        )
    }

    func extensionSpace(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaces.first { $0.id == spaceId }
    }

    var currentExtensionSpace: Space? {
        tabManager.currentSpace
    }

    func extensionTargetSpace(for windowState: BrowserWindowState?) -> Space? {
        windowState?.currentSpaceId.flatMap(extensionSpace(for:)) ?? currentExtensionSpace
    }

    func extensionTargetSpace(for tab: Tab) -> Space? {
        tab.spaceId.flatMap(extensionSpace(for:)) ?? currentExtensionSpace
    }

    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        if let primaryWindowId = tab.primaryWindowId,
           let primaryWindow = windowRegistry?.windows[primaryWindowId] {
            return primaryWindow
        }

        if let containing = windowState(containing: tab) {
            return containing
        }

        if let activeWindow = activeExtensionWindowState,
           tabsForExtensionWindow(activeWindow).contains(where: { $0.id == tab.id }) {
            return activeWindow
        }

        return windowRegistry?.windows.values.first { windowState in
            tabsForExtensionWindow(windowState).contains(where: { $0.id == tab.id })
        }
    }

    func setActiveExtensionWindow(_ windowState: BrowserWindowState) {
        windowRegistry?.setActive(windowState)
    }

    func createExtensionWindow() {
        createNewWindow()
    }

    func awaitNextExtensionWindow(excluding existingWindowIDs: Set<UUID>) async -> BrowserWindowState? {
        await windowRegistry?.awaitNextRegisteredWindow(excluding: existingWindowIDs)
    }

    func createExtensionTab(
        url: URL?,
        in space: Space?,
        activate: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        if let url {
            return tabManager.createNewTab(
                url: url.absoluteString,
                in: space,
                activate: activate,
                webExtensionContextOverride: webExtensionContextOverride
            )
        }

        return tabManager.createNewTab(
            in: space,
            activate: activate,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func createTransientExtensionTab(
        url: URL,
        in space: Space?,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        tabManager.createTransientExtensionTab(
            url: url.absoluteString,
            in: space,
            webExtensionContextOverride: webExtensionContextOverride
        )
    }

    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) {
        let resolvedTargetSpaceId = targetSpace?.id ?? tab.spaceId
        tabManager.pinTab(
            tab,
            context: .init(windowState: targetWindow, spaceId: resolvedTargetSpaceId)
        )
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

    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
    }

    func assignExtensionWebView(
        _ webView: WKWebView,
        to tab: Tab,
        in windowState: BrowserWindowState
    ) {
        webViewCoordinator?.setWebView(webView, for: tab.id, in: windowState.id)
    }

    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager.session(for: tab)
    }

    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager.session(for: sessionId)
    }

    func auxiliaryWindowSession(for window: NSWindow) -> AuxiliaryWindowSession? {
        auxiliaryWindowManager.session(for: window)
    }

    func focusedExtensionMiniWindowAdapter(
        forOwnerExtensionID ownerExtensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        auxiliaryWindowManager.focusedMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        )
    }

    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID) {
        auxiliaryWindowManager.recordAuxiliarySessionFocus(sessionId)
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

    func closeAuxiliaryWindowSessions(
        forExtensionId extensionId: String,
        reason: AuxiliaryWindowCloseReason
    ) {
        auxiliaryWindowManager.closeAll(forExtensionId: extensionId, reason: reason)
    }

    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool {
        auxiliaryWindowManager.contains(webView: webView)
    }

    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        shouldActivateApp: Bool,
        extensionOwnedSourceURL: URL?,
        ownerExtensionID: String?
    ) -> WKWebView? {
        auxiliaryWindowManager.presentExtensionExternalWebPopup(
            configuration: configuration,
            request: request,
            windowFeatures: windowFeatures,
            openerTab: openerTab,
            shouldActivateApp: shouldActivateApp,
            extensionOwnedSourceURL: extensionOwnedSourceURL,
            ownerExtensionID: ownerExtensionID
        )
    }

    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        extensionManager: ExtensionManager,
        parentWindow: NSWindow?
    ) async -> ExtensionMiniWindowAdapter? {
        await auxiliaryWindowManager.presentExtensionPopupWindow(
            configuration: configuration,
            controller: controller,
            extensionContext: extensionContext,
            extensionManager: extensionManager,
            parentWindow: parentWindow
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionBridgeCallbackSupport {
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

    func frame(for _: WKWebExtensionContext) -> CGRect {
        windowState?.window?.frame ?? .zero
    }

    func screenFrame(for _: WKWebExtensionContext) -> CGRect {
        windowState?.window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    func focus(
        for _: WKWebExtensionContext,
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

    func isPrivate(for _: WKWebExtensionContext) -> Bool {
        windowState?.isIncognito ?? false
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for _: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = windowState?.window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for _: WKWebExtensionContext,
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
        for _: WKWebExtensionContext,
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
        for _: WKWebExtensionContext,
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

    func tabs(for _: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let extensionManager, let tab else { return [] }
        guard extensionManager.isTabEligibleForCurrentExtensionRuntime(tab) else { return [] }
        guard let adapter = extensionManager.stableAdapter(for: tab) else { return [] }
        return [adapter]
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tabs(for: extensionContext).first
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .popup
    }

    func windowState(for _: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func isPrivate(for _: WKWebExtensionContext) -> Bool {
        isPrivateWindow
    }

    func screenFrame(for _: WKWebExtensionContext) -> CGRect {
        window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }

    func frame(for _: WKWebExtensionContext) -> CGRect {
        window?.frame ?? .zero
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for _: WKWebExtensionContext,
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
        for _: WKWebExtensionContext,
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
        for _: WKWebExtensionContext,
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
        for _: WKWebExtensionContext,
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
