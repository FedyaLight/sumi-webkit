import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    @discardableResult
    func ensureWebView(context: TabNormalWebViewRuntimeContext) -> WKWebView? {
        if !context.hasCurrentWebView {
            context.setupWebView()
        }
        return context.currentWebView()
    }

    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        context.replaceUntrackedWebView(webView)

        context.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        context.replaceUntrackedWebView(webView)

        context.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    @discardableResult
    func createAuxiliaryOverrideWebView(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        context.replaceUntrackedWebView(webView)

        context.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            enableVisitedLinkRecording: false,
            applyNavigationPreferences: false
        )

        return webView
    }

    func assignWebViewToWindow(
        _ webView: WKWebView,
        context: TabNormalWebViewRuntimeContext,
        windowId: UUID
    ) {
        context.assignPrimaryWebView(webView, windowId)
        context.ownedWebViewPreparationOwner.prepareAssignedWebView(webView)
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
            context.deferWebViewCreationUntilProfileAvailable()
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
        configurationContext.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profile.id,
            "\(reason).configuration"
        )
        prepareConfiguration?(configuration)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, context: context, reason: reason)
        return webView
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(
        context: TabNormalWebViewRuntimeContext,
        reason: String
    ) {
        context.registerNormalTabWithExtensionRuntimeIfNeeded(reason)
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext
    ) {
        context.webViewConfigurationOwner.applyWebViewConfigurationOverride(
            configuration,
            profileId: context.resolveProfile()?.id ?? context.profileId(),
            context: context.configurationContext()
        )
    }

    private func configureNormalTabWebView(
        _ webView: FocusableWKWebView,
        context: TabNormalWebViewRuntimeContext,
        reason: String
    ) {
        context.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: context.currentURL(),
            reason: reason
        )
    }

    private func normalTabWebViewConfiguration(
        context: TabNormalWebViewRuntimeContext,
        profile: Profile,
        reason: String
    ) -> WKWebViewConfiguration? {
        let currentURL = context.currentURL()
        return context.webViewConfigurationOwner.normalTabWebViewConfiguration(
            for: currentURL,
            profile: profile,
            userScriptsProvider: context.normalTabUserScriptsProvider(currentURL),
            context: context.configurationContext(),
            reloadPolicyStateOwner: context.reloadPolicyStateOwner
        )
    }

}
