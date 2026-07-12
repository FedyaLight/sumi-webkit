import Foundation
import WebKit
import SumiWebRuntime

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
        context: TabNormalWebViewRuntimeContext,
        policyTransaction: TabConfigurationPolicyTransaction,
        provisioningOwner: TabWebViewProvisioningOwner,
        reason: String,
        registerTabWithExtensionRuntime: Bool = true
    ) -> TabUntrackedWebViewEnsureOutcome {
        guard let tab else { return .failed }
        precondition(
            context.tabId == tab.id,
            "Normal WebView setup context must describe the bound Tab"
        )
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
                guard install(
                    existingWebView,
                    for: tab,
                    using: installation,
                    context: context
                ) else {
                    return .failed
                }
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
            let setupWebView = context.setupWebView
            if context.deferWebsiteDataMutationWebViewMaterialization(
                { setupWebView(registerTabWithExtensionRuntime) }
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
                guard install(
                    overrideWebView,
                    for: tab,
                    using: installation,
                    context: context
                ) else {
                    return .failed
                }
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = provisioningOwner.makeNormalTabWebView(
                context: context,
                policyTransaction: policyTransaction,
                reason: reason
            ) {
                guard install(
                    normalWebView,
                    for: tab,
                    using: installation,
                    context: context
                ) else {
                    return .failed
                }
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

        guard let committedWebView = context.currentWebView() else {
            return .failed
        }

        if registerTabWithExtensionRuntime,
           shouldDelayInitialTabRuntimeRegistration == false {
            provisioningOwner.registerTabWithExtensionRuntimeIfNeeded(
                context: context,
                reason: reason
            )
        }

        guard context.currentWebView() === committedWebView else {
            return supersededOutcome(context: context)
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(context.currentURL()),
           context.currentWebView() === committedWebView {
            loadExtensionOwnedInitialURL(
                context.currentURL(),
                on: committedWebView,
                context: context
            )
            context.finishSuspendedRestoreIfNeeded()
            return .available(committedWebView)
        }

        if didCreateNormalWebView && context.isPopupHost() == false {
            context.scheduleInitialDocumentRuntimeHandoff(
                committedWebView,
                context.currentURL(),
                profile.id,
                "\(reason).beforeInitialLoad"
            )
        }

        context.finishSuspendedRestoreIfNeeded()
        guard let currentWebView = context.currentWebView() else {
            return .failed
        }
        guard currentWebView === committedWebView else {
            return .superseded(currentWebView)
        }
        return .available(currentWebView)
    }

    private func supersededOutcome(
        context: TabNormalWebViewRuntimeContext
    ) -> TabUntrackedWebViewEnsureOutcome {
        context.finishSuspendedRestoreIfNeeded()
        guard let currentWebView = context.currentWebView() else {
            return .failed
        }
        return .superseded(currentWebView)
    }

    private func install(
        _ webView: WKWebView,
        for tab: Tab,
        using installation: (any UntrackedWebViewInstalling)?,
        context: TabNormalWebViewRuntimeContext
    ) -> Bool {
        guard let installation else {
            if context.currentWebView() !== webView,
               context.parkedWebView() !== webView {
                context.cleanupCloneWebView(webView)
            }
            return false
        }
        let outcome = installation.installUntracked(webView, for: tab)
        guard outcome.isAccepted else {
            if outcome.callerRetainsWebView {
                context.cleanupCloneWebView(webView)
            }
            return false
        }
        return context.currentWebView() === webView
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
