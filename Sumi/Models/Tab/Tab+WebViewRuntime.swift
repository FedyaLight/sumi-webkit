import Foundation
import Navigation
import WebKit

enum TabMainFrameNavigationSubmissionOutcome: Equatable {
    case submitted
    case alreadyScheduled
    case missingNavigator
    case submissionFailed
}

extension Tab {
    // MARK: - WebView Ownership (session/registry resolve + mutator forwards)

    /// Session/registry resolve for Tab-internal owners and derived helpers.
    /// Not a public WebView SoT accessor — live lookup stays on routing/session.
    func resolvedCurrentWebView() -> WKWebView? {
        webViewSession.currentWebView
    }

    @discardableResult
    func retainWebContentProcessRecovery(on webView: WKWebView) -> Bool {
        guard webViewSession.owns(webView),
              requiresWebContentProcessRecovery(on: webView) else {
            return false
        }
        return navigationRuntime.webViewRouting.retainWebContentProcessRecovery(
            id,
            webView
        )
    }

    @discardableResult
    func reconcileWebContentProcessRecovery(
        on webView: WKWebView
    ) -> TabMainFrameReloadCommandOutcome {
        guard webViewSession.owns(webView),
              requiresWebContentProcessRecovery(on: webView) else {
            return .failed
        }
        return navigationRuntime.webViewRouting.recoverWebContentProcess(
            id,
            webView
        )
    }

    /// Parked/staging WebView from session (or pre-runtime local session).
    func resolvedParkedWebView() -> WKWebView? {
        webViewSession.parkedWebView
    }

    /// Primary window id from session/registry (or pre-runtime local session).
    func resolvedPrimaryWindowId() -> UUID? {
        webViewSession.primaryWindowID
    }

    /// Window-assigned primary WebView when a primary window id is known.
    func resolvedAssignedWebView() -> WKWebView? {
        webViewSession.primaryWebView
    }

    var hasCurrentWebView: Bool {
        resolvedCurrentWebView() != nil
    }

    var hasParkedWebView: Bool {
        resolvedParkedWebView() != nil
    }

