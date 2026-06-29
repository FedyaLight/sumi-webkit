import Foundation
import WebKit

@MainActor
final class TabOwnedWebViewPreparationOwner {
    struct Dependencies {
        let tab: @MainActor () -> Tab?
        let browserManager: @MainActor () -> BrowserManager?
        let visitedLinkStore: @MainActor () -> (any BrowserVisitedLinkStoreManaging)?
        let installNavigationDelegate: @MainActor (WKWebView) -> Void
        let setupNavigationStateObservers: @MainActor (WKWebView) -> Void
        let bindAudioState: @MainActor (WKWebView) -> Void
        let applyRestoredNavigationState: @MainActor () -> Void
        let ensureFaviconsTabExtension: @MainActor (SumiFaviconUserScripts) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func prepareCreatedFocusableWebView(
        _ webView: FocusableWKWebView,
        currentURL: URL?,
        reason: String,
        enableVisitedLinkRecording: Bool = true,
        applyNavigationPreferences: Bool = true,
        installFaviconRuntime: Bool = true,
        prepareExtensionRuntime: Bool = true
    ) {
        applyOwnedTabWebViewNavigationSetup(to: webView)
        applyOwnedTabWebViewOwnershipBaseline(to: webView)
        if applyNavigationPreferences {
            applyOwnedTabWebViewNavigationPreferences(to: webView)
        }
        if enableVisitedLinkRecording {
            dependencies.visitedLinkStore()?.enableVisitedLinkRecording(on: webView)
        }
        installRuntimeObservers(on: webView)
        if installFaviconRuntime {
            installFaviconRuntimeIfAvailable(on: webView)
        }
        prepareWebViewForExtensionRuntimeIfNeeded(
            webView,
            currentURL: currentURL,
            reason: reason,
            shouldPrepare: prepareExtensionRuntime
        )
    }

    func prepareReusedOrExternallyCreatedWebView(_ webView: WKWebView) {
        dependencies.visitedLinkStore()?.enableVisitedLinkRecording(on: webView)
        applyOwnedTabWebViewNavigationSetup(to: webView)
        installRuntimeObservers(on: webView)
        installFaviconRuntimeIfAvailable(on: webView)
    }

    func prepareAssignedWebView(_ webView: WKWebView) {
        dependencies.installNavigationDelegate(webView)
        installRuntimeObservers(on: webView)
    }

    func installRuntimeObservers(on webView: WKWebView) {
        dependencies.setupNavigationStateObservers(webView)
        dependencies.bindAudioState(webView)
        dependencies.applyRestoredNavigationState()
    }

    func applyOwnedTabWebViewNavigationPreferences(to webView: WKWebView) {
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }

        webView.allowsLinkPreview = true
        webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    }

    private func applyOwnedTabWebViewNavigationSetup(to webView: WKWebView) {
        dependencies.installNavigationDelegate(webView)
        webView.uiDelegate = dependencies.tab()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
    }

    private func applyOwnedTabWebViewOwnershipBaseline(to webView: FocusableWKWebView) {
        webView.setValue(true, forKey: "drawsBackground")
        webView.owningTab = dependencies.tab()
        SumiUserAgent.apply(to: webView)
    }

    private func installFaviconRuntimeIfAvailable(on webView: WKWebView) {
        guard let scriptsProvider = webView
            .configuration
            .userContentController
            .sumiNormalTabUserScriptsProvider?
            .faviconScripts
        else { return }

        dependencies.ensureFaviconsTabExtension(scriptsProvider)
    }

    private func prepareWebViewForExtensionRuntimeIfNeeded(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String,
        shouldPrepare: Bool
    ) {
        guard shouldPrepare else { return }
        dependencies.browserManager()?.extensionsModule.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: currentURL,
            reason: reason
        )
    }
}

extension TabOwnedWebViewPreparationOwner.Dependencies {
    @MainActor
    static func live(tab: Tab) -> Self {
        Self(
            tab: { [weak tab] in tab },
            browserManager: { [weak tab] in tab?.browserManager },
            visitedLinkStore: { [weak tab] in tab?.visitedLinkStore },
            installNavigationDelegate: { [weak tab] webView in
                tab?.installNavigationDelegate(on: webView)
            },
            setupNavigationStateObservers: { [weak tab] webView in
                tab?.setupNavigationStateObservers(for: webView)
            },
            bindAudioState: { [weak tab] webView in
                tab?.bindAudioState(to: webView)
            },
            applyRestoredNavigationState: { [weak tab] in
                tab?.applyRestoredNavigationState()
            },
            ensureFaviconsTabExtension: { [weak tab] scriptsProvider in
                tab?.ensureFaviconsTabExtension(using: scriptsProvider)
            }
        )
    }
}
