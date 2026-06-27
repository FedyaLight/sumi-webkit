//
//  WebViewDestructiveCleanupPreparationOwner.swift
//  Sumi
//
//  Owns destructive browsing-data cleanup preparation for live WebViews.
//

import Foundation
import WebKit

@MainActor
final class WebViewDestructiveCleanupPreparationOwner {
    private var blankingWebViewIDs: Set<ObjectIdentifier> = []

    func beginNavigationSuppression(on webView: WKWebView) {
        blankingWebViewIDs.insert(ObjectIdentifier(webView))
    }

    func isSuppressingNavigation(on webView: WKWebView) -> Bool {
        blankingWebViewIDs.contains(ObjectIdentifier(webView))
    }

    func finishNavigationSuppression(on webView: WKWebView) {
        blankingWebViewIDs.remove(ObjectIdentifier(webView))
    }

    func finishNavigationSuppression(webViewID: ObjectIdentifier) {
        blankingWebViewIDs.remove(webViewID)
    }

    func prepare(_ webView: WKWebView, tab: Tab) {
        tab.stopLoading(on: webView)
        webView.pauseAllMediaPlayback(completionHandler: nil)

        if webView.cameraCaptureState != .none {
            webView.setCameraCaptureState(.none, completionHandler: nil)
        }
        if webView.microphoneCaptureState != .none {
            webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        }

        guard webView.url?.absoluteString != SumiSurface.emptyTabURL.absoluteString else {
            finishNavigationSuppression(on: webView)
            return
        }

        beginNavigationSuppression(on: webView)
        if webView.load(URLRequest(url: SumiSurface.emptyTabURL)) == nil {
            finishNavigationSuppression(on: webView)
        }
    }
}
