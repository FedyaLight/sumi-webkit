//
//  WebViewContainerDetachmentOwner.swift
//  Sumi
//
//  Owns removal of WebViews from compositor containers, deferring the
//  detachment while the WebView is protected from compositor mutation.
//

import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewContainerDetachmentOwner {
    struct Dependencies {
        let compositorContainers: @MainActor () -> [(UUID, NSView)]
        let enqueueDeferredProtectedCommand:
            @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func removeWebViewFromContainers(_ webView: WKWebView) {
        if dependencies.enqueueDeferredProtectedCommand(
            .removeWebViewFromContainers(webViewID: ObjectIdentifier(webView)),
            webView,
            "removeWebViewFromContainers"
        ) {
            return
        }

        for (_, container) in dependencies.compositorContainers() {
            removeMatchingWebView(webView, from: container)
        }
    }

    /// `WKWebView` instances live under pane views, not only as direct children of the compositor container.
    private func removeMatchingWebView(_ webView: WKWebView, from root: NSView) {
        for subview in Array(root.subviews) {
            if let host = subview as? SumiWebViewContainerView,
               host.webView === webView {
                host.removeFromSuperview()
            } else if subview === webView {
                subview.removeFromSuperview()
            } else {
                removeMatchingWebView(webView, from: subview)
            }
        }
    }
}

extension WebViewContainerDetachmentOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            compositorContainers: { [weak coordinator] in
                coordinator?.compositorContainers() ?? []
            },
            enqueueDeferredProtectedCommand: { [weak coordinator] command, webView, reason in
                coordinator?.enqueueDeferredProtectedCommand(
                    command,
                    for: webView,
                    reason: reason
                ) ?? false
            }
        )
    }
}
