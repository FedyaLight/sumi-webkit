import AppKit
import Foundation
import WebKit

enum AuxiliaryWindowCloseReason: String {
    case webViewDidClose
    case nativeClose
    case extensionRequestedClose
    case presentationFailure
    case profileSwitch
    case appQuit
    case extensionDisable
    case bulkCleanup

    var shouldCloseNativeWindow: Bool {
        self != .nativeClose
    }

    var shouldRestoreOpenerFocus: Bool {
        switch self {
        case .webViewDidClose, .nativeClose, .extensionRequestedClose:
            true
        case .presentationFailure, .profileSwitch, .appQuit,
             .extensionDisable, .bulkCleanup:
            false
        }
    }

    var shouldRestoreExtensionFocus: Bool {
        shouldRestoreOpenerFocus
    }
}

/// Immutable authority for one exact physical auxiliary session. A WebView
/// can be registered again after teardown, so its identity alone is never a
/// sufficient retirement capability.
struct AuxiliaryWindowSessionReceipt: Hashable {
    let sessionID: UUID
    let sessionIdentity: ObjectIdentifier
    let webViewIdentity: ObjectIdentifier

    @MainActor
    fileprivate init(session: AuxiliaryWindowSession) {
        sessionID = session.id
        sessionIdentity = ObjectIdentifier(session)
        webViewIdentity = ObjectIdentifier(session.webView)
    }
}

@MainActor
final class AuxiliaryWindowSession {
    let id: UUID
    let tab: Tab
    let window: AuxiliaryCompactWindow
    let webView: WKWebView
    let openerTab: Tab?
    weak var openerWindow: NSWindow?
    let shouldActivateApp: Bool
    let isPrivate: Bool
    let ownerExtensionID: String?
    let miniWindowAdapter: ExtensionMiniWindowAdapter?
    /// The session owns the lifetime projection; the projection itself keeps
    /// the extension runtime root weak. This preserves callbacks for the
    /// session lifetime without making the browser session retain extensions.
    let extensionEvents: (any AuxiliaryWindowExtensionEventHandling)?
    let uiDelegate: AuxiliaryWindowUIDelegate
    let windowDelegate: AuxiliaryWindowSessionDelegate

    init(
        id: UUID,
        tab: Tab,
        window: AuxiliaryCompactWindow,
        webView: WKWebView,
        openerTab: Tab?,
        openerWindow: NSWindow?,
        shouldActivateApp: Bool,
        isPrivate: Bool,
        ownerExtensionID: String?,
        miniWindowAdapter: ExtensionMiniWindowAdapter?,
        extensionEvents: (any AuxiliaryWindowExtensionEventHandling)?,
        uiDelegate: AuxiliaryWindowUIDelegate,
        windowDelegate: AuxiliaryWindowSessionDelegate
    ) {
        self.id = id
        self.tab = tab
        self.window = window
        self.webView = webView
        self.openerTab = openerTab
        self.openerWindow = openerWindow
        self.shouldActivateApp = shouldActivateApp
        self.isPrivate = isPrivate
        self.ownerExtensionID = ownerExtensionID
        self.miniWindowAdapter = miniWindowAdapter
        self.extensionEvents = extensionEvents
        self.uiDelegate = uiDelegate
        self.windowDelegate = windowDelegate
    }
}

/// Canonical lifetime index for auxiliary windows. Registration and removal
/// update every identity index atomically on the main actor.
@MainActor
final class AuxiliaryWindowSessionRegistry {
    private var sessionsByID: [UUID: AuxiliaryWindowSession] = [:]
    private var sessionIDByWebView: [ObjectIdentifier: UUID] = [:]
    private var sessionIDByWindow: [ObjectIdentifier: UUID] = [:]
    private var sessionIDByTabID: [UUID: UUID] = [:]
    private var focusOrderByExtensionID: [String: [UUID]] = [:]

    @discardableResult
    func register(
        _ session: AuxiliaryWindowSession
    ) -> AuxiliaryWindowSessionReceipt {
        let webViewID = ObjectIdentifier(session.webView)
        let windowID = ObjectIdentifier(session.window)

        precondition(sessionsByID[session.id] == nil)
        precondition(sessionIDByWebView[webViewID] == nil)
        precondition(sessionIDByWindow[windowID] == nil)
        precondition(sessionIDByTabID[session.tab.id] == nil)

        sessionsByID[session.id] = session
        sessionIDByWebView[webViewID] = session.id
        sessionIDByWindow[windowID] = session.id
        sessionIDByTabID[session.tab.id] = session.id
        return AuxiliaryWindowSessionReceipt(session: session)
    }

