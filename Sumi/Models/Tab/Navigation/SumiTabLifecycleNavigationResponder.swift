import Foundation
import Navigation
import SumiDomain
import WebKit

@MainActor
final class SumiTabLifecycleNavigationResponder:
    SumiNavigationStartResponding,
    SumiNavigationResponseContextResponding,
    SumiNavigationCommitResponding,
    SumiNavigationCompletionResponding,
    SumiNavigationTerminalResponding,
    SumiSameDocumentNavigationResponding,
    SumiNavigationAuthChallengeResponding {
    private weak var tab: Tab?
    private let submission: any TabMainFrameSubmissionSettlement
    private let lifecycle: any TabMainFrameLifecycleSettlement
    private let promotion: any TabMainFramePromotionSettlement
    private let recovery: any TabWebContentRecoveryAdmission

    init(
        tab: Tab,
        submission: any TabMainFrameSubmissionSettlement,
        lifecycle: any TabMainFrameLifecycleSettlement,
        promotion: any TabMainFramePromotionSettlement,
        recovery: any TabWebContentRecoveryAdmission
    ) {
        self.tab = tab
        self.submission = submission
        self.lifecycle = lifecycle
        self.promotion = promotion
        self.recovery = recovery
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }
        (webView as? FocusableWKWebView)?
            .resetPageInteractionStateForNavigation()
        webView.sumiReaderPresentationHost?.dismissReader()

        tab.navigationRuntime.lifecycleNavigationRuntime
            .destructiveDataCleanupNavigationWillStart(
                webView,
                context.navigationID,
                context.navigationLifetime,
                context.action?.request.url ?? context.url,
                submission.semanticRevision(
                    for: webView,
                    navigationID: context.navigationID,
                    navigationLifetime: context.navigationLifetime
                )
            )

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        let role = beginMainFrameLifecycle(
            context,
            tab: tab,
            webView: webView,
            allowUserInitiatedSupersession: true
        )
        guard role.isParticipant else { return }
        publishLocalStartEffectsIfNeeded(context, tab: tab, webView: webView)
        let roleAfterLocalEffects = lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        guard roleAfterLocalEffects.isAuthority else { return }
        _ = publishAuthorityStartEffectsIfNeeded(
            context,
            tab: tab,
            webView: webView
        )
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }
        (webView as? FocusableWKWebView)?
            .resetPageInteractionStateForNavigation()
        webView.sumiReaderPresentationHost?.dismissReader()

        tab.navigationRuntime.lifecycleNavigationRuntime
            .destructiveDataCleanupNavigationWillStart(
                webView,
                context.navigationID,
                context.navigationLifetime,
                context.action?.request.url ?? context.url,
                submission.semanticRevision(
                    for: webView,
                    navigationID: context.navigationID,
                    navigationLifetime: context.navigationLifetime
                )
            )

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        var role = lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: context.isCurrent
        )
        if role == .stale {
            role = beginMainFrameLifecycle(
                context,
                tab: tab,
                webView: webView,
                allowUserInitiatedSupersession: true
            )
        }
        guard role.isParticipant else { return }
        publishLocalStartEffectsIfNeeded(context, tab: tab, webView: webView)
        role = lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: context.isCurrent
        )
        guard role.isAuthority,
              let authorityLease = publishAuthorityStartEffectsIfNeeded(
                  context,
                  tab: tab,
                  webView: webView
              ) else { return }

        tab.beginLoadingPresentationIfNeeded()
        guard lifecycle.remainsCurrent(authorityLease) else { return }
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
        guard lifecycle.remainsCurrent(authorityLease) else { return }
        tab.resetPlaybackActivity()

        if let newURL = webView.url {
            if newURL.absoluteString != tab.url.absoluteString {
                guard tab.applyAcceptedMainFrameLifecycleURL(
                    newURL,
                    from: webView,
                    navigationID: context.navigationID
                ) else { return }
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                tab.refreshFaviconExtensionCache()
            } else {
                guard tab.applyAcceptedMainFrameLifecycleURL(
                    newURL,
                    from: webView,
                    navigationID: context.navigationID
                ) else { return }
            }
        }
    }

    func decidePolicy(
        for response: SumiNavigationResponse,
        context: SumiNavigationContext?
    ) async -> SumiNavigationResponsePolicy? {
        guard response.isForMainFrame else { return .next }

        guard let context, let webView = context.webView else { return .next }
        lifecycle.noteResponse(
            isPDF: response.mimeType?.lowercased() == "application/pdf",
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime
        )
        return .next
    }

    func navigationDidCommit(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        let initialRole = lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        guard initialRole.isParticipant else { return }
        publishLocalStartEffectsIfNeeded(context, tab: tab, webView: webView)
        guard lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        ).isParticipant else { return }
        let preparedRole = lifecycle.prepareAuthorityForCommit(
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime
        )
        guard preparedRole.isParticipant else { return }
        if preparedRole.isAuthority {
            guard publishAuthorityStartEffectsIfNeeded(
                context,
                tab: tab,
                webView: webView
            ) != nil else { return }
        }
        guard let committedURL = webView.committedURL ?? webView.url ?? context.url else {
            return
        }
        let decision = lifecycle.settleCommit(
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime,
            committedURL: committedURL
        )
        guard case .publish(let publication) = decision else { return }

        TabMainFrameLifecycleReducer.publishCommit(
            publication,
            tab: tab,
            lifecycle: lifecycle
        )
    }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        guard let tab,
              let context,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }
        defer {
            finishDestructiveDataCleanupNavigation(
                on: webView,
                context: context,
                succeeded: true
            )
        }

        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        let initialRole = lifecycle.role(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        if initialRole.isParticipant {
            if let newURL = webView.url {
                tab.navigationRuntime.lifecycleNavigationRuntime.applyAdblockZapperRulesAfterNavigation(
                    webView,
                    newURL,
                    tab
                )
            }
            tab.mediaRuntime.callbacks.invalidateBackgroundMediaCommand(webView)
            tab.navigationRuntime.lifecycleNavigationRuntime.loadZoomForTab(
                tab.id,
                webView
            )
            guard lifecycle.role(
                from: webView,
                navigationID: context.navigationID,
                isCurrent: nil
            ).isParticipant else { return }
            // A terminal success callback proves the document committed;
            // compensate missed commit callbacks before terminal settlement.
            navigationDidCommit(context)
        }
        let decision = lifecycle.settleFinish(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            terminalURL: webView.url ?? context.url
        )
        guard case .publish(let publication) = decision else { return }

        TabMainFrameLifecycleReducer.publishFinish(
            publication,
            tab: tab,
            lifecycle: lifecycle
        )
    }

    func navigationDidSameDocumentNavigation(
        type navigationType: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        guard let tab,
              let context,
              let webView = context.webView,
              let newURL = webView.url
        else { return }
        webView.sumiReaderPresentationHost?.dismissReader()
        if context.isCurrent != true {
            guard navigationType == .sessionStatePop,
                  tab.navigationRuntime.navigationTransactionOwner
                    .pendingMainFrameNavigationKind == .backForward else {
                return
            }
        }
        let beginRole = tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            targetURL: newURL,
            allowsUserInitiatedSupersession: false,
            continuationKind: .sameDocument
        )
        guard beginRole.isParticipant else { return }
        let decision = lifecycle.settleSameDocument(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            presentationURL: newURL
        )
        guard case .publish(let publication) = decision else { return }

        TabMainFrameLifecycleReducer.publishSameDocument(
            publication,
            navigationType: navigationType,
            tab: tab,
            lifecycle: lifecycle
        )
    }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        guard let tab,
              let context,
              context.isMainFrame == true
        else { return }

        guard let webView = context.webView else { return }
        defer {
            finishDestructiveDataCleanupNavigation(
                on: webView,
                context: context,
                succeeded: false
            )
        }
        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        let terminationResult = tab.abortMainFrameNavigation(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            rollsBackWhenUnreplaced: error.sumiIsNavigationCancelled
        )
        guard terminationResult != .ignored else { return }

        switch terminationResult {
        case .authoritativeContinuation(let continuation):
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: tab,
                promotion: promotion
            )
            tab.finishBackForwardNavigationTrackingIfOwned(by: webView)
            return
        case .ignored, .participant:
            tab.finishBackForwardNavigationTrackingIfOwned(by: webView)
            return
        case .authoritativeRollback:
            tab.finishBackForwardNavigationTrackingIfOwned(by: webView)
            settleAbortedNavigationPresentation(tab)
            return
        case .authoritativeTerminated:
            tab.finishBackForwardNavigationTrackingIfOwned(by: webView)
            break
        }

        tab.loadingState = context.isCommitted == true
            ? .didFail(error)
            : .didFailProvisionalNavigation(error)
        tab.updateNavigationState()
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
    }

    func mainFrameNavigationDidTerminate(
        _ termination: SumiMainFrameNavigationTermination
    ) {
        guard let tab else { return }
        let shouldSuppress = shouldSuppressForDestructiveDataCleanup(
            on: termination.webView,
            navigationID: termination.navigationID,
            navigationLifetime: termination.navigationLifetime
        )
        tab.navigationRuntime.lifecycleNavigationRuntime
            .finishDestructiveDataCleanupNavigation(
                termination.webView,
                termination.navigationID,
                termination.navigationLifetime,
                false
            )
        guard shouldSuppress == false else { return }
        let result = tab.abortMainFrameNavigation(
            from: termination.webView,
            navigationID: termination.navigationID,
            navigationLifetime: termination.navigationLifetime
        )
        guard result != .ignored else { return }
        switch result {
        case .authoritativeContinuation(let continuation):
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: tab,
                promotion: promotion
            )
            tab.finishBackForwardNavigationTrackingIfOwned(
                by: termination.webView
            )
        case .authoritativeRollback, .authoritativeTerminated:
            tab.finishBackForwardNavigationTrackingIfOwned(
                by: termination.webView
            )
            settleAbortedNavigationPresentation(tab)
        case .participant:
            tab.finishBackForwardNavigationTrackingIfOwned(
                by: termination.webView
            )
        case .ignored:
            break
        }
    }

    func webContentProcessDidTerminate(on webView: WKWebView) {
        guard let tab, tab.webViewSession.owns(webView) else { return }
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        webView.sumiReaderPresentationHost?.dismissReader()
        if tab.navigationRuntime.lifecycleNavigationRuntime
            .handleDestructiveDataCleanupProcessTermination(webView) {
            return
        }
        let recoveryPlan = recovery.beginRecovery(on: webView)
        if let continuation = recoveryPlan.authorityContinuation {
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: tab,
                promotion: promotion
            )
        }
        tab.finishBackForwardNavigationTrackingIfOwned(by: webView)

        switch recoveryPlan.scope {
        case .replica:
            _ = tab.navigationRuntime.webViewRouting
                .recoverWebContentProcess(tab.id, webView)
        case .global(let targetURL):
            _ = tab.navigationCommandOwner.recoverWebContentProcess(
                tab,
                targetURL: targetURL,
                sourceWebView: webView
            )
        }
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context _: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        await sumiAuthChallengeDisposition(for: authenticationChallenge)
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge, context: nil)
    }

    private func sumiAuthChallengeDisposition(
        for authenticationChallenge: URLAuthenticationChallenge
    ) async -> SumiAuthChallengeDisposition? {
        guard let tab else { return .next }
        return await tab.navigationRuntime.lifecycleNavigationRuntime.resolveAuthenticationChallenge(
            authenticationChallenge,
            tab
        )
    }

    private func shouldSuppressForDestructiveDataCleanup(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> Bool {
        tab?.navigationRuntime.lifecycleNavigationRuntime
            .isPreparingForDataCleanupNavigation(
                webView,
                navigationID,
                navigationLifetime
            ) == true
    }

    private func beginMainFrameLifecycle(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView,
        allowUserInitiatedSupersession: Bool = false
    ) -> TabMainFrameLifecycleRole {
        let isFreshUserAction = allowUserInitiatedSupersession
            && context.action?.isUserInitiated == true
        return tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            targetURL: context.url ?? context.action?.request.url,
            allowsUserInitiatedSupersession: isFreshUserAction,
            continuationKind: context.action.flatMap {
                if $0.isClientRedirect { return .clientRedirect }
                if $0.navigationType == .sameDocumentNavigation {
                    return .sameDocument
                }
                return nil
            }
        )
    }

    private func publishLocalStartEffectsIfNeeded(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView
    ) {
        guard context.action?.navigationType != .sameDocumentNavigation else {
            return
        }
        let decision = lifecycle.claimLocalStartEffects(
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime
        )
        guard let targetURL = decision.value else { return }
        guard case .publish = decision else { return }
        tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionWebView(
            webView,
            targetURL,
            "SumiTabLifecycleNavigationResponder.start"
        )
    }

    private func publishAuthorityStartEffectsIfNeeded(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView
    ) -> TabMainFrameActiveAuthorityLease? {
        guard context.action?.navigationType != .sameDocumentNavigation else {
            return nil
        }
        let transactionStart = lifecycle.claimTransactionStartEffects(
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime
        )
        guard let transactionLease = transactionStart.value else { return nil }
        if case .publish = transactionStart {
            guard publishSharedTransactionStartEffects(
                transactionLease,
                tab: tab,
                webView: webView,
                isBackForward: context.action?.navigationType.isBackForward == true
            ) else { return nil }
        }
        guard lifecycle.remainsCurrent(transactionLease) else { return nil }
        guard context.action?.navigationType.isBackForward != true else {
            return transactionLease
        }
        let targetPreparation = lifecycle.claimAuthorityTargetPreparation(
            from: webView,
            navigationID: context.navigationID, navigationLifetime: context.navigationLifetime
        )
        guard let targetLease = targetPreparation.value else { return nil }
        if case .publish = targetPreparation {
            tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionRuntimeBeforeCommit(
                tab,
                targetLease.targetURL,
                "SumiTabLifecycleNavigationResponder.start"
            )
        }
        return lifecycle.remainsCurrent(targetLease) ? targetLease : nil
    }

    private func publishSharedTransactionStartEffects(
        _ lease: TabMainFrameActiveAuthorityLease,
        tab: Tab,
        webView: WKWebView,
        isBackForward: Bool
    ) -> Bool {
        StartupPerformanceTrace.firstNavigationStarted()
        if isBackForward {
            tab.beginBackForwardNavigationTracking(on: webView)
            guard lifecycle.remainsCurrent(lease) else { return false }
        } else {
            tab.handleNormalTabPermissionNavigation(to: lease.targetURL)
            guard lifecycle.remainsCurrent(lease) else { return false }
            tab.markRegularMainFrameNavigation(on: webView)
            guard lifecycle.remainsCurrent(lease) else { return false }
        }
        tab.navigationRuntime.lifecycleNavigationRuntime.resetRevisitProtection(tab)
        return lifecycle.remainsCurrent(lease)
    }

    private func settleAbortedNavigationPresentation(_ tab: Tab) {
        if tab.loadingState.isLoading {
            tab.loadingState = .idle
        }
        tab.applyCachedFaviconOrPlaceholder(for: tab.url)
        tab.refreshFaviconExtensionCache()
        tab.updateNavigationState()
        tab.stateChangeEmitter.postNavigationStateDidChange(for: tab)
        tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .loading]
        )
        tab.mediaRuntime.callbacks.scheduleBackgroundMediaReconcile(
            "navigation-terminal-rollback"
        )
    }

    private func finishDestructiveDataCleanupNavigation(
        on webView: WKWebView,
        context: SumiNavigationContext,
        succeeded: Bool
    ) {
        tab?.navigationRuntime.lifecycleNavigationRuntime
            .finishDestructiveDataCleanupNavigation(
                webView,
                context.navigationID,
                context.navigationLifetime,
                succeeded
            )
    }
}

private extension WKError {
    var sumiIsNavigationCancelled: Bool {
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
