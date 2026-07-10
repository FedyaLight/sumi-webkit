import Foundation
import WebKit
import SumiDomain
import SumiWebRuntime

enum TabMainFrameReloadCommandOutcome: Equatable {
    case accepted
    case scheduled
    case failed

    func merged(with other: Self) -> Self {
        if self == .failed || other == .failed { return .failed }
        if self == .scheduled || other == .scheduled { return .scheduled }
        return .accepted
    }
}

@MainActor
final class TabNavigationCommandOwner {
    typealias WebViewResolver = @MainActor @Sendable () -> WKWebView?
    typealias ConfigurationPolicyRebuilder = @MainActor (
        _ targetURL: URL,
        _ reason: String
    ) -> TabWebViewReplacementOutcome

    func loadURL(_ newURL: URL, for tab: Tab) {
        guard tab.hasCurrentWebView else {
            _ = tab.beginMainFrameNavigationIntent(to: newURL)
            _ = tab.beginWebViewRebuildIntent()
            tab.url = newURL
            tab.beginLoadingPresentationIfNeeded()
            let replacementOutcome = prepareMainFrameConfigurationPolicyIfNeeded(
                newURL,
                for: tab,
                reason: "Tab.loadURL.initial"
            )
            if replacementOutcome == .failed {
                tab.rollbackMainFrameNavigationAfterFailedSubmission(on: nil)
                return
            }
            if replacementOutcome.blocksCallerNavigation
                || replacementOutcome.navigationWasScheduled {
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                return
            }
            switch tab.ensureUntrackedNormalWebViewOutcome(
                reason: "Tab.loadURL.initial"
            ) {
            case .available:
                break
            case .deferred:
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                return
            case .failed:
                tab.rollbackMainFrameNavigationAfterFailedSubmission(on: nil)
                return
            }
            tab.applyCachedFaviconOrPlaceholder(for: newURL)
            return
        }

        loadURL(
            newURL,
            for: tab,
            resolvedWebView: { [weak tab] in tab?.resolvedCurrentWebView() },
            reason: "Tab.loadURL"
        )
    }

    func loadURL(
        _ newURL: URL,
        for tab: Tab,
        resolvedWebView: WebViewResolver,
        reason: String,
        configurationPolicyRebuilder: ConfigurationPolicyRebuilder? = nil
    ) {
        let navigationIntent = tab.beginMainFrameNavigationIntent(to: newURL)
        _ = tab.beginWebViewRebuildIntent()
        tab.url = newURL
        tab.beginLoadingPresentationIfNeeded()
        tab.resetPlaybackActivity()
        let extensionReplacementOutcome = prepareMainFrameConfigurationPolicyIfNeeded(
            newURL,
            for: tab,
            reason: reason
        )

        if extensionReplacementOutcome == .failed {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: resolvedWebView()
            )
            return
        }

        if extensionReplacementOutcome.blocksCallerNavigation
            || extensionReplacementOutcome.navigationWasScheduled {
            tab.applyCachedFaviconOrPlaceholder(for: newURL)
            return
        }

        guard let initialWebView = resolvedWebView() else {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(on: nil)
            return
        }

        let configurationReplacementOutcome = extensionReplacementOutcome == .notNeeded
            && ExtensionUtils.isExtensionOwnedURL(newURL) == false
            ? (configurationPolicyRebuilder?(newURL, reason)
                ?? tab.rebuildNormalWebViewForConfigurationPolicyOutcome(
                    targetURL: newURL,
                    reason: reason
                ))
            : .notNeeded

