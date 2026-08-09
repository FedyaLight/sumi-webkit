import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

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

enum PageReloadFailureReason: Equatable {
    case unsupportedPage
    case staleAttempt
    case noResidence
    case protectedDeliveryRejected
    case missingNavigator
    case nativeReloadUnavailable
    case submissionFailed
    case deliveryContextUnavailable
}

struct PageReloadFailure: Equatable {
    let intent: TabMainFrameNavigationIntent?
    let webViewID: ObjectIdentifier?
    let reason: PageReloadFailureReason
}

struct PageReloadSubmission: Equatable {
    let owner: TabMainFramePendingAttemptOwner
    /// Stable identity produced only after WebKit returned a concrete
    /// WKNavigation and the distributed navigator bound it to `owner`.
    let navigationID: ObjectIdentifier
}

enum PageReloadDisposition: Equatable {
    case submitted(PageReloadSubmission)
    case submittedFallbackNavigation(PageReloadSubmission)
    case waiting(TabMainFramePendingAttemptOwner)
    case coalesced(TabMainFramePendingAttemptOwner)
    case failed(PageReloadFailure)

    var ownsFutureOrSubmittedNavigation: Bool {
        switch self {
        case .submitted, .submittedFallbackNavigation, .waiting, .coalesced:
            return true
        case .failed:
            return false
        }
    }
}

/// One user command can address several physical residences. Keeping every
/// disposition prevents a deferred replica from hiding a failed or submitted
/// sibling residence.
struct PageReloadCommandOutcome: Equatable {
    let dispositions: [PageReloadDisposition]

    init(_ disposition: PageReloadDisposition) {
        dispositions = [disposition]
    }

    init(dispositions: [PageReloadDisposition]) {
        precondition(
            dispositions.isEmpty == false,
            "A Page Reload command must expose at least one exact disposition"
        )
        self.dispositions = dispositions
    }

    var ownsFutureOrSubmittedNavigation: Bool {
        dispositions.contains(where: \.ownsFutureOrSubmittedNavigation)
    }

    var containsConcreteSubmission: Bool {
        dispositions.contains {
            switch $0 {
            case .submitted, .submittedFallbackNavigation:
                true
            case .waiting, .coalesced, .failed:
                false
            }
        }
    }

    var legacyRecoveryOutcome: TabMainFrameReloadCommandOutcome {
        if containsConcreteSubmission { return .accepted }
        if ownsFutureOrSubmittedNavigation { return .scheduled }
        return .failed
    }

    func merged(with other: Self) -> Self {
        Self(dispositions: dispositions + other.dispositions)
    }

    static func failed(
        intent: TabMainFrameNavigationIntent?,
        webView: WKWebView? = nil,
        reason: PageReloadFailureReason
    ) -> Self {
        Self(.failed(PageReloadFailure(
            intent: intent,
            webViewID: webView.map(ObjectIdentifier.init),
            reason: reason
        )))
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
            tab.cancelPendingMainFrameNavigation()
            _ = tab.beginMainFrameNavigationIntent(to: newURL)
            _ = tab.webViewRebuildEpoch.advance()
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
            case .available, .superseded:
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
        tab.cancelPendingMainFrameNavigation()
        let navigationIntent = tab.beginMainFrameNavigationIntent(to: newURL)
        _ = tab.webViewRebuildEpoch.advance()
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
            && ExtensionURLIdentity.isOwned(newURL) == false
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

        if tab.mainFrameLoads.isCurrent(navigationIntent) {
            tab.applyCachedFaviconOrPlaceholder(for: newURL)
        }
    }

