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

    init(tab: Tab) {
        self.tab = tab
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        webView.sumiReaderPresentationHost?.dismissReader()

        tab.navigationRuntime.lifecycleNavigationRuntime
            .destructiveDataCleanupNavigationWillStart(
                webView,
                context.navigationID,
                context.navigationLifetime,
                context.action?.request.url ?? context.url,
                tab.submittedMainFrameSemanticRevision(
                    on: webView,
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
        let roleAfterLocalEffects = tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        if roleAfterLocalEffects.isAuthority {
            publishAuthorityStartEffectsIfNeeded(
                context,
                tab: tab,
                webView: webView
            )
        }
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        guard let tab,
              context.isMainFrame == true,
              let webView = context.webView
        else { return }
        (webView as? FocusableWKWebView)?.resetPageInteractionState()
        webView.sumiReaderPresentationHost?.dismissReader()

        tab.navigationRuntime.lifecycleNavigationRuntime
            .destructiveDataCleanupNavigationWillStart(
                webView,
                context.navigationID,
                context.navigationLifetime,
                context.action?.request.url ?? context.url,
                tab.submittedMainFrameSemanticRevision(
                    on: webView,
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
        var role = tab.mainFrameLifecycleRole(
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
        role = tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: context.isCurrent
        )
        if role.isAuthority {
            publishAuthorityStartEffectsIfNeeded(
                context,
                tab: tab,
                webView: webView
            )
        }
        guard tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: context.isCurrent
        ).isAuthority else { return }

        tab.beginLoadingPresentationIfNeeded()
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
        tab.resetPlaybackActivity()

        if let newURL = webView.url {
            if newURL.absoluteString != tab.url.absoluteString {
                tab.applyAcceptedMainFrameLifecycleURL(
                    newURL,
                    from: webView,
                    navigationID: context.navigationID
                )
                tab.applyCachedFaviconOrPlaceholder(for: newURL)
                tab.refreshFaviconExtensionCache()
            } else {
                tab.applyAcceptedMainFrameLifecycleURL(
                    newURL,
                    from: webView,
                    navigationID: context.navigationID
                )
            }
        }
    }

    func decidePolicy(
        for response: SumiNavigationResponse,
        context: SumiNavigationContext?
    ) async -> SumiNavigationResponsePolicy? {
        guard let tab,
              response.isForMainFrame
        else { return .next }

        if let context, let webView = context.webView {
            tab.recordMainFrameResponse(
                isPDF: response.mimeType?.lowercased() == "application/pdf",
                from: webView,
                navigationID: context.navigationID
            )
        }
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
        let initialRole = tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        guard initialRole.isParticipant else { return }
        publishLocalStartEffectsIfNeeded(context, tab: tab, webView: webView)
        guard tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        ).isParticipant else { return }
        let preparedRole = tab.prepareMainFrameAuthorityForCommit(
            from: webView,
            navigationID: context.navigationID
        )
        guard preparedRole.isParticipant else { return }
        if preparedRole.isAuthority {
            guard tab.mainFrameLifecycleRole(
                from: webView,
                navigationID: context.navigationID,
                isCurrent: nil
            ).isAuthority else { return }
            publishAuthorityStartEffectsIfNeeded(
                context,
                tab: tab,
                webView: webView
            )
            guard tab.mainFrameLifecycleRole(
                from: webView,
                navigationID: context.navigationID,
                isCurrent: nil
            ).isAuthority else { return }
        }
        let isPDF = tab.mainFrameResponseIsPDF(
            from: webView,
            navigationID: context.navigationID
        ) ?? false
        guard let committedURL = webView.committedURL ?? webView.url ?? context.url else {
            return
        }
        let claim = tab.recordMainFrameCommitSnapshot(
            from: webView,
            navigationID: context.navigationID,
            committedURL: committedURL,
            isPDF: isPDF
        )
        guard claim.shouldPublishSharedEffects else { return }

        TabMainFrameLifecycleReducer.publishCommit(
            .navigation(
                webView: webView,
                navigationID: context.navigationID,
                targetURL: committedURL,
                isPDF: isPDF
            ),
            tab: tab
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
        let initialRole = tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        )
        guard initialRole.isParticipant else { return }

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
        guard tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        ).isParticipant else { return }
        let role = tab.claimMainFrameAuthorityForTerminalSuccess(
            from: webView,
            navigationID: context.navigationID,
            terminalURL: webView.url ?? context.url,
            completesDocumentNavigation: true
        )
        guard role.isParticipant else { return }
        guard role.isAuthority else {
            tab.finishMainFrameLifecycle(
                from: webView,
                navigationID: context.navigationID
            )
            return
        }

        publishAuthorityStartEffectsIfNeeded(context, tab: tab, webView: webView)
        navigationDidCommit(context)
        guard tab.mainFrameLifecycleRole(
            from: webView,
            navigationID: context.navigationID,
            isCurrent: nil
        ).isAuthority,
        tab.claimSharedMainFrameFinishEffects(
            from: webView,
            navigationID: context.navigationID
        ) else {
            tab.finishMainFrameLifecycle(
                from: webView,
                navigationID: context.navigationID
            )
            return
        }

        TabMainFrameLifecycleReducer.publishFinish(
            .navigation(
                webView: webView,
                navigationID: context.navigationID,
                targetURL: webView.url ?? context.url ?? tab.url,
                isPDF: tab.committedDocumentRuntime.lease(for: webView)?.isPDF
                    ?? false
            ),
            tab: tab
        )
        tab.finishMainFrameLifecycle(
            from: webView,
            navigationID: context.navigationID
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
        let role = tab.claimMainFrameAuthorityForTerminalSuccess(
            from: webView,
            navigationID: context.navigationID,
            terminalURL: newURL,
            completesDocumentNavigation: false
        )
        guard role.isAuthority else {
            tab.finishMainFrameLifecycle(
                from: webView,
                navigationID: context.navigationID
            )
            return
        }

        tab.handleSameDocumentNavigation(
            to: newURL,
            from: webView,
            navigationID: context.navigationID
        )
        tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: newURL,
            type: navigationType,
            tab: tab
        )
        if tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind == .backForward {
            tab.scheduleBackForwardSameDocumentSettle(using: webView)
        } else {
            tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
            tab.navigationRuntime.webViewRouting.syncTabAcrossWindows(tab.id, webView)
            tab.navigationRuntime.navigationTransactionOwner.pendingMainFrameNavigationKind = nil
        }

        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.URL])
        tab.finishMainFrameLifecycle(
            from: webView,
            navigationID: context.navigationID
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
                tab: tab
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
                tab: tab
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
        let recoveryPlan = tab.beginWebContentProcessRecovery(on: webView)
        if let continuation = recoveryPlan.authorityContinuation {
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: tab
            )
        }
        tab.finishBackForwardNavigationTrackingIfOwned(by: webView)

        switch recoveryPlan.scope {
        case .replica:
            _ = tab.reconcileWebContentProcessRecovery(on: webView)
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
        guard context.action?.navigationType != .sameDocumentNavigation,
              let url = context.url ?? context.action?.request.url,
              tab.claimMainFrameLocalStartEffects(
            from: webView,
            navigationID: context.navigationID
        ) else {
            return
        }
        tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionWebView(
            webView,
            url,
            "SumiTabLifecycleNavigationResponder.start"
        )
    }

    private func publishAuthorityStartEffectsIfNeeded(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView
    ) {
        guard context.action?.navigationType != .sameDocumentNavigation else {
            return
        }
        if tab.claimMainFrameTransactionStartEffects(
            from: webView,
            navigationID: context.navigationID
        ) {
            publishSharedTransactionStartEffects(
                context,
                tab: tab,
                webView: webView
            )
        }
        guard context.action?.navigationType.isBackForward != true,
              let url = context.url ?? context.action?.request.url,
              tab.claimMainFrameAuthorityTargetPreparation(
            from: webView,
            navigationID: context.navigationID
        ) else {
            return
        }
        tab.navigationRuntime.lifecycleNavigationRuntime.prepareExtensionRuntimeBeforeCommit(
            tab,
            url,
            "SumiTabLifecycleNavigationResponder.start"
        )
    }

    private func publishSharedTransactionStartEffects(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView
    ) {
        StartupPerformanceTrace.firstNavigationStarted()
        let isBackForward = context.action?.navigationType.isBackForward == true
        if isBackForward {
            tab.beginBackForwardNavigationTracking(on: webView)
        } else {
            tab.handleNormalTabPermissionNavigation(to: context.url)
            tab.markRegularMainFrameNavigation(on: webView)
        }
        tab.navigationRuntime.lifecycleNavigationRuntime.resetRevisitProtection(tab)
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
