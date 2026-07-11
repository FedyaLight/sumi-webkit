import Foundation
import WebKit
import SumiWebRuntime

@MainActor
enum TabUntrackedWebViewEnsureOutcome {
    case available(WKWebView)
    case deferred
    case failed

    var webView: WKWebView? {
        guard case .available(let webView) = self else { return nil }
        return webView
    }
}

@MainActor
final class TabNormalWebViewSetupOwner {
    /// Single create-policy path for pre-window / untracked normal-tab WebViews.
    /// Order: profile defer → parked reuse → aux override → factory+replace → registration/handoff.
    @discardableResult
    func ensureUntrackedNormalWebView(
        context: TabNormalWebViewRuntimeContext,
        policyTransaction: TabConfigurationPolicyTransaction,
        provisioningOwner: TabWebViewProvisioningOwner,
        reason: String
    ) -> TabUntrackedWebViewEnsureOutcome {
        if let currentWebView = context.currentWebView() {
            return .available(currentWebView)
        }

        context.beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = context.parkedWebView()
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false
        var didCreateNormalWebView = false

        guard let profile = context.resolveProfile() else {
            return context.deferWebViewUntilProfileAvailable()
                ? .deferred
                : .failed
        }

        let configurationContext = context.configurationContext()
        let auxiliaryOverrideConfiguration = context.configurationRuntime.auxiliaryOverrideConfiguration(
            profile,
            configurationContext
        )

        if let existingWebView = reusableExistingWebView {
            if canReuseAsNormalTabWebView(existingWebView, context: context) {
                context.adoptParkedWebViewAsCurrent(existingWebView)
                didReuseExistingWebView = true
                let replaceNormalTabUserScripts = context.replaceNormalTabUserScripts
                let currentURL = context.currentURL
                Task { @MainActor [weak existingWebView] in
                    guard let existingWebView else { return }
                    await replaceNormalTabUserScripts(
                        existingWebView.configuration.userContentController,
                        currentURL()
                    )
                }
            } else {
                if context.retireParkedWebView(
                    existingWebView,
                    "\(reason).discardIncompatibleParkedWebView"
                ) == false {
                    context.cleanupCloneWebView(existingWebView)
                    context.clearParkedExistingWebView()
                }
            }
        }

        if !context.hasCurrentWebView {
            if context.deferWebsiteDataMutationWebViewMaterialization(
                context.setupWebView
            ) {
                return .deferred
            }
            if let auxiliaryOverrideConfiguration {
                configurationContext.prepareWebViewConfigForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "\(reason).configuration"
                )
                let overrideWebView = provisioningOwner.createAuxiliaryOverrideWebView(
                    auxiliaryOverrideConfiguration,
                    context: context,
                    currentURL: context.currentURL(),
                    reason: reason
                )
                context.replaceUntrackedWebView(overrideWebView)
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = provisioningOwner.makeNormalTabWebView(
                context: context,
                policyTransaction: policyTransaction,
                reason: reason
            ) {
                guard let policyAdmission = policyTransaction
                    .preparePlacementAdmission(
                    [normalWebView],
                    as: .canonicalGeneration
                ) else {
                    context.cleanupCloneWebView(normalWebView)
                    return .failed
                }
                context.replaceUntrackedWebView(normalWebView)
                precondition(
                    context.currentWebView() === normalWebView,
                    "A normal WebView must be canonical before policy commit"
                )
                precondition(
                    policyTransaction.commit(policyAdmission),
                    "Canonical normal WebView policy receipt must commit once"
                )
                didCreateNormalWebView = true
            }
        }

        if let webView = context.currentWebView() {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                context.preparationRuntime.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = context.currentWebView() {
            context.preparationRuntime.applyOwnedWebViewNavPreferences(webView)
        }

        let shouldDelayInitialTabRuntimeRegistration =
            shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: context.isPopupHost(),
                hasExistingWebView: context.hasParkedWebView,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: context.currentURL()
            )

        if shouldDelayInitialTabRuntimeRegistration == false {
            provisioningOwner.registerTabWithExtensionRuntimeIfNeeded(
                context: context,
                reason: reason
            )
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(context.currentURL()),
           let webView = context.currentWebView() {
            loadExtensionOwnedInitialURL(context.currentURL(), on: webView, context: context)
            context.finishSuspendedRestoreIfNeeded()
            return .available(webView)
        }

        if didCreateNormalWebView && context.isPopupHost() == false {
            let initialWebView = context.currentWebView()
            context.scheduleInitialDocumentRuntimeHandoff(
                initialWebView,
                context.currentURL(),
                profile.id,
                "\(reason).beforeInitialLoad"
            )
        }

        context.finishSuspendedRestoreIfNeeded()
        guard let currentWebView = context.currentWebView() else {
            return .failed
        }
        return .available(currentWebView)
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

    private func loadExtensionOwnedInitialURL(
        _ targetURL: URL,
        on webView: WKWebView,
        context: TabNormalWebViewRuntimeContext
    ) {
        context.loadMainFrameRequest(
            webView,
            WebRuntimeNavigationRequestFactory.navigationRequest(for: targetURL)
        )
        context.applyCachedFaviconOrPlaceholder(targetURL)
    }

    private func canReuseAsNormalTabWebView(
        _ webView: WKWebView,
        context: TabNormalWebViewRuntimeContext
    ) -> Bool {
        context.configurationRuntime.canReuseAsNormalTabWebView(
            webView,
            context.currentURL(),
            context.resolveProfile(),
            context.configurationContext()
        )
    }
}