    @discardableResult
    func prepareMainFrameConfigurationPolicyIfNeeded(
        _ newURL: URL,
        for tab: Tab,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        guard ExtensionURLIdentity.isOwned(newURL)
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
    func refresh(_ tab: Tab) -> PageReloadCommandOutcome {
        let resolvedWebView = tab.resolvedCurrentWebView()
        if let resolvedWebView,
           tab.webContentRecoveryMarkers.recoveryState(on: resolvedWebView)?
            .isFailure == true {
            tab.webContentRecoveryAdmission.authorizeRecoveryEpochReset(
                onCommitFrom: resolvedWebView
            )
        }
        return refresh(
            tab,
            resolvedWebView: { [weak resolvedWebView] in resolvedWebView },
            reason: "Tab.refresh",
            deliverTrackedReload: { [weak self, weak tab] intent, policy in
                guard let self, let tab else {
                    return .failed(
                        intent: intent,
                        reason: .deliveryContextUnavailable
                    )
                }
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
        sourceWebView: WKWebView
    ) -> TabMainFrameReloadCommandOutcome {
        guard tab.navigationRuntime.webViewRouting
            .retainWebContentProcessRecovery(tab.id, sourceWebView) else {
            return .failed
        }
        var recoveryOutcome = TabMainFrameReloadCommandOutcome.failed
        _ = refresh(
            tab,
            resolvedWebView: { [weak sourceWebView] in sourceWebView },
            reason: "WebContentProcess.global-recovery",
            targetURLOverride: targetURL,
            rollbackOnDeliveryFailure: false,
            deliverTrackedReload: { [weak self, weak tab, weak sourceWebView] intent, policy in
                guard let self, let tab, let sourceWebView else {
                    return .failed(
                        intent: intent,
                        reason: .deliveryContextUnavailable
                    )
                }
                let delivery = self.deliverWebContentProcessRecovery(
                    for: tab,
                    sourceWebView: sourceWebView,
                    intent: intent,
                    policy: policy
                )
                recoveryOutcome = delivery.recovery
                return delivery.page
            }
        )
        return recoveryOutcome
    }

    /// Restores the exact semantic document after a destructive WebKit data
    /// transaction temporarily navigated every physical replica to a blank
    /// document. One new revision is created for the whole Tab, so replicas do
    /// not race each other or retain the pre-deletion document generation.
    @discardableResult
    func restoreAfterDestructiveDataCleanup(
        _ tab: Tab,
        targetURL: URL
    ) -> PageReloadCommandOutcome {
        guard !tab.representsSumiNativeSurface else {
            return .failed(
                intent: tab.mainFrameLoads.currentIntent,
                reason: .unsupportedPage
            )
        }
        tab.cancelPendingMainFrameNavigation()
        let intent = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.webViewRebuildEpoch.advance()
        tab.beginLoadingPresentationIfNeeded()
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }

        var dispositions: [PageReloadDisposition] = []
        for webView in tab.webViewSession.allKnownWebViews {
            dispositions.append(contentsOf: submitExactNavigation(
                on: webView,
                tab: tab,
                intent: intent
            ).dispositions)
        }
        guard dispositions.isEmpty == false else {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(on: nil)
            return .failed(intent: intent, reason: .noResidence)
        }
        let outcome = PageReloadCommandOutcome(dispositions: dispositions)
        if outcome.containsConcreteSubmission == false {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: tab.resolvedCurrentWebView()
            )
        }
        return outcome
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
        rollbackOnDeliveryFailure: Bool = true,
        deliverTrackedReload: @MainActor (
            TabMainFrameNavigationIntent,
            WebRuntimeMainFrameReloadPolicy
        ) -> PageReloadCommandOutcome
    ) -> PageReloadCommandOutcome {
        guard !tab.representsSumiNativeSurface else {
            return .failed(
                intent: tab.mainFrameLoads.currentIntent,
                reason: .unsupportedPage
            )
        }

        tab.cancelPendingMainFrameNavigation()
        let currentWebView = resolvedWebView()
        let targetURL = targetURLOverride
            ?? currentWebView?.committedURL
            ?? tab.url
        let navigationIntent = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.webViewRebuildEpoch.advance()
        tab.beginLoadingPresentationIfNeeded()
        guard tab.mainFrameLoads.isCurrent(navigationIntent) else {
            return .failed(
                intent: navigationIntent,
                webView: currentWebView,
                reason: .staleAttempt
            )
        }
        let outcome = deliverTrackedReload(navigationIntent, policy)
        if rollbackOnDeliveryFailure
            && outcome.ownsFutureOrSubmittedNavigation == false {
            tab.rollbackMainFrameNavigationAfterFailedSubmission(
                on: currentWebView
            )
        }
        return outcome
    }

    private func deliverReload(
        for tab: Tab,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy,
        includesParkedWebView: Bool = false
    ) -> PageReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, reason: .staleAttempt)
        }

        var didDeliver = false
        var dispositions: [PageReloadDisposition] = []
        if let untrackedWebView = tab.webViewSession.untrackedWebView {
            didDeliver = true
            dispositions.append(contentsOf: submitExactReload(
                on: untrackedWebView,
                tab: tab,
                intent: intent,
                policy: policy
            ).dispositions)
        }
        if includesParkedWebView,
           let parkedWebView = tab.webViewSession.parkedWebView,
           parkedWebView !== tab.webViewSession.untrackedWebView {
            didDeliver = true
            dispositions.append(contentsOf: submitExactReload(
                on: parkedWebView,
                tab: tab,
                intent: intent,
                policy: policy
            ).dispositions)
        }
        if tab.resolvedPrimaryWindowId() != nil {
            didDeliver = true
            dispositions.append(contentsOf: tab.navigationRuntime.webViewRouting
                .reloadTabAcrossWindows(
                tab.id,
                intent,
                policy
            ).dispositions)
        }
        return didDeliver
            ? PageReloadCommandOutcome(dispositions: dispositions)
            : .failed(intent: intent, reason: .noResidence)
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
    ) -> (
        page: PageReloadCommandOutcome,
        recovery: TabMainFrameReloadCommandOutcome
    ) {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return (
                .failed(intent: intent, webView: sourceWebView, reason: .staleAttempt),
                .failed
            )
        }

        var broadcastOutcome: PageReloadCommandOutcome?
        if tab.resolvedPrimaryWindowId() != nil {
            broadcastOutcome = tab.navigationRuntime.webViewRouting
                .reloadTabAcrossWindows(
                tab.id,
                intent,
                policy
            )
        }

        let sourceOutcome = tab.navigationRuntime.webViewRouting
            .recoverWebContentProcess(tab.id, sourceWebView)
        if let broadcastOutcome {
            let combinedRecovery = sourceOutcome == .failed
                ? broadcastOutcome.legacyRecoveryOutcome
                : sourceOutcome
            return (broadcastOutcome, combinedRecovery)
        }
        return (
            .failed(
                intent: intent,
                webView: sourceWebView,
                reason: sourceOutcome == .failed
                    ? .submissionFailed
                    : .deliveryContextUnavailable
            ),
            sourceOutcome
        )
    }

    func submitExactReload(
        on webView: WKWebView,
        tab: Tab,
        intent: TabMainFrameNavigationIntent,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> PageReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, webView: webView, reason: .staleAttempt)
        }
        let admission = tab.mainFrameLoads.deferAttempt(
            on: webView,
            intent: intent
        )
        let admittedOwner: TabMainFramePendingAttemptOwner
        switch admission {
        case .waiting(let owner):
            admittedOwner = owner
        case .coalesced(let owner):
            return PageReloadCommandOutcome(.coalesced(owner))
        case .rejected:
            return .failed(
                intent: intent,
                webView: webView,
                reason: .submissionFailed
            )
        }

        var submittedOwner: TabMainFramePendingAttemptOwner?
        var submittedNavigationID: ObjectIdentifier?
        var submission: WebRuntimeMainFrameReloadSubmission = .failed
        let allowsSafeFallback = webView.backForwardList.currentItem == nil
            && webView.url == nil
            && webView.committedURL == nil
            && tab.committedDocumentRuntime.lease(for: webView) == nil
        let claim = tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: intent.targetURL,
            restoreWaiterAfterFailedSubmission: false,
            didClaim: { submittedOwner = $0 },
            didSubmit: { navigationID, _ in
                submittedNavigationID = navigationID
            }
        ) { resolvedWebView in
            submission = WebRuntimeMainFrameReloader.reloadOrLoad(
                intent.targetURL,
                on: resolvedWebView,
                policy: policy,
                fallback: allowsSafeFallback
                    ? .safeOrdinaryNavigation
                    : .disallowed
            )
            return submission.navigation
        }
        switch claim {
        case .claimed:
            guard let submittedOwner, let submittedNavigationID else {
                return .failed(
                    intent: intent,
                    webView: webView,
                    reason: .submissionFailed
                )
            }
            let proof = PageReloadSubmission(
                owner: submittedOwner,
                navigationID: submittedNavigationID
            )
            switch submission {
            case .reloaded:
                return PageReloadCommandOutcome(.submitted(proof))
            case .fallbackNavigation:
                return PageReloadCommandOutcome(
                    .submittedFallbackNavigation(proof)
                )
            case .failed:
                return .failed(
                    intent: intent,
                    webView: webView,
                    reason: .nativeReloadUnavailable
                )
            }
        case .alreadyScheduled:
            return PageReloadCommandOutcome(.waiting(admittedOwner))
        case .submissionFailed, .stale:
            return .failed(
                intent: intent,
                webView: webView,
                reason: webView.navigator() == nil
                    ? .missingNavigator
                    : (submission.navigation == nil
                        ? .nativeReloadUnavailable
                        : .submissionFailed)
            )
        }
    }

    func submitExactNavigation(
        on webView: WKWebView,
        tab: Tab,
        intent: TabMainFrameNavigationIntent
    ) -> PageReloadCommandOutcome {
        guard tab.mainFrameLoads.isCurrent(intent) else {
            return .failed(intent: intent, webView: webView, reason: .staleAttempt)
        }
        let admission = tab.mainFrameLoads.deferAttempt(on: webView, intent: intent)
        let admittedOwner: TabMainFramePendingAttemptOwner
        switch admission {
        case .waiting(let owner): admittedOwner = owner
        case .coalesced(let owner):
            return PageReloadCommandOutcome(.coalesced(owner))
        case .rejected:
            return .failed(intent: intent, webView: webView, reason: .submissionFailed)
        }

        var submittedOwner: TabMainFramePendingAttemptOwner?
        var submittedNavigationID: ObjectIdentifier?
        let claim = tab.performDeferredMainFrameNavigation(
            on: webView,
            revision: intent.revision,
            targetURL: intent.targetURL,
            restoreWaiterAfterFailedSubmission: false,
            didClaim: { submittedOwner = $0 },
            didSubmit: { navigationID, _ in submittedNavigationID = navigationID }
        ) { resolvedWebView in
            WebRuntimeMainFrameLoader.load(intent.targetURL, on: resolvedWebView)
        }
        switch claim {
        case .claimed:
            guard let submittedOwner, let submittedNavigationID else {
                return .failed(intent: intent, webView: webView, reason: .submissionFailed)
            }
            return PageReloadCommandOutcome(.submittedFallbackNavigation(
                PageReloadSubmission(
                    owner: submittedOwner,
                    navigationID: submittedNavigationID
                )
            ))
        case .alreadyScheduled:
            return PageReloadCommandOutcome(.waiting(admittedOwner))
        case .submissionFailed, .stale:
            return .failed(
                intent: intent,
                webView: webView,
                reason: webView.navigator() == nil ? .missingNavigator : .submissionFailed
            )
        }
    }

    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        tab: Tab,
        waitForContentBlockingAssets: Bool,
        didClaim: @escaping @MainActor @Sendable (
            TabMainFramePendingAttemptOwner
        ) -> Void = { _ in },
        didSubmit: @escaping @MainActor @Sendable (
            ObjectIdentifier,
            AnyObject
        ) -> Void = { _, _ in },
        performLoad: @escaping @MainActor @Sendable (WKWebView, URL) -> WKNavigation?
    ) {
        guard waitForContentBlockingAssets,
              let controller = webView.configuration.userContentController.sumiNormalTabUserContentController
        else {
            tab.performMainFrameNavigation(
                on: webView,
                didClaim: didClaim,
                didSubmit: didSubmit
            ) { resolvedWebView in
                performLoad(
                    resolvedWebView,
                    tab.mainFrameLoads.currentIntent.targetURL
                )
            }
            return
        }

        let navigationIntent = tab.mainFrameLoads.currentIntent
        let preparationTicket = tab.mainFrameLoads.beginPreparedLoad(
            on: webView,
            intent: navigationIntent
        )
        _ = tab.navigationRuntime.navigationTransactionOwner.performAfterPreparation(
            on: webView,
            prepare: {
                await controller.waitForContentBlockingAssetsInstalled()
            },
            didTerminate: { [weak tab] _ in
                guard let tab, let preparationTicket else { return }
                tab.mainFrameLoads.finishPreparedLoad(preparationTicket)
            },
            performLoad: { [weak tab] resolvedWebView in
                guard let tab else { return }
                guard let currentIntent = tab.mainFrameLoads.currentIntent(
                    revision: navigationIntent.revision
                ) else {
                    return
                }
                tab.performMainFrameNavigation(
                    on: resolvedWebView,
                    preparedTicket: preparationTicket,
                    didClaim: didClaim,
                    didSubmit: didSubmit
                ) {
                    performLoad($0, currentIntent.targetURL)
                }
            }
        )
    }
}
