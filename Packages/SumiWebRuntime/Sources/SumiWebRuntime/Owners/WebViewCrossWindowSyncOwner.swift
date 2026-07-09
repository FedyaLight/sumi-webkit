//
//  WebViewCrossWindowSyncOwner.swift
//  Sumi
//
//  Owns cross-window WebView sync iteration and recursion guarding.
//

import Foundation
import WebKit

enum WebViewSyncLoadPolicy {
    static func shouldLoadTarget(
        desiredURL: URL,
        targetURL: URL?,
        targetHistoryURL: URL?,
        isOriginatingWebView: Bool
    ) -> Bool {
        guard !isOriginatingWebView else { return false }
        guard targetURL != desiredURL else { return false }
        guard targetHistoryURL != desiredURL else { return false }
        return true
    }
}

@MainActor
final class WebViewCrossWindowSyncOwner {
    typealias WebViewProtectionChecker = (WKWebView) -> Bool
    typealias WebViewAction = (WKWebView) -> Void

    private var syncingTabIds: Set<UUID> = []

    func syncTab(
        _ tabId: UUID,
        to url: URL,
        webViews: [WKWebView],
        originatingWebView: WKWebView?,
        isProtected: WebViewProtectionChecker,
        load: WebViewAction
    ) {
        guard !syncingTabIds.contains(tabId) else { return }

        syncingTabIds.insert(tabId)
        defer { syncingTabIds.remove(tabId) }

        for webView in webViews {
            if isProtected(webView) {
                RuntimeDiagnostics.protectedWebViewTrace(
                    "skipSyncProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                continue
            }
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

            load(webView)
        }
    }

    func reloadTab(
        _ tabId: UUID,
        webViews: [WKWebView],
        isProtected: WebViewProtectionChecker,
        reload: WebViewAction
    ) {
        for webView in webViews {
            if isProtected(webView) {
                RuntimeDiagnostics.protectedWebViewTrace(
                    "skipReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tabId.uuidString.prefix(8))"
                )
                continue
            }
            reload(webView)
        }
    }

    func setMuteState(
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
