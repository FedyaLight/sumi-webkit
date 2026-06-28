//
//  WebViewTrackingLifecycleOwner.swift
//  Sumi
//
//  Owns tracked WebView slot attachment and detachment mechanics.
//

import Foundation
import WebKit

@MainActor
final class WebViewTrackingLifecycleOwner {
    typealias ContainerRemoval = (WKWebView) -> Void
    typealias RuntimeObservationInstaller = (WKWebView) -> Void
    typealias RuntimeObservationUninstaller = (WKWebView) -> Void
    typealias DeferredCommandPruner = (String) -> Void

    func registerTrackedWebView(
        _ webView: WKWebView,
        for owner: TrackedWebViewOwner,
        in webViewRegistry: WindowWebViewRegistry,
        removeFromContainers: ContainerRemoval,
        installRuntimeObservations: RuntimeObservationInstaller,
        uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller,
        pruneInvalidDeferredCommands: DeferredCommandPruner
    ) {
        if let existingOwner = webViewRegistry.indexedOwner(containing: webView),
           existingOwner != owner
        {
            _ = unregisterTrackedWebViewSlot(
                owner: existingOwner,
                expectedWebView: webView,
                removeFromSuperview: true,
                in: webViewRegistry,
                removeFromContainers: removeFromContainers,
                uninstallRuntimeObservationsIfUntracked: uninstallRuntimeObservationsIfUntracked,
                pruneInvalidDeferredCommands: pruneInvalidDeferredCommands
            )
        }

        if let existingWebView = webViewRegistry.webView(for: owner),
           existingWebView !== webView
        {
            _ = unregisterTrackedWebViewSlot(
                owner: owner,
                expectedWebView: existingWebView,
                removeFromSuperview: true,
                removeRecentVisibility: false,
                in: webViewRegistry,
                removeFromContainers: removeFromContainers,
                uninstallRuntimeObservationsIfUntracked: uninstallRuntimeObservationsIfUntracked,
                pruneInvalidDeferredCommands: pruneInvalidDeferredCommands
            )
        }

        webViewRegistry.setWebView(webView, for: owner)
        installRuntimeObservations(webView)
        webViewRegistry.assertTrackingConsistency("registerTrackedWebView")
    }

    @discardableResult
    func unregisterTrackedWebViewSlot(
        owner: TrackedWebViewOwner,
        expectedWebView: WKWebView? = nil,
        removeFromSuperview: Bool = false,
        removeRecentVisibility: Bool = true,
        in webViewRegistry: WindowWebViewRegistry,
        removeFromContainers: ContainerRemoval,
        uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller,
        pruneInvalidDeferredCommands: DeferredCommandPruner
    ) -> WKWebView? {
        let trackedWebView = webViewRegistry.webView(for: owner)
        if let expectedWebView,
           let trackedWebView,
           trackedWebView !== expectedWebView
        {
            webViewRegistry.removeReverseIndex(for: expectedWebView, ifOwnedBy: owner)
            return nil
        }

        let resolvedWebView = trackedWebView ?? expectedWebView

        if removeFromSuperview,
           let resolvedWebView
        {
            removeFromContainers(resolvedWebView)
        }

        webViewRegistry.removeWebView(
            owner: owner,
            resolvedWebView: resolvedWebView,
            removeRecentVisibility: removeRecentVisibility
        )
        if let resolvedWebView {
            uninstallRuntimeObservationsIfUntracked(resolvedWebView)
        }
        pruneInvalidDeferredCommands("unregisterTrackedWebViewSlot")
        webViewRegistry.assertTrackingConsistency("unregisterTrackedWebViewSlot")
        return resolvedWebView
    }
}
