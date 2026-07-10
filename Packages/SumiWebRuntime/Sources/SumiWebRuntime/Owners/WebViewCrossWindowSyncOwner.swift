//
//  WebViewCrossWindowSyncOwner.swift
//  Sumi
//
//  Owns cross-window WebView sync iteration and recursion guarding.
//

import Foundation
import WebKit

public enum WebViewSyncLoadPolicy {
    public static func shouldLoadTarget(
        desiredURL: URL,
        targetURL: URL?,
        targetHistoryURL: URL?,
        isOriginatingWebView: Bool
    ) -> Bool {
        guard !isOriginatingWebView else { return false }
        guard targetURL.map({ WebRuntimeNavigationIdentity.matches($0, desiredURL) }) != true else {
            return false
        }
        guard targetHistoryURL.map({ WebRuntimeNavigationIdentity.matches($0, desiredURL) }) != true else {
            return false
        }
        return true
    }
}

public enum ProtectedWebViewMutationDisposition: Equatable {
    case deferred
    /// Protection ended during the scheduling handoff; execute the mutation
    /// in the current main-actor turn instead of dropping it.
    case executeNow
    case rejected
}

@MainActor
public final class WebViewCrossWindowSyncOwner {
    public init() {}

    public typealias WebViewProtectionChecker = (WKWebView) -> Bool
    public typealias WebViewAction = (WKWebView) -> Void
    public typealias PendingTargetChecker = (WKWebView, URL) -> Bool
    public typealias ProtectedTargetDeferrer = (
        WKWebView
    ) -> ProtectedWebViewMutationDisposition

    private var syncingTabIds: Set<UUID> = []

    public func syncTab(
        _ tabId: UUID,
        to url: URL,
        webViews: [WKWebView],
        originatingWebView: WKWebView?,
        hasPendingTarget: PendingTargetChecker,
        isProtected: WebViewProtectionChecker,
        deferProtectedTarget: ProtectedTargetDeferrer,
        load: WebViewAction
    ) {
        guard !syncingTabIds.contains(tabId) else { return }

        syncingTabIds.insert(tabId)
        defer { syncingTabIds.remove(tabId) }

        for webView in webViews {
            let isOriginatingWebView = originatingWebView.map { $0 === webView } ?? false
            let targetHistoryURL = webView.backForwardList.currentItem?.url
            guard WebViewSyncLoadPolicy.shouldLoadTarget(
                desiredURL: url,
                targetURL: webView.url,
                targetHistoryURL: targetHistoryURL,
                isOriginatingWebView: isOriginatingWebView
            ) else {
                continue
            }
            if hasPendingTarget(webView, url) {
                continue
            }
            if isProtected(webView) {
                SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                    "deferSyncProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                switch deferProtectedTarget(webView) {
                case .deferred:
                    continue
                case .executeNow:
                    break
                case .rejected:
                    assertionFailure(
                        "A protected tracked WebView must retain its semantic navigation target"
                    )
                    continue
                }
            }

            load(webView)
        }
    }

    public func reloadTab(
        _ tabId: UUID,
        webViews: [WKWebView],
        isProtected: WebViewProtectionChecker,
        deferProtectedReload: ProtectedTargetDeferrer,
        reload: WebViewAction
    ) {
        for webView in webViews {
            if isProtected(webView) {
                SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                    "deferReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                switch deferProtectedReload(webView) {
                case .deferred:
                    continue
                case .executeNow:
                    break
                case .rejected:
                    assertionFailure(
                        "A protected tracked WebView must retain its exact semantic reload"
                    )
                    continue
                }
            }
            reload(webView)
        }
    }

    public func setMuteState(
        _ muted: Bool,
        for tabId: UUID,
        windowWebViews: [UUID: WKWebView]
    ) {
        guard windowWebViews.isEmpty == false else { return }

        for webView in windowWebViews.values {
            webView.sumiSetAudioMuted(muted)
        }
    }
}
