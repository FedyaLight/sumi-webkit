import AppKit
import Foundation
import WebKit

@MainActor
final class AuxiliaryWindowFocusService {
    private let sessions: AuxiliaryWindowSessionRegistry

    init(sessions: AuxiliaryWindowSessionRegistry) {
        self.sessions = sessions
    }

    func record(_ receipt: AuxiliaryWindowSessionReceipt) {
        sessions.recordFocus(receipt)
    }

    @discardableResult
    func focus(_ receipt: AuxiliaryWindowSessionReceipt) -> Bool {
        guard let session = sessions.session(for: receipt) else { return false }
        sessions.recordFocus(receipt)
        guard sessions.session(for: receipt) === session else { return false }
        session.extensionEvents?.notifyAuxiliaryWindowFocused(session)
        return sessions.session(for: receipt) === session
    }

    func focusedMiniWindowAdapter(
        forExtensionID extensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        sessions.mostRecentlyFocusedSession(forExtensionID: extensionID)?
            .miniWindowAdapter
    }

    @discardableResult
    func restoreMostRecentWindow(forExtensionID extensionID: String) -> Bool {
        guard let session = sessions.mostRecentlyFocusedSession(
            forExtensionID: extensionID
        ), let receipt = sessions.receipt(for: session) else {
            return false
        }
        if session.shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
            guard sessions.session(for: receipt) === session else {
                return false
            }
        }
        session.window.makeKeyAndOrderFront(nil)
        guard sessions.session(for: receipt) === session,
              focus(receipt)
        else {
            return false
        }
        return sessions.session(for: receipt) === session
    }
}

@MainActor
final class AuxiliaryWindowTeardownService {
    private let sessions: AuxiliaryWindowSessionRegistry
    private let tabs: any AuxiliaryWindowTabLifecycle
    private let focus: AuxiliaryWindowFocusService

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        tabs: any AuxiliaryWindowTabLifecycle,
        focus: AuxiliaryWindowFocusService
    ) {
        self.sessions = sessions
        self.tabs = tabs
        self.focus = focus
    }

    func teardown(
        _ receipt: AuxiliaryWindowSessionReceipt,
        reason: AuxiliaryWindowCloseReason = .webViewDidClose
    ) {
        guard let session = sessions.remove(receipt) else { return }

        session.window.delegate = nil
        session.webView.uiDelegate = nil
        session.webView.navigationDelegate = nil
        session.webView.stopLoading()
        session.webView.removeFromSuperview()

        session.tab.performComprehensiveWebViewCleanup()
        tabs.removeMiniWindowTab(session.tab)

        if reason.shouldCloseNativeWindow, session.window.isVisible {
            session.window.close()
        }

        session.extensionEvents?.notifyAuxiliaryWindowClosed(session)
        guard physicalIdentityWasNotReused(afterRetiring: session) else {
            return
        }

        let restoredExtensionWindow: Bool
        if reason.shouldRestoreExtensionFocus,
           let extensionID = session.ownerExtensionID {
            restoredExtensionWindow = focus.restoreMostRecentWindow(
                forExtensionID: extensionID
            )
        } else {
            restoredExtensionWindow = false
        }

        if restoredExtensionWindow == false,
           reason.shouldRestoreOpenerFocus,
           session.shouldActivateApp,
           let openerWindow = session.openerWindow,
           openerWindow.isVisible {
            openerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func physicalIdentityWasNotReused(
        afterRetiring session: AuxiliaryWindowSession
    ) -> Bool {
        sessions.session(for: session.webView) == nil
            && sessions.session(for: session.window) == nil
            && sessions.session(for: session.tab) == nil
    }

    func closeAll(
        reason: AuxiliaryWindowCloseReason = .bulkCleanup
    ) {
        let receipts = sessions.sessionsSnapshot().compactMap {
            sessions.receipt(for: $0)
        }
        receipts.forEach { teardown($0, reason: reason) }
    }

    /// Live-session tab ports are no longer callable on this terminal path.
    /// Canonical WebViews are released by WebViewLifecycleService first; this
    /// method only drops auxiliary session/UI ownership and native windows.
    func closeAllAfterBrowserRuntimeDeallocation() {
        let receipts = sessions.sessionsSnapshot().compactMap {
            sessions.receipt(for: $0)
        }
        for receipt in receipts {
            guard let session = sessions.remove(receipt) else { continue }
            session.window.delegate = nil
            session.webView.uiDelegate = nil
            session.webView.navigationDelegate = nil
            session.webView.stopLoading()
            session.webView.removeFromSuperview()
            if session.window.isVisible {
                session.window.close()
            }
        }
    }

    func closeAll(
        forExtensionID extensionID: String,
        reason: AuxiliaryWindowCloseReason = .extensionDisable
    ) {
        let receipts = sessions.sessions(forExtensionID: extensionID)
            .compactMap { sessions.receipt(for: $0) }
        receipts.forEach { teardown($0, reason: reason) }
    }
}

@MainActor
final class AuxiliaryWindowSessionDelegate: NSObject, NSWindowDelegate {
    private weak var teardown: AuxiliaryWindowTeardownService?
    private weak var focus: AuxiliaryWindowFocusService?
    private var sessionReceipt: AuxiliaryWindowSessionReceipt?

    init(
        teardown: AuxiliaryWindowTeardownService,
        focus: AuxiliaryWindowFocusService
    ) {
        self.teardown = teardown
        self.focus = focus
    }

    func bind(_ receipt: AuxiliaryWindowSessionReceipt) {
        precondition(sessionReceipt == nil)
        sessionReceipt = receipt
    }

    func windowWillClose(_ notification: Notification) {
        guard let sessionReceipt else { return }
        teardown?.teardown(sessionReceipt, reason: .nativeClose)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let sessionReceipt else { return }
        focus?.focus(sessionReceipt)
    }
}
