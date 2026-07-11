import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    /// Constructs an auxiliary mini-window WebView. Does not install ownership —
    /// callers must install through the WebView ownership runtime or routing.
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
    /// callers must install through the WebView ownership runtime or routing.
    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        context: TabNormalWebViewRuntimeContext,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> FocusableWKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.configuration.sumiIsNormalTabWebViewConfiguration = false
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

    func prepareAssignedWebView(
        _ webView: WKWebView,
        context: TabNormalWebViewRuntimeContext
    ) {
        context.preparationRuntime.prepareAssignedWebView(webView)
    }

    @discardableResult
    func makeNormalTabWebView(
        context: TabNormalWebViewRuntimeContext,
        policyTransaction: TabConfigurationPolicyTransaction,
        reason: String,
        explicitProfile: Profile? = nil,
        prepareExtensionRuntime: Bool = true,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)? = nil
    ) -> WKWebView? {
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        guard let profile = explicitProfile ?? context.resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            if context.deferWebViewUntilProfileAvailable() == false {
                RuntimeDiagnostics.emit(
                    "[Tab] WebView creation cannot resume because no profile update source is attached."
                )
            }
            return nil
        }

        guard let preparedConfiguration = normalTabWebViewConfiguration(
            context: context,
            profile: profile,
            reason: reason
        ) else {
            return nil
        }

        let configuration = preparedConfiguration.configuration
        let configurationContext = context.configurationContext()
        configurationContext.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profile.id,
            "\(reason).configuration"
        )
        prepareCandidateConfiguration?(configuration, profile.id)
        guard configuration.websiteDataStore === profile.dataStore else {
            RuntimeDiagnostics.emit(
                "[Tab] Rejected normal WebView during \(reason); its data store does not belong to profile \(profile.id)."
            )
            return nil
        }

        var policyState = preparedConfiguration.policyState
        policyState.websiteDataStoreIdentity = ObjectIdentifier(
            configuration.websiteDataStore
        )
        policyState.autoplayState = SumiRuntimePermissionController
            .autoplayState(
                from: configuration
                    .mediaTypesRequiringUserActionForPlayback
            )
        let policyChange = policyTransaction.prepare(policyState)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.sumiPreparedConfigurationPolicyChange =
            policyChange
        configureNormalTabWebView(
            webView,
            context: context,
            reason: reason,
            prepareExtensionRuntime: prepareExtensionRuntime
        )
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
        reason: String,
        prepareExtensionRuntime: Bool
    ) {
        context.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            context.currentURL(),
            reason,
            CreatedWebViewPreparationOptions(
                prepareExtensionRuntime: prepareExtensionRuntime
            )
        )
    }

    private func normalTabWebViewConfiguration(
        context: TabNormalWebViewRuntimeContext,
        profile: Profile,
        reason _: String
    ) -> PreparedNormalTabWebViewConfiguration? {
        let currentURL = context.currentURL()
        return context.configurationRuntime.normalTabWebViewConfiguration(
            currentURL,
            profile,
            context.normalTabUserScriptsProvider(currentURL, profile.id),
            context.configurationContext()
        )
    }
}
