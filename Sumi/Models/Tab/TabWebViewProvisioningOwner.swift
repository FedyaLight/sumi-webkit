import Combine
import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    @discardableResult
    func ensureWebView(for tab: Tab) -> WKWebView? {
        if tab._webView == nil {
            setupWebView(for: tab)
        }
        return tab._webView
    }

    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        tab: Tab,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        tab.replaceUntrackedWebView(webView)

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
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
        tab: Tab,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        tab.replaceUntrackedWebView(webView)

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    func assignWebViewToWindow(_ webView: WKWebView, tab: Tab, windowId: UUID) {
        tab.assignPrimaryWebView(webView, windowId: windowId)
        tab.ownedWebViewPreparationOwner.prepareAssignedWebView(webView)
    }

    @discardableResult
    func makeNormalTabWebView(
        for tab: Tab,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        guard let profile = tab.resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            deferNormalTabWebViewCreationUntilProfileAvailable(for: tab)
            return nil
        }

        guard let configuration = normalTabWebViewConfiguration(
            for: tab,
            profile: profile,
            reason: reason
        ) else {
            return nil
        }

        let configurationContext = TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        configurationContext.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profile.id,
            "\(reason).configuration"
        )
        prepareConfiguration?(configuration)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, tab: tab, reason: reason)
        return webView
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(for tab: Tab, reason: String) {
        tab.browserManager?.extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
            tab,
            reason: reason
        )

        if let browserManager = tab.browserManager,
           let windowId = tab.primaryWindowId,
           let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == tab.id {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: nil
            )
        }
    }

    func setupWebView(for tab: Tab) {
        tab.beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = tab._existingWebView
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false

        guard let profile = tab.resolveProfile() else {
            deferNormalTabWebViewCreationUntilProfileAvailable(for: tab)
            return
        }

        let configurationContext = TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        let auxiliaryOverrideConfiguration = tab.webViewConfigurationOwner.auxiliaryOverrideConfiguration(
            for: profile,
            context: configurationContext
        )

        if let existingWebView = reusableExistingWebView {
            if canReuseAsNormalTabWebView(existingWebView, tab: tab) {
                tab.adoptParkedWebViewAsCurrent(existingWebView)
                didReuseExistingWebView = true
                Task { @MainActor [weak tab, weak existingWebView] in
                    guard let tab, let existingWebView else { return }
                    await tab.replaceNormalTabUserScripts(
                        on: existingWebView.configuration.userContentController,
                        for: tab.url
                    )
                }
            } else {
                tab.cleanupCloneWebView(existingWebView)
                tab.clearParkedExistingWebView()
            }
        }

        if tab._webView == nil {
            if let auxiliaryOverrideConfiguration {
                configurationContext.prepareWebViewConfigurationForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "Tab.setupWebView.configuration"
                )
                let newWebView = FocusableWKWebView(frame: .zero, configuration: auxiliaryOverrideConfiguration)
                tab.replaceUntrackedWebView(newWebView)
                didCreateAuxiliaryOverrideWebView = true
                configureAuxiliaryOverrideWebView(newWebView, tab: tab, reason: "Tab.setupWebView")
            } else {
                if let normalWebView = makeNormalTabWebView(for: tab, reason: "Tab.setupWebView") {
                    tab.replaceUntrackedWebView(normalWebView)
                }
            }
        }

        if let webView = tab._webView {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                tab.ownedWebViewPreparationOwner.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = tab._webView {
            tab.ownedWebViewPreparationOwner.applyOwnedTabWebViewNavigationPreferences(to: webView)
        }

        let shouldDelayInitialNormalTabRuntimeRegistration =
            tab.webViewConfigurationOwner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: tab.isPopupHost,
                hasExistingWebView: tab._existingWebView != nil,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: tab.url
            )

        if shouldDelayInitialNormalTabRuntimeRegistration == false {
            registerNormalTabWithExtensionRuntimeIfNeeded(for: tab, reason: "Tab.setupWebView")
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(tab.url),
           let webView = tab._webView {
            loadExtensionOwnedInitialURL(tab.url, on: webView, tab: tab)
            tab.finishSuspendedRestoreIfNeeded()
            return
        }

        if shouldDelayInitialNormalTabRuntimeRegistration {
            let initialWebView = tab._webView
            let hasInitialUserContentController = initialWebView?.configuration
                .userContentController
                .sumiNormalTabUserContentController != nil
            NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                tab: tab,
                webView: initialWebView,
                targetURL: tab.url,
                profileId: profile.id,
                registrationReason: "Tab.setupWebView.beforeInitialLoad",
                registrationGuard: hasInitialUserContentController
                    ? .currentWebViewIdentity
                    : .noExistingWebView
            )
        }

        tab.finishSuspendedRestoreIfNeeded()
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        for tab: Tab
    ) {
        tab.webViewConfigurationOwner.applyWebViewConfigurationOverride(
            configuration,
            profileId: tab.resolveProfile()?.id ?? tab.profileId,
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        )
    }

    private func configureNormalTabWebView(
        _ webView: FocusableWKWebView,
        tab: Tab,
        reason: String
    ) {
        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: tab.url,
            reason: reason
        )
    }

    private func loadExtensionOwnedInitialURL(_ targetURL: URL, on webView: WKWebView, tab: Tab) {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        tab.performMainFrameNavigation(on: webView) { resolvedWebView in
            resolvedWebView.load(request)
        }
        tab.applyCachedFaviconOrPlaceholder(for: targetURL)
    }

    private func normalTabWebViewConfiguration(
        for tab: Tab,
        profile: Profile,
        reason: String
    ) -> WKWebViewConfiguration? {
        return tab.webViewConfigurationOwner.normalTabWebViewConfiguration(
            for: tab.url,
            profile: profile,
            userScriptsProvider: tab.normalTabUserScriptsProvider(for: tab.url),
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager),
            reloadPolicyStateOwner: tab.reloadPolicyStateOwner
        )
    }

    private func deferNormalTabWebViewCreationUntilProfileAvailable(for tab: Tab) {
        guard tab.profileAwaitCancellable == nil else { return }

        RuntimeDiagnostics.emit(
            "[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile..."
        )
        tab.profileAwaitCancellable = tab.browserManager?
            .$currentProfile
            .receive(on: RunLoop.main)
            .sink { [weak self, weak tab] value in
                guard let self, let tab else { return }
                if value != nil && tab._webView == nil {
                    tab.profileAwaitCancellable?.cancel()
                    tab.profileAwaitCancellable = nil
                    self.setupWebView(for: tab)
                }
            }
    }

    private func canReuseAsNormalTabWebView(_ webView: WKWebView, tab: Tab) -> Bool {
        tab.webViewConfigurationOwner.canReuseAsNormalTabWebView(
            webView,
            fallbackURL: tab.url,
            tabId: tab.id,
            profile: tab.resolveProfile(),
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager),
            reloadPolicyStateOwner: tab.reloadPolicyStateOwner
        )
    }

    private func configureAuxiliaryOverrideWebView(
        _ webView: FocusableWKWebView,
        tab: Tab,
        reason: String
    ) {
        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: tab.url,
            reason: reason,
            enableVisitedLinkRecording: false,
            applyNavigationPreferences: false
        )
    }
}
