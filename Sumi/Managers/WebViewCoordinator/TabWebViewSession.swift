//
//  TabWebViewSession.swift
//  Sumi
//
//  Phase 6B: Tab WebView session outside Tab model fields.
//

import Foundation
import WebKit

/// Per-tab WebView session material that is not window-registry tracked.
///
/// - `untrackedWebView`: pre-window / Glance-style ownership (`primaryWindowId == nil`)
/// - `parkedWebView`: staging for ensure reuse
/// - Windowed primaries live in `WindowWebViewRegistry` (referenced via `primaryWindowId`)
///
/// Phase 6B: session `note*` APIs are the authoritative writers when a browser
/// runtime is attached. Tab model fields remain a compatibility mirror.
@MainActor
final class TabWebViewSession {
    let tabId: UUID
    var untrackedWebView: WKWebView?
    var parkedWebView: WKWebView?
    var primaryWindowId: UUID?

    init(tabId: UUID) {
        self.tabId = tabId
    }

    func clearUntracked() {
        untrackedWebView = nil
        primaryWindowId = nil
    }

    func clearParked() {
        parkedWebView = nil
    }

    func clearAll() {
        untrackedWebView = nil
        parkedWebView = nil
        primaryWindowId = nil
    }
}

/// Coordinator-owned store wrapping registry + parked/untracked staging.
@MainActor
final class TabWebViewSessionStore {
    private let webViewRegistry: WindowWebViewRegistry
    private var sessions: [UUID: TabWebViewSession] = [:]

    init(webViewRegistry: WindowWebViewRegistry) {
        self.webViewRegistry = webViewRegistry
    }

    func session(for tabId: UUID) -> TabWebViewSession {
        if let existing = sessions[tabId] {
            return existing
        }
        let created = TabWebViewSession(tabId: tabId)
        sessions[tabId] = created
        return created
    }

    /// Imports Tab mirror fields when the session slot is still empty (compat bridge).
    /// Prefer coordinator/Tab `note*` writers; this keeps teardown/rebuild honest for
    /// tabs that parked/ensured before a session store was attached.
    func syncFromTabIfNeeded(_ tab: Tab) {
        let session = session(for: tab.id)
        if session.parkedWebView == nil, let parked = tab.parkedWebView {
            session.parkedWebView = parked
        }
        if let primaryWindowId = tab.primaryWindowId {
            session.primaryWindowId = primaryWindowId
            session.untrackedWebView = nil
        } else if session.untrackedWebView == nil, let current = tab.currentWebView {
            session.untrackedWebView = current
            session.primaryWindowId = nil
        }
    }

    func noteParkedWebView(_ webView: WKWebView?, for tabId: UUID) {
        let session = session(for: tabId)
        session.parkedWebView = webView
    }

    func noteUntrackedWebView(_ webView: WKWebView?, for tabId: UUID) {
        let session = session(for: tabId)
        session.untrackedWebView = webView
        session.primaryWindowId = nil
    }

    func notePrimaryAssignment(windowId: UUID, for tabId: UUID) {
        let session = session(for: tabId)
        session.primaryWindowId = windowId
        session.untrackedWebView = nil
    }

    func clearPrimaryAssignment(for tabId: UUID) {
        let session = session(for: tabId)
        session.primaryWindowId = nil
    }

    func clearAll(for tabId: UUID) {
        sessions[tabId]?.clearAll()
        sessions.removeValue(forKey: tabId)
    }

    func parkedWebView(for tabId: UUID) -> WKWebView? {
        sessions[tabId]?.parkedWebView
    }

    func untrackedWebView(for tabId: UUID) -> WKWebView? {
        sessions[tabId]?.untrackedWebView
    }

    /// Registry windowed views + session untracked/parked. Does not read Tab fields
    /// after `syncFromTabIfNeeded` has imported any missing mirror state.
    func allKnownWebViews(for tab: Tab) -> [WKWebView] {
        syncFromTabIfNeeded(tab)

        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }

        let windowWebViews = webViewRegistry.windowWebViews(for: tab.id)
        if windowWebViews.isEmpty == false {
            result.reserveCapacity(windowWebViews.count + 2)
            for webView in windowWebViews.values {
                appendUnique(webView)
            }
        } else {
            result.reserveCapacity(2)
        }

        let session = session(for: tab.id)
        appendUnique(session.untrackedWebView)
        appendUnique(session.parkedWebView)
        return result
    }

    func protectedCandidateWebViews(for tab: Tab) -> [WKWebView] {
        syncFromTabIfNeeded(tab)
        let session = session(for: tab.id)
        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }
        for webView in webViewRegistry.windowWebViews(for: tab.id).values {
            appendUnique(webView)
        }
        appendUnique(session.untrackedWebView)
        appendUnique(session.parkedWebView)
        return result
    }
}