    func session(for id: UUID) -> AuxiliaryWindowSession? {
        sessionsByID[id]
    }

    func session(for window: NSWindow) -> AuxiliaryWindowSession? {
        sessionIDByWindow[ObjectIdentifier(window)].flatMap { sessionsByID[$0] }
    }

    func session(for webView: WKWebView) -> AuxiliaryWindowSession? {
        sessionIDByWebView[ObjectIdentifier(webView)].flatMap { sessionsByID[$0] }
    }

    func session(for tab: Tab) -> AuxiliaryWindowSession? {
        sessionIDByTabID[tab.id].flatMap { sessionsByID[$0] }
    }

    func receipt(
        for session: AuxiliaryWindowSession
    ) -> AuxiliaryWindowSessionReceipt? {
        let receipt = AuxiliaryWindowSessionReceipt(session: session)
        guard isCurrent(receipt) else { return nil }
        return receipt
    }

    func session(
        for receipt: AuxiliaryWindowSessionReceipt
    ) -> AuxiliaryWindowSession? {
        guard isCurrent(receipt) else { return nil }
        return sessionsByID[receipt.sessionID]
    }

    func contains(_ webView: WKWebView) -> Bool {
        session(for: webView) != nil
    }

    func ownerExtensionID(for webView: WKWebView) -> String? {
        session(for: webView)?.ownerExtensionID
    }

    func sessionsSnapshot() -> [AuxiliaryWindowSession] {
        Array(sessionsByID.values)
    }

    func sessions(forExtensionID extensionID: String) -> [AuxiliaryWindowSession] {
        sessionsByID.values.filter { $0.ownerExtensionID == extensionID }
    }

    @discardableResult
    func remove(
        _ receipt: AuxiliaryWindowSessionReceipt
    ) -> AuxiliaryWindowSession? {
        guard isCurrent(receipt),
              let session = sessionsByID.removeValue(
                  forKey: receipt.sessionID
              )
        else { return nil }

        sessionIDByWebView.removeValue(forKey: receipt.webViewIdentity)

        let windowID = ObjectIdentifier(session.window)
        if sessionIDByWindow[windowID] == receipt.sessionID {
            sessionIDByWindow.removeValue(forKey: windowID)
        }
        if sessionIDByTabID[session.tab.id] == receipt.sessionID {
            sessionIDByTabID.removeValue(forKey: session.tab.id)
        }
        removeFromFocusHistory(
            receipt.sessionID,
            extensionID: session.ownerExtensionID
        )
        return session
    }

    private func isCurrent(_ receipt: AuxiliaryWindowSessionReceipt) -> Bool {
        guard let session = sessionsByID[receipt.sessionID] else {
            return false
        }
        return ObjectIdentifier(session) == receipt.sessionIdentity
            && ObjectIdentifier(session.webView) == receipt.webViewIdentity
            && sessionIDByWebView[receipt.webViewIdentity]
                == receipt.sessionID
            && sessionIDByWindow[ObjectIdentifier(session.window)]
                == receipt.sessionID
            && sessionIDByTabID[session.tab.id] == receipt.sessionID
    }

    func recordFocus(_ receipt: AuxiliaryWindowSessionReceipt) {
        guard let session = session(for: receipt),
              let extensionID = session.ownerExtensionID else {
            return
        }
        let sessionID = session.id
        var order = focusOrderByExtensionID[extensionID] ?? []
        order.removeAll { $0 == sessionID }
        order.append(sessionID)
        focusOrderByExtensionID[extensionID] = order
    }

    func mostRecentlyFocusedSession(
        forExtensionID extensionID: String
    ) -> AuxiliaryWindowSession? {
        var order = focusOrderByExtensionID[extensionID] ?? []
        while let sessionID = order.last {
            guard let session = sessionsByID[sessionID],
                  session.ownerExtensionID == extensionID,
                  session.window.isVisible,
                  session.miniWindowAdapter != nil else {
                order.removeLast()
                continue
            }
            focusOrderByExtensionID[extensionID] = order
            return session
        }
        focusOrderByExtensionID.removeValue(forKey: extensionID)
        return nil
    }

    private func removeFromFocusHistory(
        _ sessionID: UUID,
        extensionID: String?
    ) {
        guard let extensionID,
              var order = focusOrderByExtensionID[extensionID] else {
            return
        }
        order.removeAll { $0 == sessionID }
        if order.isEmpty {
            focusOrderByExtensionID.removeValue(forKey: extensionID)
        } else {
            focusOrderByExtensionID[extensionID] = order
        }
    }
}