    public func currentWebViewIsIdentical(to webView: WKWebView) -> Bool {
        resolvedCurrentWebView() === webView
    }

    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        webViewProvisioningOwner.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            context: normalWebViewRuntimeContext(),
            currentURL: currentURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: reason
        )
    }

    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        webViewProvisioningOwner.createPopupWebViewFromWebKitConfiguration(
            configuration,
            context: normalWebViewRuntimeContext(),
            currentURL: currentURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: reason
        )
    }

    /// Installs the Tab-owned runtime on a WebView after the coordinator has
    /// committed its window ownership in the canonical session repository.
    func prepareAssignedWebView(_ webView: WKWebView) {
        webViewProvisioningOwner.prepareAssignedWebView(
            webView,
            context: normalWebViewRuntimeContext()
        )
    }

    /// Installs the Tab-owned runtime observers on WebViews created outside
    /// the untracked ensure path owned by the WebView runtime.
    func installRuntimeObservers(on webView: WKWebView) {
        ownedWebViewPreparationOwner.installRuntimeObservers(on: webView)
    }

    /// Creates a fully configured normal-tab WebView. This is the single
    /// construction path for primary and clone normal-tab runtimes.
    public func makeNormalTabWebView(
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        makeNormalTabWebView(
            reason: reason,
            prepareExtensionRuntime: true,
            prepareConfiguration: prepareConfiguration
        )
    }

    func makeNormalTabWebView(
        reason: String,
        prepareExtensionRuntime: Bool,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        webViewProvisioningOwner.makeNormalTabWebView(
            context: normalWebViewRuntimeContext(),
            reason: reason,
            prepareExtensionRuntime: prepareExtensionRuntime,
            prepareConfiguration: prepareConfiguration
        )
    }

    /// Transactional profile replacement path. Kept separate from the public
    /// protocol requirement so ordinary materialization cannot accidentally
    /// provision against a profile that is not yet committed on the Tab.
    func makeNormalTabWebView(
        reason: String,
        explicitProfile: Profile,
        prepareExtensionRuntime: Bool,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        webViewProvisioningOwner.makeNormalTabWebView(
            context: normalWebViewRuntimeContext(),
            reason: reason,
            explicitProfile: explicitProfile,
            prepareExtensionRuntime: prepareExtensionRuntime,
            prepareConfiguration: prepareConfiguration
        )
    }

    func prepareNormalWebViewExtensionRuntime(
        _ webView: WKWebView,
        targetURL: URL,
        reason: String
    ) {
        navigationRuntime.normalWebViewExtensionRuntime
            .prepareWebViewForExtensionRuntime(webView, targetURL, reason)
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(webView, currentURL: url, reason: reason)
    }

    func makeAuxiliaryOverrideTabWebView(
        configuration: WKWebViewConfiguration,
        reason: String
    ) -> WKWebView {
        let runtimeContext = normalWebViewRuntimeContext()
        let webView = AuxiliaryWebViewFactory
            .makeWebViewPreservingWebKitConfiguration(configuration)
        runtimeContext.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            runtimeContext.currentURL(),
            reason,
            .auxiliaryOverride
        )
        return webView
    }

    public func registerTabWithExtensionRuntimeIfNeeded(reason: String) {
        webViewProvisioningOwner.registerTabWithExtensionRuntimeIfNeeded(
            context: normalWebViewRuntimeContext(),
            reason: reason
        )
    }

    // MARK: - WebView Runtime

    func webViewConfigurationContext() -> TabWebViewConfigurationContext {
        makeWebViewConfigurationContext()
    }

    func normalTabUserScriptsProvider(
        for targetURL: URL?,
        profileIDOverride: UUID? = nil
    ) -> SumiNormalTabUserScripts {
        webViewConfigurationOwner.normalTabUserScriptsProvider(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: {
                profileIDOverride ?? self.resolveProfile()?.id ?? self.profileId
            },
            context: webViewConfigurationContext(),
            isEphemeral: isEphemeral
        )
    }

    func normalTabManagedUserScripts(
        for targetURL: URL?,
        profileIDOverride: UUID? = nil
    ) -> [SumiUserScript] {
        webViewConfigurationOwner.normalTabManagedUserScripts(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: {
                profileIDOverride ?? self.resolveProfile()?.id ?? self.profileId
            },
            context: webViewConfigurationContext(),
            isEphemeral: isEphemeral
        )
    }

    func replaceNormalTabUserScripts(
        on userContentController: WKUserContentController,
        for targetURL: URL?
    ) async {
        guard let controller = userContentController.sumiNormalTabUserContentController,
              let provider = controller.normalTabUserScriptsProvider
        else { return }

        let managedUserScripts = normalTabManagedUserScripts(for: targetURL)
        guard provider.replaceManagedUserScriptsIfChanged(managedUserScripts) else {
            return
        }

        let signpostState = PerformanceTrace.beginInterval("Tab.replaceNormalTabUserScripts")
        defer { PerformanceTrace.endInterval("Tab.replaceNormalTabUserScripts", signpostState) }
        await controller.replaceNormalTabUserScripts(with: provider)
    }

    public func cancelPendingMainFrameNavigation() {
        navigationRuntime.navigationTransactionOwner.cancelPendingMainFrameNavigation(
            environment: navigationTransactionEnvironment()
        )
    }

    @available(macOS 15.5, *)
    func performMainFrameNavigationAfterHydrationIfNeeded(
        on webView: WKWebView,
        performLoad: @escaping @MainActor @Sendable (WKWebView) -> WKNavigation?
    ) {
        performMainFrameNavigation(
            on: webView,
            performLoad: performLoad
        )
    }

    @discardableResult
    func performMainFrameNavigation(
        on webView: WKWebView,
        didSubmit: @escaping @MainActor @Sendable (
            _ navigationID: ObjectIdentifier,
            _ navigationLifetime: AnyObject
        ) -> Void = { _, _ in },
        performLoad: @escaping @MainActor @Sendable (WKWebView) -> WKNavigation?
    ) -> TabMainFrameNavigationSubmissionOutcome {
        let intent = currentMainFrameNavigationIntent()
        if navigationRuntime.webViewCleanupRuntime
            .deferWebsiteDataMutationMainFrameSubmission(
                self,
                webView,
                intent.revision,
                { [weak self, weak webView] in
                    guard let self,
                          let webView,
                          self.webViewSession.owns(webView),
                          self.isCurrentMainFrameNavigationIntent(
                              revision: intent.revision,
                              targetURL: intent.targetURL
                          ) else {
                        return
                    }
                    _ = self.performMainFrameNavigation(
                        on: webView,
                        didSubmit: didSubmit,
                        performLoad: performLoad
                    )
                }
            ) {
            return .alreadyScheduled
        }
        guard let submissionLease = claimDirectMainFrameLoadLease(on: webView) else {
            return .alreadyScheduled
        }
        guard let navigator = webView.navigator() else {
            let failure = failSubmittedMainFrameLoad(
                on: webView,
                matching: submissionLease
            )
            settleFailedMainFrameSubmissionIfNeeded(failure, on: webView)
            assertionFailure(
                "Normal-tab main-frame loads require DistributedNavigationDelegate"
            )
            return .missingNavigator
        }
        let didCreateNavigation = performClaimedMainFrameNavigation(
            on: webView,
            navigator: navigator,
            submissionLease: submissionLease,
            didSubmit: didSubmit,
            performLoad: performLoad
        )
        if didCreateNavigation == false {
            let failure = failSubmittedMainFrameLoad(
                on: webView,
                matching: submissionLease
            )
            settleFailedMainFrameSubmissionIfNeeded(failure, on: webView)
            return .submissionFailed
        }
        return .submitted
    }

    @discardableResult
    func performDeferredMainFrameNavigation(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        performLoad: @escaping @MainActor (WKWebView) -> WKNavigation?
    ) -> TabDeferredMainFrameLoadClaim {
        if navigationRuntime.webViewCleanupRuntime
            .deferWebsiteDataMutationMainFrameSubmission(
                self,
                webView,
                revision,
                { [weak self, weak webView] in
                    guard let self,
                          let webView,
                          self.webViewSession.owns(webView),
                          self.isCurrentMainFrameNavigationIntent(
                              revision: revision,
                              targetURL: targetURL
                          ) else {
                        return
                    }
                    _ = self.performDeferredMainFrameNavigation(
                        on: webView,
                        revision: revision,
                        targetURL: targetURL,
                        performLoad: performLoad
                    )
                }
            ) {
            return .alreadyScheduled
        }
        let claim = claimDeferredMainFrameLoad(
            on: webView,
            revision: revision,
            targetURL: targetURL
        )
        guard claim == .claimed else { return claim }
        guard let submissionLease = submittedMainFrameLoadLease(
            on: webView,
            revision: revision,
            targetURL: targetURL
        ) else {
            return .submissionFailed
        }
        guard let navigator = webView.navigator() else {
            restoreDeferredMainFrameLoadAfterFailedSubmission(
                on: webView,
                revision: revision,
                targetURL: targetURL,
                matching: submissionLease
            )
            assertionFailure(
                "Normal-tab deferred main-frame loads require DistributedNavigationDelegate"
            )
            return .submissionFailed
        }
        let didCreateNavigation = performClaimedMainFrameNavigation(
            on: webView,
            navigator: navigator,
            submissionLease: submissionLease,
            performLoad: performLoad
        )
        guard didCreateNavigation else {
            restoreDeferredMainFrameLoadAfterFailedSubmission(
                on: webView,
                revision: revision,
                targetURL: targetURL,
                matching: submissionLease
            )
            return .submissionFailed
        }
        return .claimed
    }

    private func performClaimedMainFrameNavigation(
        on webView: WKWebView,
        navigator: Navigator,
        submissionLease: TabMainFrameSubmissionLease? = nil,
        didSubmit: @MainActor (
            _ navigationID: ObjectIdentifier,
            _ navigationLifetime: AnyObject
        ) -> Void = { _, _ in },
        performLoad: @escaping @MainActor (WKWebView) -> WKNavigation?
    ) -> Bool {
        navigationRuntime.navigationTransactionOwner.perform(
            on: webView,
            performLoad: { [weak self] resolvedWebView in
                guard let self else { return false }
                guard let navigation = performLoad(resolvedWebView) else {
                    return false
                }
                let expectedNavigation = navigator.expect(navigation)
                precondition(
                    bindSubmittedMainFrameLoad(
                        on: resolvedWebView,
                        navigationID: expectedNavigation.stableIdentifier,
                        navigationLifetime: expectedNavigation.identityLifetime,
                        matching: submissionLease
                    ),
                    "Submitted main-frame load lost its exact navigation transaction"
                )
                didSubmit(
                    expectedNavigation.stableIdentifier,
                    expectedNavigation.identityLifetime
                )
                return true
            }
        )
    }

    private func settleFailedMainFrameSubmissionIfNeeded(
        _ result: TabMainFrameNavigationAbortResult,
        on webView: WKWebView
    ) {
        guard case .authoritativeTerminated = result else { return }
        rollbackMainFrameNavigationAfterFailedSubmission(on: webView)
    }

    /// Single create-policy path for pre-window / untracked normal-tab WebViews.
    func ensureUntrackedNormalWebViewOutcome(
        reason: String = "Tab.ensureUntrackedNormalWebView"
    ) -> TabUntrackedWebViewEnsureOutcome {
        normalWebViewSetupOwner.ensureUntrackedNormalWebView(
            context: normalWebViewRuntimeContext(),
            provisioningOwner: webViewProvisioningOwner,
            reason: reason
        )
    }

    @discardableResult
    func ensureUntrackedNormalWebView(
        reason: String = "Tab.ensureUntrackedNormalWebView"
    ) -> WKWebView? {
        ensureUntrackedNormalWebViewOutcome(reason: reason).webView
    }

    /// Thin wrapper retained for call sites that historically named this `setupWebView`.
    func setupWebView() {
        _ = ensureUntrackedNormalWebView(reason: "Tab.setupWebView")
    }

    func resolveProfile() -> Profile? {
        profileResolutionOwner.resolveProfile(for: self)
    }

    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        webViewProvisioningOwner.applyWebViewConfigurationOverride(
            configuration,
            context: normalWebViewRuntimeContext()
        )
    }

    func normalWebViewRuntimeContext() -> TabNormalWebViewRuntimeContext {
        normalWebViewRuntimeContextOwner.makeContext()
    }
}
