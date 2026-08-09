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
func webExtensionWindowState(
    of window: NSWindow
) -> WKWebExtension.WindowState {
    switch BrowserWindowGeometryPolicy.displayMode(of: window) {
    case .normal:
        return .normal
    case .zoomed:
        return .maximized
    case .fullScreen:
        return .fullscreen
    case .miniaturized:
        return .minimized
    }
}
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
    ) -> PageReloadCommandOutcome
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
protocol ExtensionAuxiliaryTabClosing: ExtensionAuxiliaryTabSessionQuery {
    func auxiliaryWindowSessionReceipt(
        for session: AuxiliaryWindowSession
    ) -> AuxiliaryWindowSessionReceipt?
    func closeAuxiliaryWindowSession(
        _ receipt: AuxiliaryWindowSessionReceipt
    )
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionAuxiliaryWindowControl:
    ExtensionAuxiliaryTabSessionQuery,
    ExtensionAuxiliaryTabClosing {
    func auxiliaryWindowSession(for sessionId: UUID) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(for window: NSWindow) -> AuxiliaryWindowSession?
    func auxiliaryWindowSession(
        for receipt: AuxiliaryWindowSessionReceipt
    ) -> AuxiliaryWindowSession?
    func focusedExtensionMiniWindowAdapter(forOwnerExtensionID ownerExtensionID: String) -> ExtensionMiniWindowAdapter?
    func recordAuxiliaryWindowSessionFocus(
        _ receipt: AuxiliaryWindowSessionReceipt
    )
    @discardableResult
    func focusAuxiliaryWindowSession(
        _ receipt: AuxiliaryWindowSessionReceipt
    ) -> Bool
    func auxiliaryWindowSessionReceipts(
        forExtensionID extensionID: String
    ) -> [ExtensionAuxiliaryWindowSessionReceipt]
    func closeAuxiliaryWindowSession(
        _ receipt: ExtensionAuxiliaryWindowSessionReceipt,
        reason: AuxiliaryWindowCloseReason
    )
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWindowPresentation: AnyObject {
    func presentExtensionPopupWindow(
        request: ExtensionWindowOpeningRequest,
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
    let sessionIdentity: ObjectIdentifier
    let webViewIdentity: ObjectIdentifier
    let adapter: ExtensionMiniWindowAdapter
    private let retirement: Retirement

    init(
        sessionReceipt: AuxiliaryWindowSessionReceipt,
        adapter: ExtensionMiniWindowAdapter,
        retireExactSession: @escaping @MainActor () -> Void
    ) {
        sessionID = sessionReceipt.sessionID
        sessionIdentity = sessionReceipt.sessionIdentity
        webViewIdentity = sessionReceipt.webViewIdentity
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
