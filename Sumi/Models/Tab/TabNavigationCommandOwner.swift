import Foundation
import WebKit

@MainActor
final class TabNavigationCommandOwner {
    func loadURL(_ newURL: URL, for tab: Tab) {
        tab.url = newURL
        tab.beginLoadingPresentationIfNeeded()

        guard tab.hasCurrentWebView else {
            tab.setupWebView()
            return
        }

        let rebuiltForConfigurationPolicy = tab.rebuildNormalWebViewForConfigurationPolicyIfNeeded(
            targetURL: newURL,
            reason: "Tab.loadURL"
        )
        tab.resetPlaybackActivity()

        if newURL.isFileURL {
            loadFileURL(
                newURL,
                for: tab,
                waitForContentBlockingAssets: rebuiltForConfigurationPolicy
            )
        } else {
            loadWebURL(
                newURL,
                for: tab,
                waitForContentBlockingAssets: rebuiltForConfigurationPolicy
            )
        }

        tab.applyCachedFaviconOrPlaceholder(for: newURL)
    }

    func loadURL(_ urlString: String, for tab: Tab) {
        guard let newURL = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL, for: tab)
    }

    func navigateToURL(_ input: String, for tab: Tab) {
        let settings = tab.sumiSettings ?? tab.browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(input, queryTemplate: template)

        guard let validURL = URL(string: normalizedUrl) else {
            RuntimeDiagnostics.emit("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        loadURL(validURL, for: tab)
    }

    func refresh(_ tab: Tab) {
        guard !tab.representsSumiNativeSurface else { return }

        tab.beginLoadingPresentationIfNeeded()
        let targetURL = tab.currentWebView?.url ?? tab.url
        let protectionReloadWasRequired = tab.isProtectionReloadRequired
        let rebuiltForConfigurationPolicy = tab.rebuildNormalWebViewForConfigurationPolicyIfNeeded(
            targetURL: targetURL,
            reason: "Tab.refresh"
        )

        if protectionReloadWasRequired {
            tab.noteProtectionManualReloadResult(
                rebuiltForConfigurationPolicy: rebuiltForConfigurationPolicy,
                targetURL: targetURL
            )
        }

        if let webView = tab.currentWebView {
            if rebuiltForConfigurationPolicy {
                performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                    on: webView,
                    tab: tab,
                    waitForContentBlockingAssets: true
                ) { resolvedWebView in
                    if targetURL.isFileURL {
                        resolvedWebView.loadFileURL(
                            targetURL,
                            allowingReadAccessTo: targetURL.deletingLastPathComponent()
                        )
                    } else {
                        resolvedWebView.load(URLRequest(url: targetURL))
                    }
                }
            } else {
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            }
        }

        if !rebuiltForConfigurationPolicy {
            tab.browserManager?.reloadTabAcrossWindows(tab.id)
        }
    }

    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        tab: Tab,
        waitForContentBlockingAssets: Bool,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        guard waitForContentBlockingAssets,
              let controller = webView.configuration.userContentController.sumiNormalTabUserContentController
        else {
            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView,
                performLoad: performLoad
            )
            return
        }

        tab.navigationTransactionOwner.performAfterPreparation(
            on: webView,
            prepare: {
                await controller.waitForContentBlockingAssetsInstalled()
            },
            performLoad: performLoad
        )
    }

    nonisolated static func navigationCommandURLRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = navigationCommandCachePolicy(for: url)
        request.timeoutInterval = 30.0
        return request
    }

    nonisolated private static func navigationCommandCachePolicy(for url: URL) -> URLRequest.CachePolicy {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "webkit-extension" || scheme == "safari-web-extension" {
            return .reloadIgnoringLocalCacheData
        }
        return .returnCacheDataElseLoad
    }

    private func loadFileURL(
        _ url: URL,
        for tab: Tab,
        waitForContentBlockingAssets: Bool
    ) {
        let directoryURL = url.deletingLastPathComponent()
        if let webView = tab.currentWebView {
            performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                on: webView,
                tab: tab,
                waitForContentBlockingAssets: waitForContentBlockingAssets
            ) { resolvedWebView in
                resolvedWebView.loadFileURL(
                    url,
                    allowingReadAccessTo: directoryURL
                )
            }
        }
    }

    private func loadWebURL(
        _ url: URL,
        for tab: Tab,
        waitForContentBlockingAssets: Bool
    ) {
        let request = Self.navigationCommandURLRequest(for: url)
        if let webView = tab.currentWebView {
            performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                on: webView,
                tab: tab,
                waitForContentBlockingAssets: waitForContentBlockingAssets
            ) { resolvedWebView in
                resolvedWebView.load(request)
            }
        }
    }
}
