//
//  TabWebViewSession.swift
//  Sumi
//
//  Phase 6B / N5–N6: Tab WebView session outside Tab model mirror fields.
//

import Foundation
import WebKit

/// Per-tab WebView session material that is not window-registry tracked.
///
/// - `untrackedWebView`: pre-window / Glance-style ownership (`primaryWindowId == nil`)
/// - `parkedWebView`: staging for ensure reuse
/// - `primaryWindowId` + optional `primaryWebView`: windowed primary note; live
///   windowed instances are SoT in `WindowWebViewRegistry` once registered.
///   `primaryWebView` is a session hint for pre-registry / Tab-local paths.
///
/// Session `note*` APIs are the sole writers. Tab does not store WKWebView mirrors.
@MainActor
public final class TabWebViewSession {
    public let tabId: UUID
    public var untrackedWebView: WKWebView?
    public var parkedWebView: WKWebView?
    public var primaryWindowId: UUID?
    public var primaryWebView: WKWebView?

    public init(tabId: UUID) {
        self.tabId = tabId
    }

    public func clearUntracked() {
        untrackedWebView = nil
        primaryWindowId = nil
        primaryWebView = nil
    }

    public func clearParked() {
        parkedWebView = nil
    }

    public func clearAll() {
        untrackedWebView = nil
        parkedWebView = nil
        primaryWindowId = nil
        primaryWebView = nil
    }

    /// Current session-owned WebView (windowed hint or untracked), excluding parked.
    public var currentWebView: WKWebView? {
        if primaryWindowId != nil {
            return primaryWebView
        }
        return untrackedWebView
    }

    /// Copies non-nil slots from another session (used when promoting Tab-local
    /// pre-runtime notes into the coordinator store on browser-runtime attach).
    public func mergePreferringExisting(from other: TabWebViewSession) {
        if parkedWebView == nil, let parked = other.parkedWebView {
            parkedWebView = parked
        }
        if let primaryWindowId = other.primaryWindowId {
            self.primaryWindowId = primaryWindowId
            untrackedWebView = nil
            if primaryWebView == nil {
                primaryWebView = other.primaryWebView
            }
        } else if untrackedWebView == nil, let untracked = other.untrackedWebView {
            untrackedWebView = untracked
            self.primaryWindowId = nil
            primaryWebView = nil
        }
    }
}

/// Coordinator-owned store wrapping registry + parked/untracked staging.
@MainActor
public final class TabWebViewSessionStore {
    private let webViewRegistry: WindowWebViewRegistry
    private var sessions: [UUID: TabWebViewSession] = [:]

    public init(webViewRegistry: WindowWebViewRegistry) {
        self.webViewRegistry = webViewRegistry
    }

    public func session(for tabId: UUID) -> TabWebViewSession {
        if let existing = sessions[tabId] {
            return existing
        }
        let created = TabWebViewSession(tabId: tabId)
        sessions[tabId] = created
        return created
    }

    /// Absorbs Tab-local pre-runtime session notes into the coordinator store
    /// and clears the local slot (browser-runtime attach).
    public func adoptLocalSession(_ local: TabWebViewSession, for tabId: UUID) {
        let session = session(for: tabId)
        session.mergePreferringExisting(from: local)
        local.clearAll()
    }

    /// Copies Tab-local notes into the coordinator store without clearing them.
    /// Pre-runtime Tab readers still use the local session until attach.
    public func promoteLocalSessionIfNeeded(tabId: UUID, localSession: TabWebViewSession) {
        guard localSession.untrackedWebView != nil
            || localSession.parkedWebView != nil
            || localSession.primaryWindowId != nil
            || localSession.primaryWebView != nil
        else {
            return
        }
        session(for: tabId).mergePreferringExisting(from: localSession)
    }

    public func noteParkedWebView(_ webView: WKWebView?, for tabId: UUID) {
        let session = session(for: tabId)
        session.parkedWebView = webView
    }

    public func noteUntrackedWebView(_ webView: WKWebView?, for tabId: UUID) {
        let session = session(for: tabId)
        session.untrackedWebView = webView
        session.primaryWindowId = nil
        session.primaryWebView = nil
    }

    public func notePrimaryAssignment(windowId: UUID, for tabId: UUID, webView: WKWebView? = nil) {
        let session = session(for: tabId)
        session.primaryWindowId = windowId
        session.untrackedWebView = nil
        if let webView {
            session.primaryWebView = webView
        }
    }

    public func clearPrimaryAssignment(for tabId: UUID) {
        let session = session(for: tabId)
        session.primaryWindowId = nil
        session.primaryWebView = nil
    }

    public func clearAll(for tabId: UUID) {
        sessions[tabId]?.clearAll()
        sessions.removeValue(forKey: tabId)
    }

    public func parkedWebView(for tabId: UUID) -> WKWebView? {
        sessions[tabId]?.parkedWebView
    }

    public func untrackedWebView(for tabId: UUID) -> WKWebView? {
        sessions[tabId]?.untrackedWebView
    }

    public func primaryWindowId(for tabId: UUID) -> UUID? {
        sessions[tabId]?.primaryWindowId
    }

    /// Registry windowed views + session untracked/parked.
    public func allKnownWebViews(
        for tabId: UUID,
        localSession: TabWebViewSession
    ) -> [WKWebView] {
        promoteLocalSessionIfNeeded(tabId: tabId, localSession: localSession)

        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }

        let windowWebViews = webViewRegistry.windowWebViews(for: tabId)
        if windowWebViews.isEmpty == false {
            result.reserveCapacity(windowWebViews.count + 2)
            for webView in windowWebViews.values {
                appendUnique(webView)
            }
        } else {
            result.reserveCapacity(2)
        }

        let session = session(for: tabId)
        appendUnique(session.primaryWebView)
        appendUnique(session.untrackedWebView)
        appendUnique(session.parkedWebView)
        return result
    }

    public func protectedCandidateWebViews(
        for tabId: UUID,
        localSession: TabWebViewSession
    ) -> [WKWebView] {
        promoteLocalSessionIfNeeded(tabId: tabId, localSession: localSession)
        let session = session(for: tabId)
        var seen = Set<ObjectIdentifier>()
        var result: [WKWebView] = []
        func appendUnique(_ webView: WKWebView?) {
            guard let webView else { return }
            let id = ObjectIdentifier(webView)
            if seen.insert(id).inserted {
                result.append(webView)
            }
        }
        for webView in webViewRegistry.windowWebViews(for: tabId).values {
            appendUnique(webView)
        }
        appendUnique(session.primaryWebView)
        appendUnique(session.untrackedWebView)
        appendUnique(session.parkedWebView)
        return result
    }
}
