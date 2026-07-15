import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionAuxiliaryWindowAdapter:
    ExtensionAuxiliaryWindowControl {
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

    func auxiliaryWindowSession(
        for receipt: AuxiliaryWindowSessionReceipt
    ) -> AuxiliaryWindowSession? {
        sessions.session(for: receipt)
    }

    func auxiliaryWindowSessionReceipt(
        for session: AuxiliaryWindowSession
    ) -> AuxiliaryWindowSessionReceipt? {
        sessions.receipt(for: session)
    }

    func focusedExtensionMiniWindowAdapter(
        forOwnerExtensionID ownerExtensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        focus.focusedMiniWindowAdapter(forExtensionID: ownerExtensionID)
    }

    func recordAuxiliaryWindowSessionFocus(
        _ receipt: AuxiliaryWindowSessionReceipt
    ) {
        focus.record(receipt)
    }

    func focusAuxiliaryWindowSession(
        _ receipt: AuxiliaryWindowSessionReceipt
    ) -> Bool {
        focus.focus(receipt)
    }

    func closeAuxiliaryWindowSession(
        _ receipt: AuxiliaryWindowSessionReceipt
    ) {
        teardown.teardown(receipt, reason: .extensionRequestedClose)
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
        guard let sessionReceipt = sessions.receipt(for: session) else { return }
        teardown.teardown(sessionReceipt, reason: reason)
    }
}
