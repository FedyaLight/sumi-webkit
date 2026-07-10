//
//  WebViewSessionHandle.swift
//  SumiWebRuntime
//
//  Tab-scoped view of canonical WebView placement.
//

import Foundation
import WebKit

@preconcurrency @MainActor
public final class WebViewSessionHandle {
    public let tabID: UUID
    private let repository: WebViewSessionRepository

    public init(tabID: UUID) {
        self.tabID = tabID
        repository = WebViewSessionRepository()
    }

    public init(tabID: UUID, repository: WebViewSessionRepository) {
        self.tabID = tabID
        self.repository = repository
    }

    public func requireBacking(by candidate: WebViewSessionRepository) {
        precondition(
            repository === candidate,
            "Tab and browser runtime must share one WebView session repository"
        )
    }

    public func isBacked(by candidate: WebViewSessionRepository) -> Bool {
        repository === candidate
    }

    public var generation: UInt64 {
        repository.queries.generation(for: tabID)
    }
    public var currentWebView: WKWebView? {
        repository.queries.currentWebView(for: tabID)
    }
    public var untrackedWebView: WKWebView? {
        repository.queries.untrackedWebView(for: tabID)
    }
    public var parkedWebView: WKWebView? {
        repository.queries.parkedWebView(for: tabID)
    }
    public var primaryWindowID: UUID? {
        repository.queries.primaryWindowID(for: tabID)
    }
    public var primaryWebView: WKWebView? {
        repository.queries.primaryWebView(for: tabID)
    }
    public var isUnloaded: Bool { currentWebView == nil }
    public var allKnownWebViews: [WKWebView] {
        repository.queries.allKnownWebViews(for: tabID)
    }
    public var runtimeOwnedWebViews: [WKWebView] {
        repository.queries.runtimeOwnedWebViews(for: tabID)
    }

    public func residence(of webView: WKWebView) -> WebViewResidence? {
        repository.queries.residence(of: webView)
    }

    public func park(_ webView: WKWebView?) {
        repository.placement.noteParkedWebView(webView, for: tabID)
    }

    public func clearParked() {
        park(nil)
    }

    @discardableResult
    public func adoptParkedAsUntracked(_ webView: WKWebView) -> Bool {
        repository.placement.adoptParkedWebViewAsUntracked(
            webView,
            for: tabID
        )
    }

    public func replaceUntracked(with webView: WKWebView) {
        repository.placement.noteUntrackedWebView(webView, for: tabID)
    }

    public func clearUntracked() {
        repository.placement.noteUntrackedWebView(nil, for: tabID)
    }

    public func releaseUntrackedAndBeginPendingCleanup(
        _ expectedCurrent: WKWebView
    ) -> WebViewPendingCleanupLease? {
        repository.releaseUntrackedAndBeginPendingCleanup(
            expectedCurrent,
            for: tabID
        )
    }

    public func releaseParkedAndBeginPendingCleanup(
        _ expectedCurrent: WKWebView
    ) -> WebViewPendingCleanupLease? {
        repository.releaseParkedAndBeginPendingCleanup(
            expectedCurrent,
            for: tabID
        )
    }

    public func clearDetachedOwnership() {
        repository.placement.clearDetachedWebViews(for: tabID)
    }

    @discardableResult
    public func clearUntracked(ifIdenticalTo webView: WKWebView) -> Bool {
        guard untrackedWebView === webView else { return false }
        clearUntracked()
        return true
    }

    public func owns(_ webView: WKWebView) -> Bool {
        switch repository.queries.residence(of: webView) {
        case .parked(let ownerTabID), .untracked(let ownerTabID):
            return ownerTabID == tabID
        case .window(let owner):
            return owner.tabID == tabID
        case .retiring, .pendingCleanup:
            return false
        case nil:
            return false
        }
    }
}
