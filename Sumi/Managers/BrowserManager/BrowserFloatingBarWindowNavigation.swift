import Foundation
import WebKit

private enum WindowScopedConfigurationPolicyPreparation {
    case ready
    case rebuiltAndLoaded
}

@MainActor
extension BrowserManager {
    func loadWindowScopedPage(
        _ url: URL,
        tab: Tab,
        in windowState: BrowserWindowState,
        reason: String
    ) {
        guard let preparation = prepareWindowScopedConfigurationPolicy(
            for: tab,
            targetURL: url,
            in: windowState,
            reason: reason
        ) else {
            return
        }

        if preparation == .rebuiltAndLoaded {
            tab.beginLoadingPresentationIfNeeded()
            tab.resetPlaybackActivity()
            tab.applyCachedFaviconOrPlaceholder(for: url)
            return
        }

        tab.navigationCommandOwner.loadURL(
            url,
            for: tab,
            resolvedWebView: windowScopedWebViewResolver(tab: tab, in: windowState),
            reason: reason,
            rebuildConfigurationPolicy: false
        )
    }

    func refreshWindowScopedPage(
        tab: Tab,
        in windowState: BrowserWindowState,
        reason: String
    ) {
        guard !tab.representsSumiNativeSurface else { return }

        let targetWebView = windowOwnedOrCreatedWebView(for: tab, in: windowState.id)
        let targetURL = targetWebView?.url ?? tab.url
        let protectionReloadWasRequired = tab.isProtectionReloadRequired
        if tab.configurationPolicyRequiresNormalWebViewRebuild(for: targetURL) {
            guard let preparation = prepareWindowScopedConfigurationPolicy(
                for: tab,
                targetURL: targetURL,
                in: windowState,
                reason: reason
            ) else {
                return
            }
            tab.beginLoadingPresentationIfNeeded()
            if protectionReloadWasRequired {
                tab.noteProtectionManualReloadResult(
                    rebuiltForConfigurationPolicy: true,
                    targetURL: targetURL
                )
            }
            if preparation == .rebuiltAndLoaded {
                return
            }
            tab.navigationCommandOwner.loadURL(
                targetURL,
                for: tab,
                resolvedWebView: windowScopedWebViewResolver(tab: tab, in: windowState),
                reason: reason,
                rebuildConfigurationPolicy: false
            )
            return
        }

        guard targetWebView != nil else { return }
        tab.beginLoadingPresentationIfNeeded()
        if protectionReloadWasRequired {
            tab.noteProtectionManualReloadResult(
                rebuiltForConfigurationPolicy: false,
                targetURL: targetURL
            )
        }
        reloadTab(tab.id, in: windowState.id)
    }

    func loadFloatingBarCurrentPage(
        _ urlString: String,
        tab: Tab,
        in windowState: BrowserWindowState
    ) {
        guard let url = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadFloatingBarCurrentPage(url, tab: tab, in: windowState)
    }

    func navigateFloatingBarCurrentPage(
        _ input: String,
        tab: Tab,
        in windowState: BrowserWindowState
    ) {
        let template = sumiSettings?.resolvedSearchEngineTemplate
            ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(input, queryTemplate: template)

        guard let validURL = URL(string: normalizedUrl) else {
            RuntimeDiagnostics.emit("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        loadFloatingBarCurrentPage(validURL, tab: tab, in: windowState)
    }

    private func loadFloatingBarCurrentPage(
        _ url: URL,
        tab: Tab,
        in windowState: BrowserWindowState
    ) {
        loadWindowScopedPage(
            url,
            tab: tab,
            in: windowState,
            reason: "FloatingBar.currentPage"
        )
    }

    private func prepareWindowScopedConfigurationPolicy(
        for tab: Tab,
        targetURL: URL,
        in windowState: BrowserWindowState,
        reason: String
    ) -> WindowScopedConfigurationPolicyPreparation? {
        guard tab.configurationPolicyRequiresNormalWebViewRebuild(for: targetURL) else {
            return .ready
        }
        guard let webViewCoordinator else {
            RuntimeDiagnostics.emit(
                "Cannot rebuild window-scoped WebView for \(reason): coordinator unavailable."
            )
            return nil
        }
        guard webViewCoordinator.rebuildLiveWebViews(
            for: tab,
            preferredPrimaryWindowId: windowState.id,
            load: targetURL
        ) else {
            return nil
        }
        return .rebuiltAndLoaded
    }

    private func windowScopedWebViewResolver(
        tab: Tab,
        in windowState: BrowserWindowState
    ) -> TabNavigationCommandOwner.WebViewResolver {
        { [weak self, weak tab, weak windowState] in
            guard let self, let tab, let windowState else { return nil }
            return self.windowOwnedOrCreatedWebView(for: tab, in: windowState.id)
        }
    }

    private func windowOwnedOrCreatedWebView(for tab: Tab, in windowId: UUID) -> WKWebView? {
        windowOwnedWebView(for: tab, in: windowId)
            ?? webViewCoordinator?.getOrCreateWebView(for: tab, in: windowId)
    }
}
