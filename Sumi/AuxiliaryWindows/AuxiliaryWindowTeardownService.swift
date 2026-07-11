import AppKit
import Foundation
import WebKit

@MainActor
final class AuxiliaryWindowFocusService {
    private let sessions: AuxiliaryWindowSessionRegistry

    init(sessions: AuxiliaryWindowSessionRegistry) {
        self.sessions = sessions
    }

    func record(sessionID: UUID) {
        sessions.recordFocus(sessionID: sessionID)
    }

    func focus(sessionID: UUID) {
        guard let session = sessions.session(for: sessionID) else { return }
        sessions.recordFocus(sessionID: sessionID)
        session.extensionEvents?.notifyAuxiliaryWindowFocused(session)
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
        ) else {
            return false
        }
        if session.shouldActivateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        session.window.makeKeyAndOrderFront(nil)
        focus(sessionID: session.id)
        return true
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
        for webView: WKWebView,
        reason: AuxiliaryWindowCloseReason = .webViewDidClose
    ) {
        guard let session = sessions.remove(webView: webView) else { return }

        session.window.delegate = nil
        webView.stopLoading()
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
        webView.removeFromSuperview()

        session.extensionEvents?.notifyAuxiliaryWindowClosed(session)
        tabs.notifyTabClosed(session.tab)
        session.tab.performComprehensiveWebViewCleanup()
        tabs.removeMiniWindowTab(session.tab)

        if reason.shouldCloseNativeWindow, session.window.isVisible {
            session.window.close()
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

    func closeAll(
        reason: AuxiliaryWindowCloseReason = .bulkCleanup
    ) {
        let webViews = sessions.sessionsSnapshot().map(\.webView)
        webViews.forEach { teardown(for: $0, reason: reason) }
    }

    /// Live-session tab ports are no longer callable on this terminal path.
    /// Canonical WebViews are released by WebViewLifecycleService first; this
    /// method only drops auxiliary session/UI ownership and native windows.
    func closeAllAfterBrowserRuntimeDeallocation() {
        let sessionsSnapshot = sessions.sessionsSnapshot()
        for session in sessionsSnapshot {
            guard sessions.remove(webView: session.webView) != nil else { continue }
            session.window.delegate = nil
            session.webView.stopLoading()
            session.webView.uiDelegate = nil
            session.webView.navigationDelegate = nil
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
        let webViews = sessions.sessions(forExtensionID: extensionID)
            .map(\.webView)
        webViews.forEach { teardown(for: $0, reason: reason) }
    }
}

@MainActor
final class AuxiliaryWindowSessionDelegate: NSObject, NSWindowDelegate {
    private weak var sessions: AuxiliaryWindowSessionRegistry?
    private weak var teardown: AuxiliaryWindowTeardownService?
    private weak var focus: AuxiliaryWindowFocusService?
    private let sessionID: UUID

    init(
        sessions: AuxiliaryWindowSessionRegistry,
        teardown: AuxiliaryWindowTeardownService,
        focus: AuxiliaryWindowFocusService,
        sessionID: UUID
    ) {
        self.sessions = sessions
        self.teardown = teardown
        self.focus = focus
        self.sessionID = sessionID
    }

    func windowWillClose(_ notification: Notification) {
        guard let webView = sessions?.session(for: sessionID)?.webView else {
            return
        }
        teardown?.teardown(for: webView, reason: .nativeClose)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        focus?.focus(sessionID: sessionID)
    }
}
