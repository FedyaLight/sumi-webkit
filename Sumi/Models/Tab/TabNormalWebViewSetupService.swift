import Foundation
import SumiWebRuntime
import WebKit

@MainActor
enum TabUntrackedWebViewEnsureOutcome {
    case available(WKWebView)
    case superseded(WKWebView)
    case deferred
    case failed

    var webView: WKWebView? {
        switch self {
        case .available(let webView), .superseded(let webView):
            return webView
        case .deferred, .failed:
            return nil
        }
    }
}

@MainActor
final class TabNormalWebViewSetupService {
    private weak var tab: Tab?
    private var installation: (any UntrackedWebViewInstalling)?

    func attach(
        to tab: Tab,
        installation: (any UntrackedWebViewInstalling)?
    ) {
        precondition(self.tab == nil || self.tab === tab)
        self.tab = tab
        self.installation = installation
    }

    /// Single create-policy path for pre-window / untracked normal-tab WebViews.
    /// Order: profile defer → parked reuse → aux override → factory+replace → registration/handoff.
    @discardableResult
    func ensureUntrackedNormalWebView(
        request: TabNormalWebViewSetupRequest,
        admission: TabNormalWebViewCreationAdmissionStage,
        residence: TabNormalWebViewResidenceStage,
        configuration: TabNormalWebViewConfigurationStage,
        preparation: TabNormalWebViewPreparationStage,
        initialDocument: TabNormalWebViewInitialDocumentStage,
        policyTransaction: TabConfigurationPolicyTransaction,
        provisioningOwner: TabWebViewProvisioningOwner,
        reason: String,
        registerTabWithExtensionRuntime: Bool = true
    ) -> TabUntrackedWebViewEnsureOutcome {
        guard let tab else { return .failed }
        precondition(
            request.tabID == tab.id,
            "Normal WebView setup request must describe the bound Tab"
        )
        if let currentWebView = residence.currentWebView() {
            return .available(currentWebView)
        }

        admission.beginSuspendedRestore()
        let reusableExistingWebView = residence.parkedWebView()
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false
        var didCreateNormalWebView = false

        guard let profile = request.resolvedProfile else {
            return admission.deferUntilProfileAvailable()
                ? .deferred
                : .failed
        }

        let auxiliaryOverrideConfiguration = configuration
            .auxiliaryOverrideConfiguration(profile)

        if let existingWebView = reusableExistingWebView {
            if configuration.canReuse(
                existingWebView,
                request.targetURL,
                profile
            ) {
                guard install(
                    existingWebView,
                    for: tab,
                    using: installation,
                    residence: residence
                ) else {
                    return .failed
                }
                didReuseExistingWebView = true
                let replaceNormalTabUserScripts = initialDocument.replaceNormalTabUserScripts
                let targetURL = request.targetURL
                Task { @MainActor [weak existingWebView] in
                    guard let existingWebView else { return }
                    await replaceNormalTabUserScripts(
                        existingWebView.configuration.userContentController,
                        targetURL
                    )
                }
            } else {
                if residence.retireParkedWebView(
                    existingWebView,
                    "\(reason).discardIncompatibleParkedWebView"
                ) == false {
                    residence.cleanupRejectedWebView(existingWebView)
                    residence.clearParkedWebView()
                }
            }
        }

        if !residence.hasCurrentWebView {
            let replaySetup = admission.replaySetup
            if admission.deferMaterialization(
                { replaySetup(registerTabWithExtensionRuntime) }
            ) {
                return .deferred
            }
            if let auxiliaryOverrideConfiguration {
                configuration.prepareForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "\(reason).configuration"
                )
                let overrideWebView = provisioningOwner.createAuxiliaryOverrideWebView(
                    auxiliaryOverrideConfiguration,
                    preparation: preparation,
                    currentURL: request.targetURL,
                    reason: reason
                )
                guard install(
                    overrideWebView,
                    for: tab,
                    using: installation,
                    residence: residence
                ) else {
                    return .failed
                }
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = provisioningOwner.makeNormalTabWebView(
                request: request,
                profile: profile,
                configuration: configuration,
                preparation: preparation,
                policyTransaction: policyTransaction,
                reason: reason
            ) {
                guard install(
                    normalWebView,
                    for: tab,
                    using: installation,
                    residence: residence
                ) else {
                    return .failed
                }
                didCreateNormalWebView = true
            }
        }

        if let webView = residence.currentWebView() {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                preparation.prepareReusedWebView(webView)
            }
        }

        if let webView = residence.currentWebView() {
            preparation.applyNavigationPreferences(webView)
        }

        let shouldDelayInitialTabRuntimeRegistration =
            shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: request.isPopupHost,
                hasExistingWebView: residence.hasParkedWebView,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: request.targetURL
            )

        guard let committedWebView = residence.currentWebView() else {
            return .failed
        }

        if registerTabWithExtensionRuntime,
           shouldDelayInitialTabRuntimeRegistration == false {
            initialDocument.registerExtensionRuntime(reason)
        }

        guard residence.currentWebView() === committedWebView else {
            return supersededOutcome(
                admission: admission,
                residence: residence
            )
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionURLIdentity.isOwned(request.targetURL),
           residence.currentWebView() === committedWebView {
            initialDocument.loadExtensionOwnedInitialURL(
                committedWebView,
                request.targetURL
            )
            admission.finishSuspendedRestore()
            return .available(committedWebView)
        }

        if didCreateNormalWebView && request.isPopupHost == false {
            initialDocument.scheduleRuntimeHandoff(
                committedWebView,
                request.targetURL,
                profile.id,
                "\(reason).beforeInitialLoad"
            )
        }

        admission.finishSuspendedRestore()
        guard let currentWebView = residence.currentWebView() else {
            return .failed
        }
        guard currentWebView === committedWebView else {
            return .superseded(currentWebView)
        }
        return .available(currentWebView)
    }

    private func supersededOutcome(
        admission: TabNormalWebViewCreationAdmissionStage,
        residence: TabNormalWebViewResidenceStage
    ) -> TabUntrackedWebViewEnsureOutcome {
        admission.finishSuspendedRestore()
        guard let currentWebView = residence.currentWebView() else {
            return .failed
        }
        return .superseded(currentWebView)
    }

    private func install(
        _ webView: WKWebView,
        for tab: Tab,
        using installation: (any UntrackedWebViewInstalling)?,
        residence: TabNormalWebViewResidenceStage
    ) -> Bool {
        guard let installation else {
            if residence.currentWebView() !== webView,
               residence.parkedWebView() !== webView {
                residence.cleanupRejectedWebView(webView)
            }
            return false
        }
        let outcome = installation.installUntracked(webView, for: tab)
        guard outcome.isAccepted else {
            if outcome.callerRetainsWebView {
                residence.cleanupRejectedWebView(webView)
            }
            return false
        }
        return residence.currentWebView() === webView
    }

    func shouldDelayInitialTabRuntimeRegistration(
        isPopupHost: Bool,
        hasExistingWebView: Bool,
        didCreateAuxiliaryOverrideWebView: Bool,
        url: URL
    ) -> Bool {
        !isPopupHost
            && !hasExistingWebView
            && !didCreateAuxiliaryOverrideWebView
            && Self.isInitialDocumentExtensionWarmupURL(url)
    }

    static func isInitialDocumentExtensionWarmupURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
