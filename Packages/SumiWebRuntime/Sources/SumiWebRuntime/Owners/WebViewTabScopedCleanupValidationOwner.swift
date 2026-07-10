//
//  WebViewTabScopedCleanupValidationOwner.swift
//  SumiWebRuntime
//
//  Validates deferred cleanup commands against exact repository ownership.
//

import Foundation
import WebKit

@MainActor
public struct WebViewTabScopedCleanupValidationOwner {
    public struct Context {
        public let resolveWebView: (ObjectIdentifier) -> WKWebView?
        public let residence: (WKWebView) -> WebViewResidence?

        public init(
            resolveWebView: @escaping (ObjectIdentifier) -> WKWebView?,
            residence: @escaping (WKWebView) -> WebViewResidence?
        ) {
            self.resolveWebView = resolveWebView
            self.residence = residence
        }
    }

    public init() {}

    public func canCleanUpDetachedWebView(
        with webViewID: ObjectIdentifier,
        tabID: UUID,
        context: Context
    ) -> Bool {
        guard let webView = context.resolveWebView(webViewID) else {
            return false
        }

        switch context.residence(webView) {
        case .window, .retiring, .pendingCleanup, nil:
            return false
        case .parked(let ownerTabID), .untracked(let ownerTabID):
            return ownerTabID == tabID
        }
    }

    public func canPerformFallbackCleanup(
        with webViewID: ObjectIdentifier,
        lease: WebViewPendingCleanupLease,
        context: Context
    ) -> Bool {
        guard let webView = context.resolveWebView(webViewID) else {
            return false
        }
        return context.residence(webView) == .pendingCleanup(lease)
    }
}
