//
//  ExtensionBridge.swift
//  Sumi
//
//  WebKit bridge adapters that expose Sumi windows and tabs to WebExtensions.
//

import AppKit
import Foundation
import SumiWebRuntime
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabTargetQuery: AnyObject {
    func extensionWindowState(for windowId: UUID) -> BrowserWindowState?
    var activeExtensionWindowState: BrowserWindowState? { get }
    func extensionWindowState(containing tab: Tab) -> BrowserWindowState?
    func preferredExtensionWindowState(
        containing tab: Tab
    ) -> BrowserWindowState?
    func extensionTargetSpace(for windowState: BrowserWindowState?) -> Space?
    func extensionTargetSpace(for tab: Tab) -> Space?
    func extensionTargetSpace(matchingProfile profileId: UUID) -> Space?
    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabCreation: AnyObject {
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
    @discardableResult
    func pinExtensionTab(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?
    ) -> Bool
    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState)
    func placeExtensionTab(_ tab: Tab, in windowState: BrowserWindowState)
    @discardableResult
    func discardExtensionRequestedTab(
        _ tab: Tab,
        restoringSelectionTo tabID: UUID?
    ) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabLiveWebViewQuery: AnyObject {
    func extensionLiveWebView(for tab: Tab) -> WKWebView?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWebViewResidenceQuery: AnyObject {
    func extensionLiveWebViews(for tab: Tab) -> [WKWebView]
    func extensionUntrackedWebView(for tab: Tab) -> WKWebView?
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionTabWebViewRebuildSubmissionOutcome: Equatable {
    case committed
    case deferred
    case noLiveWindows
    case failed
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWebViewRebuilding: AnyObject {
    @discardableResult
    func rebuildExtensionLiveWebViews(
        for tab: Tab,
        reason: String
    ) -> ExtensionTabWebViewRebuildSubmissionOutcome
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabReloadHosting: AnyObject {
    func reloadExtensionTab(
        _ tab: Tab,
        webView: WKWebView,
        in windowState: BrowserWindowState?,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWebViewHosting:
    ExtensionTabLiveWebViewQuery,
    ExtensionTabReloadHosting {
    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    )
    func extensionWindowOwnedWebView(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView?
    func replaceExtensionLiveWebView(
        for tab: Tab,
        in windowState: BrowserWindowState?,
        reason: String,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)?,
        prepareCommittedReplacement: ((WKWebView) -> Void)?,
        validate: ((WKWebView) -> Bool)?
    ) -> WKWebView?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWindowQuery: ExtensionTabWindowProjectionQuery {
    var allExtensionWindowStates: [BrowserWindowState] { get }
    var activeExtensionWindowState: BrowserWindowState? { get }
    func extensionWindowState(for windowId: UUID) -> BrowserWindowState?
    func extensionWindowState(containing tab: Tab) -> BrowserWindowState?
    func extensionWindowState(forAppKitWindow window: NSWindow) -> BrowserWindowState?
    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow?
    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab?
    func extensionTab(
        withID tabID: UUID,
        in windowState: BrowserWindowState
    ) -> Tab?
    func currentExtensionTabForActiveWindow() -> Tab?
    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab]
    func preferredExtensionWindowState(containing tab: Tab) -> BrowserWindowState?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabInventory: AnyObject {
    var allExtensionTabs: [Tab] { get }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabQuery: ExtensionTabPinningQuery {
    func extensionTab(for tabId: UUID) -> Tab?
    func isTransientExtensionTab(_ tab: Tab) -> Bool
    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool
    func isPinnedExtensionTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabCommandRouting: AnyObject {
    func selectExtensionTab(_ tab: Tab, in windowState: BrowserWindowState)
    func promoteTransientExtensionTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabMutation:
    ExtensionTabCreation,
    ExtensionTabCommandRouting {}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWindowActivation: AnyObject {
    func setActiveExtensionWindow(_ windowState: BrowserWindowState)
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionAuxiliaryWindowSessionReceipt {
    let sessionID: UUID
    let ownerExtensionID: String
    private let sessionIdentity: ObjectIdentifier

    init(session: AuxiliaryWindowSession, ownerExtensionID: String) {
        sessionID = session.id
        self.ownerExtensionID = ownerExtensionID
        sessionIdentity = ObjectIdentifier(session)
    }

    init(
        sessionID: UUID,
        ownerExtensionID: String,
        sessionIdentity: ObjectIdentifier
    ) {
        self.sessionID = sessionID
        self.ownerExtensionID = ownerExtensionID
        self.sessionIdentity = sessionIdentity
    }

    func represents(_ session: AuxiliaryWindowSession) -> Bool {
        session.id == sessionID
            && session.ownerExtensionID == ownerExtensionID
            && ObjectIdentifier(session) == sessionIdentity
    }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionAuxiliaryWindowControl:
    ExtensionAuxiliaryTabSessionQuery,
    ExtensionAuxiliaryTabClosing {
    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for window: NSWindow) -> AuxiliaryWindowSession?
    func focusedExtensionMiniWindowAdapter(forOwnerExtensionID ownerExtensionID: String) -> ExtensionMiniWindowAdapter?
    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID)
    func focusAuxiliaryWindowSession(_ sessionId: UUID)
    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession)
    func closeAuxiliaryWindowWebView(_ webView: WKWebView)
    func auxiliaryWindowSessionReceipts(
        forExtensionID extensionID: String
    ) -> [ExtensionAuxiliaryWindowSessionReceipt]
    func closeAuxiliaryWindowSession(
        _ receipt: ExtensionAuxiliaryWindowSessionReceipt,
        reason: AuxiliaryWindowCloseReason
    )
    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWindowPresentation: AnyObject {
    func presentExtensionExternalWebPopup(
        configuration: WKWebViewConfiguration,
        request: URLRequest?,
        windowFeatures: WKWindowFeatures,
        openerTab: Tab,
        openerWindow: NSWindow,
        openerProfileID: UUID,
        shouldActivateApp: Bool,
        extensionOwnedSourceURL: URL?,
        ownerExtensionID: String?
    ) -> WKWebView?
    func presentExtensionPopupWindow(
        configuration: WKWebExtension.WindowConfiguration,
        evidence: ExtensionControllerCallbackEvidence,
        admission: ExtensionControllerCallbackAdmission,
        runtime: ExtensionAuxiliaryWindowCallbackRuntime,
        parentWindow: NSWindow?
    ) async -> ExtensionPopupWindowPresentationReceipt?
    func extensionURLHubFallbackAnchorView(for windowId: UUID) -> NSView?
    /// Space-resolved appearance for the extension action popup anchored in the
    /// given AppKit window. `nil` leaves the popover on the system appearance.
    func extensionActionPopupAppearance(
        forAnchorWindow window: NSWindow,
        fallback: NSAppearance?
    ) -> NSAppearance?
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionPopupWindowPresentationReceipt {
    @MainActor
    private final class Retirement {
        private var didRetire = false
        private let action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        func perform() {
            guard didRetire == false else { return }
            didRetire = true
            action()
        }
    }

    let sessionID: UUID
    let adapter: ExtensionMiniWindowAdapter
    private let retirement: Retirement

    init(
        sessionID: UUID,
        adapter: ExtensionMiniWindowAdapter,
        retireExactSession: @escaping @MainActor () -> Void
    ) {
        self.sessionID = sessionID
        self.adapter = adapter
        retirement = Retirement(action: retireExactSession)
    }

    func retire() {
        retirement.perform()
    }
}

@available(macOS 15.5, *)
extension ExtensionWindowPresentation {
    func extensionActionPopupAppearance(
        forAnchorWindow window: NSWindow,
        fallback: NSAppearance?
    ) -> NSAppearance? {
        nil
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

    private weak var exactWindowState: BrowserWindowState?
    private weak var windowQuery: (any ExtensionWindowQuery)?
    private weak var windowActivation: (any ExtensionWindowActivation)?
    private weak var contextPublications: ExtensionContextPublicationQuery?
    private weak var extensionManager: ExtensionManager?
    private let preparedTabVisibility: ExtensionPreparedTabVisibility

    init(
        windowState: BrowserWindowState,
        windowQuery: any ExtensionWindowQuery,
        windowActivation: any ExtensionWindowActivation,
        contextPublications: ExtensionContextPublicationQuery,
        preparedTabVisibility: ExtensionPreparedTabVisibility,
        extensionManager: ExtensionManager
    ) {
        self.windowId = windowState.id
        self.exactWindowState = windowState
        self.windowQuery = windowQuery
        self.windowActivation = windowActivation
        self.contextPublications = contextPublications
        self.preparedTabVisibility = preparedTabVisibility
        self.extensionManager = extensionManager
        super.init()
    }

    private var windowState: BrowserWindowState? {
        guard let exactWindowState,
              windowQuery?.extensionWindowState(for: windowId)
                === exactWindowState
        else {
            return nil
        }
        return exactWindowState
    }

    private func publishedWindowState(
        for extensionContext: WKWebExtensionContext
    ) -> BrowserWindowState? {
        guard let extensionManager,
              let windowState,
              let contextProfileId = contextPublications?.currentIdentity(
                for: extensionContext
              )?.profileID,
              extensionManager.windowMatchesProfile(
                windowState,
                profileId: contextProfileId
              ),
              extensionManager.windowPublications.publishedWindowAdapter(
                    for: windowState,
                    profileID: contextProfileId
                ) === self
        else {
            return nil
        }
        return windowState
    }

    func represents(_ windowState: BrowserWindowState) -> Bool {
        exactWindowState === windowState
            && self.windowState === windowState
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionWindowAdapter else {
            return false
        }
        return other === self
    }

    override var hash: Int {
        ObjectIdentifier(self).hashValue
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard
            let windowQuery,
            let extensionManager,
            let windowState = publishedWindowState(for: extensionContext),
            let contextProfileId = contextPublications?.currentIdentity(
                for: extensionContext
            )?.profileID,
            let tab = windowQuery.currentExtensionTab(in: windowState),
            extensionManager.resolvedProfileId(for: tab) == contextProfileId,
            tabIsVisibleToPublishedWindow(tab, in: windowState)
        else {
            SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
                seesCurrentTab: false,
                extensionId: extensionManager?.extensionID(for: extensionContext),
                reason: "activeTabAdapterUnavailable"
            )
            return nil
        }

        let adapter = extensionManager.adapterCatalog.stableAdapter(for: tab)
        SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
            seesCurrentTab: adapter != nil,
            extensionId: extensionManager.extensionID(for: extensionContext),
            reason: "activeTabAdapterResolved"
        )
        return adapter
    }

    func tabs(for extensionContext: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let windowQuery,
              let extensionManager,
              let windowState = publishedWindowState(for: extensionContext),
              let contextProfileId = contextPublications?.currentIdentity(
                for: extensionContext
              )?.profileID,
              extensionManager.windowMatchesProfile(
                windowState,
                profileId: contextProfileId
              )
        else { return [] }

        return windowQuery.tabsForExtensionWindow(windowState).filter {
            extensionManager.resolvedProfileId(for: $0) == contextProfileId
                && tabIsVisibleToPublishedWindow($0, in: windowState)
        }.compactMap {
            extensionManager.adapterCatalog.stableAdapter(for: $0)
        }
    }

    private func tabIsVisibleToPublishedWindow(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let extensionManager else { return false }
        if extensionManager.publishedExtensionTabs.containsPublishedTab(tab) {
            return true
        }
        return preparedTabVisibility.allowsPreparedTabRead(
            tab,
            in: windowState,
            through: self
        ) && extensionManager.preparedExtensionTabs.containsPreparedTab(tab)
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        appKitWindow(for: extensionContext)?.frame ?? .zero
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard let window = appKitWindow(for: extensionContext) else {
            return .zero
        }
        return window.screen?.frame ?? .zero
    }

    func focus(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let windowState = publishedWindowState(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .focus)
                    .nsError()
            )
            return
        }

        appKitWindow(for: windowState)?.makeKeyAndOrderFront(nil)
        windowActivation?.setActiveExtensionWindow(windowState)
        NSApp.activate(ignoringOtherApps: true)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        publishedWindowState(for: extensionContext)?.isIncognito ?? false
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for extensionContext: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = appKitWindow(for: extensionContext) else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .setWindowState)
                    .nsError()
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
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .setFrame)
                    .nsError()
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
        guard let window = appKitWindow(for: extensionContext) else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .windowUnavailable(operation: .close)
                    .nsError()
            )
            return
        }

        window.performClose(nil)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    private func appKitWindow(for extensionContext: WKWebExtensionContext) -> NSWindow? {
        guard let windowState = publishedWindowState(for: extensionContext) else {
            return nil
        }
        return appKitWindow(for: windowState)
    }

    private func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        windowQuery?.appKitWindow(for: windowState)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionMiniWindowAdapter: NSObject, WKWebExtensionWindow {
    let sessionId: UUID
    let tabId: UUID

    private weak var auxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
    private weak var windowPublications: ExtensionWindowPublicationQuery?
    private weak var window: NSWindow?
    private let isPrivateWindow: Bool
    private let shouldActivateApp: Bool

    init(
        sessionId: UUID,
        tab: Tab,
        window: NSWindow,
        auxiliaryWindows: any ExtensionAuxiliaryWindowControl,
        windowPublications: ExtensionWindowPublicationQuery,
        isPrivate: Bool,
        shouldActivateApp: Bool
    ) {
        self.sessionId = sessionId
        self.tabId = tab.id
        self.window = window
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
        self.isPrivateWindow = isPrivate
        self.shouldActivateApp = shouldActivateApp
        super.init()
    }

    private func isAvailable(
        to extensionContext: WKWebExtensionContext
    ) -> Bool {
        windowPublications?.isCurrentAuxiliaryWindowAdapter(
            self,
            visibleTo: extensionContext
        ) == true
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? ExtensionMiniWindowAdapter else { return false }
        return other.sessionId == sessionId
    }

    override var hash: Int {
        sessionId.hashValue
    }

    func tabs(
        for extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionTab] {
        guard let adapter = windowPublications?
            .publishedAuxiliaryTabAdapter(
                for: self,
                visibleTo: extensionContext
            ) else { return [] }
        return [adapter]
    }

    func activeTab(for extensionContext: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        tabs(for: extensionContext).first
    }

    func windowType(
        for extensionContext: WKWebExtensionContext
    ) -> WKWebExtension.WindowType {
        isAvailable(to: extensionContext) ? .popup : .normal
    }

    func windowState(
        for extensionContext: WKWebExtensionContext
    ) -> WKWebExtension.WindowState {
        guard isAvailable(to: extensionContext), let window else {
            return .normal
        }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func isPrivate(for extensionContext: WKWebExtensionContext) -> Bool {
        isAvailable(to: extensionContext) && isPrivateWindow
    }

    func screenFrame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard isAvailable(to: extensionContext) else { return .zero }
        return window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
    }

    func frame(for extensionContext: WKWebExtensionContext) -> CGRect {
        guard isAvailable(to: extensionContext) else { return .zero }
        return window?.frame ?? .zero
    }

    func setWindowState(
        _ windowState: WKWebExtension.WindowState,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard isAvailable(to: extensionContext), let window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .miniWindowUnavailable(operation: .setWindowState)
                    .nsError()
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
        guard isAvailable(to: extensionContext), let window else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .miniWindowUnavailable(operation: .setFrame)
                    .nsError()
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
        guard isAvailable(to: extensionContext), window != nil else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .miniWindowUnavailable(operation: .focus)
                    .nsError()
            )
            return
        }
        if shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        auxiliaryWindows?.focusAuxiliaryWindowSession(sessionId)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }

    func close(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard isAvailable(to: extensionContext),
              let auxiliaryWindows,
              let session = auxiliaryWindows.auxiliaryWindowSession(for: sessionId)
        else {
            ExtensionBridgeCallbackSupport.complete(
                completionHandler,
                api: .windowAdapterCompletion,
                error: ExtensionBridgeAdapterCallbackError
                    .miniWindowUnavailable(operation: .close)
                    .nsError()
            )
            return
        }

        auxiliaryWindows.closeAuxiliaryWindowSession(session)
        ExtensionBridgeCallbackSupport.complete(completionHandler, api: .windowAdapterCompletion, error: nil)
    }
}
