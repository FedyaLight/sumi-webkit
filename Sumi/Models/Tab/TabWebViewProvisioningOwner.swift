import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    /// Constructs an auxiliary mini-window WebView. Does not install ownership —
    /// callers must install through the WebView ownership runtime or routing.
    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        preparation: TabNormalWebViewPreparationStage,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        preparation.prepareCreatedWebView(
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
        preparation: TabNormalWebViewPreparationStage,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> FocusableWKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.configuration.sumiIsNormalTabWebViewConfiguration = false
        preparation.prepareCreatedWebView(
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
        preparation: TabNormalWebViewPreparationStage,
        currentURL: URL?,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        preparation.prepareCreatedWebView(
            webView,
            currentURL,
            reason,
            .auxiliaryOverride
        )
        return webView
    }

    func prepareAssignedWebView(
        _ webView: WKWebView,
        preparation: TabNormalWebViewPreparationStage
    ) {
        preparation.prepareAssignedWebView(webView)
    }

    @discardableResult
    func makeNormalTabWebView(
        request: TabNormalWebViewSetupRequest,
        profile: Profile,
        configuration: TabNormalWebViewConfigurationStage,
        preparation: TabNormalWebViewPreparationStage,
        policyTransaction: TabConfigurationPolicyTransaction,
        reason: String,
        prepareExtensionRuntime: Bool = true,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)? = nil
    ) -> WKWebView? {
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        let configurationTrace = PerformanceTrace.beginInterval(
            "TabWebView.prepareConfiguration"
        )
        let preparedConfiguration = configuration.prepareNormalConfiguration(
            request.targetURL,
            profile,
            configuration.normalTabUserScripts(request.targetURL, profile.id)
        )
        PerformanceTrace.endInterval(
            "TabWebView.prepareConfiguration",
            configurationTrace
        )

        let webViewConfiguration = preparedConfiguration.configuration
        let extensionTrace = PerformanceTrace.beginInterval(
            "TabWebView.prepareExtensions"
        )
        configuration.prepareForExtensionRuntime(
            webViewConfiguration,
            profile.id,
            "\(reason).configuration"
        )
        prepareCandidateConfiguration?(webViewConfiguration, profile.id)
        PerformanceTrace.endInterval(
            "TabWebView.prepareExtensions",
            extensionTrace
        )
        guard webViewConfiguration.websiteDataStore === profile.dataStore else {
            RuntimeDiagnostics.emit(
                "[Tab] Rejected normal WebView during \(reason); its data store does not belong to profile \(profile.id)."
            )
            return nil
        }

        var policyState = preparedConfiguration.policyState
        policyState.websiteDataStoreIdentity = ObjectIdentifier(
            webViewConfiguration.websiteDataStore
        )
        policyState.autoplayState = SumiRuntimePermissionController
            .autoplayState(
                from: webViewConfiguration
                    .mediaTypesRequiringUserActionForPlayback
            )
        let policyTrace = PerformanceTrace.beginInterval(
            "TabWebView.preparePolicy"
        )
        let policyChange = policyTransaction.prepare(policyState)
        PerformanceTrace.endInterval(
            "TabWebView.preparePolicy",
            policyTrace
        )
        let webViewTrace = PerformanceTrace.beginInterval(
            "TabWebView.createWKWebView"
        )
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        PerformanceTrace.endInterval(
            "TabWebView.createWKWebView",
            webViewTrace
        )
        webView.sumiPreparedConfigurationPolicyChange =
            policyChange
        let preparationTrace = PerformanceTrace.beginInterval(
            "TabWebView.prepareRuntime"
        )
        configureNormalTabWebView(
            webView,
            preparation: preparation,
            currentURL: request.targetURL,
            reason: reason,
            prepareExtensionRuntime: prepareExtensionRuntime
        )
        PerformanceTrace.endInterval(
            "TabWebView.prepareRuntime",
            preparationTrace
        )
        return webView
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        profileID: UUID?,
        stage: TabNormalWebViewConfigurationStage
    ) {
        stage.applyConfigurationOverride(configuration, profileID)
    }

    private func configureNormalTabWebView(
        _ webView: FocusableWKWebView,
        preparation: TabNormalWebViewPreparationStage,
        currentURL: URL,
        reason: String,
        prepareExtensionRuntime: Bool
    ) {
        preparation.prepareCreatedWebView(
            webView,
            currentURL,
            reason,
            CreatedWebViewPreparationOptions(
                prepareExtensionRuntime: prepareExtensionRuntime
            )
        )
    }
}