        if configurationReplacementOutcome == .failed {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: initialWebView
            )
            return
        }

        if configurationReplacementOutcome.blocksCallerNavigation
            || configurationReplacementOutcome.navigationWasScheduled {
            tab.applyCachedFaviconOrPlaceholder(for: newURL)
            return
        }

        let webView = extensionReplacementOutcome.didReplace
                || configurationReplacementOutcome.didReplace
            ? (resolvedWebView() ?? initialWebView)
            : initialWebView

        performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            tab: tab,
            waitForContentBlockingAssets: configurationReplacementOutcome.didReplace
        ) { resolvedWebView, resolvedTargetURL in
            WebRuntimeMainFrameLoader.load(resolvedTargetURL, on: resolvedWebView)
        }

        if tab.isCurrentMainFrameNavigationIntent(navigationIntent) {
            tab.applyCachedFaviconOrPlaceholder(for: newURL)
        }
    }

    @discardableResult
    func prepareMainFrameConfigurationPolicyIfNeeded(
        _ newURL: URL,
        for tab: Tab,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard ExtensionUtils.isExtensionOwnedURL(newURL)
                || tab.webExtensionContextOverride != nil
        else {
            return .notNeeded
        }
        return tab.navigationRuntime.navigationCommandRuntime.prepareExtensionPageNavigation(
            tab,
            newURL,
            reason
        )
    }

    func loadURL(_ urlString: String, for tab: Tab) {
        guard let newURL = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL, for: tab)
    }

    func navigateToURL(_ input: String, for tab: Tab) {
        let template = tab.sumiSettings?.resolvedSearchEngineTemplate
            ?? tab.navigationRuntime.navigationCommandRuntime.resolvedSearchEngineTemplate()
            ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(input, queryTemplate: template)

        guard let validURL = URL(string: normalizedUrl) else {
            RuntimeDiagnostics.emit("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        loadURL(validURL, for: tab)
    }

    @discardableResult
    func refresh(_ tab: Tab) -> TabMainFrameReloadCommandOutcome {
        refresh(
            tab,
            resolvedWebView: { [weak tab] in tab?.resolvedCurrentWebView() },
            reason: "Tab.refresh",
            deliverTrackedReload: { [weak self, weak tab] intent, policy in
                guard let self, let tab else { return .failed }
                return self.deliverReload(
                    for: tab,
                    intent: intent,
                    policy: policy
                )
            }
        )
    }

    @discardableResult
    func recoverWebContentProcess(
        _ tab: Tab,
        targetURL: URL,
        sourceWebView: WKWebView,
        configurationPolicyRebuilder: ConfigurationPolicyRebuilder? = nil
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.retainWebContentProcessRecovery(on: sourceWebView) else {
            return .failed
        }
        return refresh(
            tab,
            resolvedWebView: { [weak sourceWebView] in sourceWebView },
            reason: "WebContentProcess.global-recovery",
            targetURLOverride: targetURL,
            configurationPolicyRebuilder: configurationPolicyRebuilder,
            deliverTrackedReload: { [weak self, weak tab, weak sourceWebView] intent, policy in
                guard let self, let tab, let sourceWebView else { return .failed }
                return self.deliverWebContentProcessRecovery(
                    for: tab,
                    sourceWebView: sourceWebView,
                    intent: intent,
                    policy: policy
                )
            }
        )
    }

    /// Restores the exact semantic document after a destructive WebKit data
    /// transaction temporarily navigated every physical replica to a blank
    /// document. One new revision is created for the whole Tab, so replicas do
    /// not race each other or retain the pre-deletion document generation.
    @discardableResult
    func restoreAfterDestructiveDataCleanup(
        _ tab: Tab,
        targetURL: URL
    ) -> TabMainFrameReloadCommandOutcome {
        refresh(
            tab,
            resolvedWebView: { [weak tab] in tab?.resolvedCurrentWebView() },
            reason: "DestructiveDataCleanup.restore",
            policy: .fromOrigin,
            targetURLOverride: targetURL,
            deliverTrackedReload: { [weak self, weak tab] intent, policy in
                guard let self, let tab else { return .failed }
                return self.deliverReload(
                    for: tab,
                    intent: intent,
                    policy: policy,
                    includesParkedWebView: true
                )
            }
        )
    }

    /// Creates one semantic reload revision before any configuration rebuild
    /// or WebView delivery. Tracked delivery is injected so global and
    /// window-scoped commands share the same Tab-owned transaction.
    @discardableResult
    func refresh(
        _ tab: Tab,
        resolvedWebView: WebViewResolver,
        reason: String,
        policy: WebRuntimeMainFrameReloadPolicy = .standard,
        targetURLOverride: URL? = nil,
        configurationPolicyRebuilder: ConfigurationPolicyRebuilder? = nil,
        deliverTrackedReload: @MainActor (
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> TabMainFrameReloadCommandOutcome
    ) -> TabMainFrameReloadCommandOutcome {
        guard !tab.representsSumiNativeSurface else { return .failed }

        let currentWebView = resolvedWebView()
        let targetURL = targetURLOverride
            ?? currentWebView?.committedURL
            ?? currentWebView?.url
            ?? tab.url
        let navigationIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.beginWebViewRebuildIntent()
        tab.beginLoadingPresentationIfNeeded()
        let protectionReloadWasRequired = tab.reloadPolicyStateOwner.isProtectionReloadRequired
        let configurationReplacementOutcome = configurationPolicyRebuilder?(
            targetURL,
            reason
        ) ?? tab.rebuildNormalWebViewForConfigurationPolicyOutcome(
            targetURL: targetURL,
            reason: reason
        )

        if configurationReplacementOutcome == .failed {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: currentWebView
            )
            return .failed
        }

        if protectionReloadWasRequired {
            tab.noteProtectionManualReloadResult(
                rebuiltForConfigurationPolicy: configurationReplacementOutcome.didReplace,
                targetURL: targetURL
            )
        }

        if configurationReplacementOutcome.blocksCallerNavigation
            || configurationReplacementOutcome.navigationWasScheduled {
            return .scheduled
        }

        if configurationReplacementOutcome == .replacedNavigationPending,
           let webView = resolvedWebView() ?? currentWebView {
            performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                on: webView,
                tab: tab,
                waitForContentBlockingAssets: true
            ) { resolvedWebView, resolvedTargetURL in
                WebRuntimeMainFrameLoader.load(resolvedTargetURL, on: resolvedWebView)
            }
            return .scheduled
        } else if configurationReplacementOutcome == .replacedNavigationPending {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: currentWebView
            )
            return .failed
        }

        if configurationReplacementOutcome == .notNeeded {
            guard tab.isCurrentMainFrameNavigationIntent(navigationIntent) else {
                return .failed
            }
            let outcome = deliverTrackedReload(navigationIntent, policy)
            if outcome == .failed {
                tab.rollbackMainFrameNavigationAfterFailedSubmission(
                    on: currentWebView
                )
            }
            return outcome
        }
        return .failed
    }

    private func deliverReload(
        for tab: Tab,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy,
        includesParkedWebView: Bool = false
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.isCurrentMainFrameNavigationIntent(intent) else {
            return .failed
        }

        var didDeliver = false
        var outcome = TabMainFrameReloadCommandOutcome.accepted
        if let untrackedWebView = tab.webViewSession.untrackedWebView {
            didDeliver = true
            outcome = outcome.merged(with: submitExactReload(
                on: untrackedWebView,
                tab: tab,
                intent: intent,
                policy: policy
            ))
        }
        if includesParkedWebView,
           let parkedWebView = tab.webViewSession.parkedWebView,
           parkedWebView !== tab.webViewSession.untrackedWebView {
            didDeliver = true
            outcome = outcome.merged(with: submitExactReload(
                on: parkedWebView,
                tab: tab,
                intent: intent,
                policy: policy
            ))
        }
        if tab.resolvedPrimaryWindowId() != nil {
            didDeliver = true
            tab.navigationRuntime.webViewRouting.reloadTabAcrossWindows(
                tab.id,
                intent,
                policy
            )
            outcome = outcome.merged(with: .scheduled)
        }
        return didDeliver ? outcome : .failed
    }

    /// Global recovery creates a fresh semantic revision, broadcasts it to
    /// healthy window replicas, and delegates repair of the exact crashed
    /// WebView to the retained process-recovery owner. Detached WebViews never
    /// bypass compositor protection through the ordinary direct-load path.
    private func deliverWebContentProcessRecovery(
        for tab: Tab,
        sourceWebView: WKWebView,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.isCurrentMainFrameNavigationIntent(intent) else {
            return .failed
        }

        var broadcastOutcome = TabMainFrameReloadCommandOutcome.failed
        if tab.resolvedPrimaryWindowId() != nil {
            tab.navigationRuntime.webViewRouting.reloadTabAcrossWindows(
                tab.id,
                intent,
                policy
            )
            broadcastOutcome = .scheduled
        }

        let sourceOutcome = tab.reconcileWebContentProcessRecovery(
            on: sourceWebView
        )
        if sourceOutcome == .scheduled || broadcastOutcome == .scheduled {
            return .scheduled
        }
        if sourceOutcome == .accepted || broadcastOutcome == .accepted {
            return .accepted
        }
        return .failed
    }

    func submitExactReload(
        on webView: WKWebView,
        tab: Tab,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.isCurrentMainFrameNavigationIntent(intent) else {
            return .failed
        }
        guard tab.markDeferredMainFrameLoad(on: webView, intent: intent) else {
            return tab.hasOutstandingMainFrameLoad(
                on: webView,
                targetURL: intent.targetURL
            ) ? .scheduled : .failed
        }
        let claim = tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: intent.targetURL
        ) { resolvedWebView in
            WebRuntimeMainFrameReloader.reloadOrLoad(
                intent.targetURL,
                on: resolvedWebView,
                policy: policy
            )
        }
        switch claim {
        case .claimed:
            return .accepted
        case .alreadyScheduled:
            return .scheduled
        case .submissionFailed, .stale:
            return .failed
        }
    }

    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        tab: Tab,
        waitForContentBlockingAssets: Bool,
        performLoad: @escaping @MainActor @Sendable (WKWebView, URL) -> WKNavigation?
    ) {
        guard waitForContentBlockingAssets,
              let controller = webView.configuration.userContentController.sumiNormalTabUserContentController
        else {
            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                performLoad(resolvedWebView, tab.url)
            }
            return
        }

        let navigationIntent = tab.currentMainFrameNavigationIntent(matching: tab.url)
        let preparationTicket = navigationIntent.flatMap {
            tab.beginPreparedMainFrameLoad(on: webView, intent: $0)
        }
        tab.navigationRuntime.navigationTransactionOwner.performAfterPreparation(
            on: webView,
            prepare: {
                await controller.waitForContentBlockingAssetsInstalled()
            },
            didCancel: { [weak tab] in
                guard let tab, let preparationTicket else { return }
                tab.finishPreparedMainFrameLoad(preparationTicket)
            },
            performLoad: { [weak tab] resolvedWebView in
                guard let tab else { return }
                if let preparationTicket {
                    tab.finishPreparedMainFrameLoad(preparationTicket)
                }
                guard let currentIntent = navigationIntent.flatMap({
                    tab.currentMainFrameNavigationIntent(revision: $0.revision)
                }) else {
                    return
                }
                tab.performMainFrameNavigation(on: resolvedWebView) {
                    performLoad($0, currentIntent.targetURL)
                }
            }
        )
    }

}
