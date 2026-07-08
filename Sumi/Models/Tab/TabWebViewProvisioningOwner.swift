import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    /// Constructs an auxiliary mini-window WebView. Does not install ownership —
    /// callers must install via WebViewCoordinator / routing.
    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        context.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            currentURL,
            reason,
            .auxiliary(prepareExtensionRuntime: isExtensionOriginated)
        )
        return webView
    }

    /// Constructs a popup WebView. Does not install ownership —
    /// callers must install via WebViewCoordinator / routing.
    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        context.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            currentURL,
            reason,
            .auxiliary(prepareExtensionRuntime: isExtensionOriginated)
        )
        return webView
    }

    /// Constructs an auxiliary-override WebView. Does not install ownership —
    /// the untracked ensure path installs after construction.
    @discardableResult
    func createAuxiliaryOverrideWebView(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        context.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            currentURL,
            reason,
            .auxiliaryOverride
        )
        return webView
    }

    func assignWebViewToWindow(
        _ webView: WKWebView,
        context: TabNormalWebViewRuntimeContext,
        windowId: UUID
    ) {
        context.assignPrimaryWebView(webView, windowId)
        context.preparationRuntime.prepareAssignedWebView(webView)
    }

    @discardableResult
    func makeNormalTabWebView(
        context: TabNormalWebViewRuntimeContext,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        guard let profile = context.resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            context.deferWebViewUntilProfileAvailable()
            return nil
        }

        guard let configuration = normalTabWebViewConfiguration(
            context: context,
            profile: profile,
            reason: reason
        ) else {
            return nil
        }

        let configurationContext = context.configurationContext()
        configurationContext.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profile.id,
            "\(reason).configuration"
        )
        prepareConfiguration?(configuration)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, context: context, reason: reason)
        return webView
    }

    func registerTabWithExtensionRuntimeIfNeeded(
        context: TabNormalWebViewRuntimeContext,
        reason: String
    ) {
        context.registerTabWithExtensionRuntimeIfNeeded(reason)
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext
    ) {
        context.configurationRuntime.applyWebViewConfigurationOverride(
            configuration,
            context.resolveProfile()?.id ?? context.profileId(),
            context.configurationContext()
        )
    }

    private func configureNormalTabWebView(
        _ webView: FocusableWKWebView,
        context: TabNormalWebViewRuntimeContext,
        reason: String
    ) {
        context.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            context.currentURL(),
            reason,
            .normal
        )
    }

    private func normalTabWebViewConfiguration(
        context: TabNormalWebViewRuntimeContext,
        profile: Profile,
        reason _: String
    ) -> WKWebViewConfiguration? {
        let currentURL = context.currentURL()
        return context.configurationRuntime.normalTabWebViewConfiguration(
            currentURL,
            profile,
            context.normalTabUserScriptsProvider(currentURL),
            context.configurationContext()
        )
    }
}
