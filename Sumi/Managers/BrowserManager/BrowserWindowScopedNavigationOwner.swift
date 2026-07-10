import Foundation
import WebKit
import SumiDomain
import SumiWebRuntime

/// Loads and reloads pages in window-scoped WebViews, rebuilding configuration
/// policy when the destination requires it (floating bar and privacy flows).
@MainActor
final class BrowserWindowScopedNavigationOwner {
    private let webViewCoordinator: @MainActor () -> WebViewCoordinator?
    private let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
    private let materializeWebView: @MainActor (Tab, UUID) -> WKWebView?
    private let reloadTab: @MainActor (
        UUID,
        UUID,
        TabMainFrameNavigationIntent,
        WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome
    private let resolvedSearchEngineTemplate: @MainActor () -> String?

    init(
        webViewCoordinator: @escaping @MainActor () -> WebViewCoordinator?,
        windowOwnedWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?,
        materializeWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?,
        reloadTab: @escaping @MainActor (
            UUID,
            UUID,
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> TabMainFrameReloadCommandOutcome,
        resolvedSearchEngineTemplate: @escaping @MainActor () -> String?
    ) {
        self.webViewCoordinator = webViewCoordinator
        self.windowOwnedWebView = windowOwnedWebView
        self.materializeWebView = materializeWebView
        self.reloadTab = reloadTab
        self.resolvedSearchEngineTemplate = resolvedSearchEngineTemplate
    }

    func loadWindowScopedPage(
        _ url: URL,
        tab: Tab,
        in windowState: BrowserWindowState,
        reason: String
    ) {
        tab.navigationCommandOwner.loadURL(
            url,
            for: tab,
            resolvedWebView: windowScopedWebViewResolver(tab: tab, in: windowState),
            reason: reason,
            configurationPolicyRebuilder: { [weak self, weak tab, weak windowState] targetURL, reason in
                guard let self, let tab, let windowState else { return .failed }
                return self.rebuildWindowScopedConfigurationPolicy(
                    for: tab,
                    targetURL: targetURL,
                    in: windowState,
                    reason: reason
                )
            }
        )
    }

    @discardableResult
    func refreshWindowScopedPage(
        tab: Tab,
        in windowState: BrowserWindowState,
        reason: String,
        policy: WebRuntimeMainFrameReloadPolicy = .standard
    ) -> TabMainFrameReloadCommandOutcome {
        tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: windowScopedWebViewResolver(tab: tab, in: windowState),
            reason: reason,
            policy: policy,
            configurationPolicyRebuilder: { [weak self, weak tab, weak windowState] targetURL, reason in
                guard let self, let tab, let windowState else { return .failed }
                return self.rebuildWindowScopedConfigurationPolicy(
                    for: tab,
                    targetURL: targetURL,
                    in: windowState,
                    reason: reason
                )
            },
            deliverTrackedReload: { [weak self, weak tab, weak windowState] intent, policy in
                guard let self, let tab, let windowState else { return .failed }
                return self.reloadTab(
                    tab.id,
                    windowState.id,
                    intent,
                    policy
                )
            }
        )
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
        let template = resolvedSearchEngineTemplate()
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

    private func rebuildWindowScopedConfigurationPolicy(
        for tab: Tab,
        targetURL: URL,
        in windowState: BrowserWindowState,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard tab.configurationPolicyRequiresNormalWebViewRebuild(for: targetURL) else {
            return .notNeeded
        }
        guard let webViewCoordinator = webViewCoordinator() else {
            RuntimeDiagnostics.emit(
                "Cannot rebuild window-scoped WebView for \(reason): coordinator unavailable."
            )
            return .failed
        }
        let rebuildResult = webViewCoordinator.rebuildService
            .rebuildLiveWebViewsResult(
            for: tab,
            preferredPrimaryWindowID: windowState.id,
            load: targetURL,
            reason: reason,
            intentRevision: tab.currentWebViewRebuildIntentRevision,
            rebuildKind: .semanticNavigation
        )
        switch rebuildResult {
        case .committed:
            return .replacedAndScheduledNavigation
        case .deferred:
            return .deferred
        case .noLiveWindows, .failed:
            return .failed
        }
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
        windowOwnedWebView(tab, windowId)
            ?? materializeWebView(tab, windowId)
    }
}
