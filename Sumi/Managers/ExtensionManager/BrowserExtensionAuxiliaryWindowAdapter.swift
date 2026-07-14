import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionAuxiliaryWindowAdapter:
    ExtensionAuxiliaryWindowControl
{
    private let sessions: AuxiliaryWindowSessionRegistry
    private let focus: AuxiliaryWindowFocusService
    private let teardown: AuxiliaryWindowTeardownService

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        focus: AuxiliaryWindowFocusService,
        teardown: AuxiliaryWindowTeardownService
    ) {
        self.sessions = sessions
        self.focus = focus
        self.teardown = teardown
    }

    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession? {
        sessions.session(for: tab)
    }

    func auxiliaryWindowSession(
        for sessionId: UUID
    ) -> AuxiliaryWindowSession? {
        sessions.session(for: sessionId)
    }

    func auxiliaryWindowSession(
        for window: NSWindow
    ) -> AuxiliaryWindowSession? {
        sessions.session(for: window)
    }

    func focusedExtensionMiniWindowAdapter(
        forOwnerExtensionID ownerExtensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        focus.focusedMiniWindowAdapter(forExtensionID: ownerExtensionID)
    }

    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID) {
        focus.record(sessionID: sessionId)
    }

    func focusAuxiliaryWindowSession(_ sessionId: UUID) {
        focus.focus(sessionID: sessionId)
    }

    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession) {
        teardown.teardown(
            for: session.webView,
            reason: .extensionRequestedClose
        )
    }

    func closeAuxiliaryWindowWebView(_ webView: WKWebView) {
        teardown.teardown(
            for: webView,
            reason: .extensionRequestedClose
        )
    }

    func auxiliaryWindowSessionReceipts(
        forExtensionID extensionID: String
    ) -> [ExtensionAuxiliaryWindowSessionReceipt] {
        sessions.sessions(forExtensionID: extensionID).compactMap { session in
            guard session.ownerExtensionID == extensionID else { return nil }
            return ExtensionAuxiliaryWindowSessionReceipt(
                session: session,
                ownerExtensionID: extensionID
            )
        }
    }

    func closeAuxiliaryWindowSession(
        _ receipt: ExtensionAuxiliaryWindowSessionReceipt,
        reason: AuxiliaryWindowCloseReason
    ) {
        guard let session = sessions.session(for: receipt.sessionID),
              receipt.represents(session)
        else {
            return
        }
        teardown.teardown(
            for: session.webView,
            reason: reason
        )
    }

    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool {
        sessions.contains(webView)
    }
}
