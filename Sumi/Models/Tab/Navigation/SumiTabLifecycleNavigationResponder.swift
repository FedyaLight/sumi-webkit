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
    SumiSameDocumentNavigationResponding {
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
        webView.sumiReaderPresentationHost?.dismissCertificateTrustWarning()
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
        if tab.webContentRecoveryMarkers.recoveryState(on: webView)?.phase
            == .recovering(navigationID: context.navigationID) {
            tab.navigationRuntime.webViewRouting
                .cancelWebContentProcessRecovery(webView)
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
        guard let committedURL = webView.url
                ?? context.url
                ?? webView.backForwardList.currentItem?.url
                ?? webView.committedURL else {
            return
        }
        let isUnexpectedRestoreBlank =
            tab.suspensionState.isRestoreInProgress
            && (committedURL.isSumiBlankDocumentURL
                || context.url?.isSumiBlankDocumentURL == true)
            && tab.suspensionState.lastSuspendedURL?.isSumiBlankDocumentURL != true
        guard isUnexpectedRestoreBlank == false,
              tab.mainFrameLoads.admitsCommit(to: committedURL) else {
            let wasRestoreFallback = tab.suspensionState.phase == .fallingBack
            let shouldSubmitRestoreFallback =
                (committedURL.isSumiBlankDocumentURL
                    || context.url?.isSumiBlankDocumentURL == true)
                && tab.suspensionState.beginFallback(
                    webViewID: ObjectIdentifier(webView),
                    navigationID: context.navigationID
                )
            let result = tab.abortMainFrameNavigation(
                from: webView,
                navigationID: context.navigationID,
                navigationLifetime: context.navigationLifetime
            )
            if result != .ignored {
                settleAbortedNavigationPresentation(tab, on: webView)
                settleSuspendedRestoreFailureIfNeeded(
                    tab: tab,
                    webView: webView,
                    wasFallback: wasRestoreFallback,
                    shouldSubmitFallback: shouldSubmitRestoreFallback
                )
            }
            return
        }
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
        _ = tab.commitSuspendedRestoreIfMatching(
            webView: webView,
            navigationID: context.navigationID
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
        settleCommittedNavigation(context, tab: tab, webView: webView)
    }

    /// A committed navigation owns a displayed document even when WebKit ends
    /// it with `didFail` (for example a cancelled back-forward cache restore).
    /// Both terminal callbacks therefore cross the same committed-document
    /// settlement seam.
    private func settleCommittedNavigation(
        _ context: SumiNavigationContext,
        tab: Tab,
        webView: WKWebView
    ) {
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
            tab.navigationRuntime.lifecycleNavigationRuntime.loadZoomForTab(
                tab.id,
                webView
            )
            guard lifecycle.role(
                from: webView,
                navigationID: context.navigationID,
                isCurrent: nil
            ).isParticipant else { return }
            // Recover a missing commit, but never re-identify a document whose
            // exact commit was already accepted.
            if !hasCurrentDocumentLease(tab, webView, context) {
                navigationDidCommit(context)
            }
            guard hasCurrentDocumentLease(tab, webView, context) else {
                let result = tab.abortMainFrameNavigation(
                    from: webView,
                    navigationID: context.navigationID,
                    navigationLifetime: context.navigationLifetime
                )
                if result != .ignored {
                    settleAbortedNavigationPresentation(tab, on: webView)
                }
                return
            }
        }
        let decision = lifecycle.settleFinish(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            terminalURL: webView.url
                ?? webView.backForwardList.currentItem?.url
                ?? context.url
                ?? webView.committedURL
        )
        guard case .publish(let publication) = decision else { return }

        TabMainFrameLifecycleReducer.publishFinish(
            publication,
            tab: tab,
            lifecycle: lifecycle
        )
    }

    private func hasCurrentDocumentLease(
        _ tab: Tab,
        _ webView: WKWebView,
        _ context: SumiNavigationContext
    ) -> Bool {
        guard let lease = tab.committedDocumentRuntime.lease(for: webView) else {
            return false
        }
        return lifecycle.documentLease(
            lease,
            matches: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
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
        if error.sumiIsContentPluginHandledLoad,
           tab.committedDocumentRuntime.lease(for: webView) != nil {
            navigationDidFinish(context)
            return
        }
        let preservesCommittedDocument = context.isCommitted == true
        defer {
            finishDestructiveDataCleanupNavigation(
                on: webView,
                context: context,
                succeeded: preservesCommittedDocument
            )
        }
        if shouldSuppressForDestructiveDataCleanup(
            on: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime
        ) {
            return
        }
        if preservesCommittedDocument {
            settleCommittedNavigation(context, tab: tab, webView: webView)
            return
        }
        let wasRestoreFallback = tab.suspensionState.phase == .fallingBack
        let shouldSubmitRestoreFallback = error.sumiIsNavigationCancelled == false
            && tab.suspensionState.beginFallback(
                webViewID: ObjectIdentifier(webView),
                navigationID: context.navigationID
            )
        if error.sumiIsNavigationCancelled {
            tab.cancelSuspendedRestoreIfNeeded()
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
            settleAbortedNavigationPresentation(tab, on: webView)
            settleSuspendedRestoreFailureIfNeeded(
                tab: tab,
                webView: webView,
                wasFallback: wasRestoreFallback,
                shouldSubmitFallback: shouldSubmitRestoreFallback
            )
            return
        case .authoritativeTerminated:
            tab.finishBackForwardNavigationTrackingIfOwned(by: webView)
            break
        }

        tab.loadingState = .didFailProvisionalNavigation(error)
        tab.navigationRuntime.webViewRouting.pagePresentationDidChange(
            tab.id,
            webView
        )
        tab.updateNavigationState()
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(tab, [.loading])
        settleSuspendedRestoreFailureIfNeeded(
            tab: tab,
            webView: webView,
            wasFallback: wasRestoreFallback,
            shouldSubmitFallback: shouldSubmitRestoreFallback
        )
    }

    private func settleSuspendedRestoreFailureIfNeeded(
        tab: Tab,
        webView: WKWebView,
        wasFallback: Bool,
        shouldSubmitFallback: Bool
    ) {
        if wasFallback {
            guard tab.suspensionState.failFallback() else { return }
            tab.isRestoreFailure = true
            tab.restoreFailureDestination = tab.mainFrameLoads.currentIntent.targetURL
            tab.restoreFailureRawDestination =
                tab.mainFrameLoads.currentIntent.targetURL.absoluteString
            tab.loadingState = .idle
            tab.navigationRuntime.webViewRouting.pagePresentationDidChange(
                tab.id,
                webView
            )
            return
        }
        guard shouldSubmitFallback,
              let residence = tab.webViewSession.residence(of: webView) else {
            return
        }
        _ = NormalTabInitialDocumentRuntimeHandoff.submitRestoreFallback(
            tab: tab,
            webView: webView,
            expectedResidence: residence,
            intentRevision: tab.mainFrameLoads.currentIntent.revision
        )
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
            settleAbortedNavigationPresentation(
                tab,
                on: termination.webView
            )
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
        let snapshot = pageRecoverySnapshot(for: tab, webView: webView)
        let recoveryPlan = recovery.beginRecovery(
            on: webView,
            snapshot: snapshot
        )
        if let continuation = recoveryPlan.authorityContinuation {
            TabMainFrameLifecycleReducer.replayIfNeeded(
                continuation,
                tab: tab,
                promotion: promotion
            )
        }
        tab.finishBackForwardNavigationTrackingIfOwned(by: webView)

        switch recoveryPlan.disposition {
        case .duplicate:
            if tab.webContentRecoveryMarkers.recoveryState(on: webView)?
                .isFailure == true {
                settleRecoveryFailure(tab, on: webView)
            }
        case .failed:
            settleRecoveryFailure(tab, on: webView)
        case .pendingActivation, .deliver:
            _ = tab.navigationRuntime.webViewRouting
                .recoverWebContentProcess(tab.id, webView)
        }
    }

    private func pageRecoverySnapshot(
        for tab: Tab,
        webView: WKWebView
    ) -> PageRecoverySessionSnapshot? {
        guard let residence = tab.webViewSession.residence(of: webView),
              let committedRevision = tab.committedDocumentRuntime
                .lease(for: webView)?.revision,
              let data = SumiWebKitPageStateAdapter.sessionStateData(from: webView)
        else { return nil }
        return PageRecoverySessionSnapshot(
            residence: residence,
            residenceGeneration: tab.webViewSession.generation,
            profileID: tab.resolveProfile()?.id,
            dataStoreIdentity: PageSessionDataStoreIdentity(
                webView.configuration.websiteDataStore
            ),
            committedRevision: committedRevision,
            destination: tab.url,
            data: data
        )
    }

    private func settleRecoveryFailure(_ tab: Tab, on webView: WKWebView) {
        tab.loadingState = .idle
        tab.navigationRuntime.webViewRouting.pagePresentationDidChange(
            tab.id,
            webView
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
        let targetURL = context.url ?? context.action?.request.url
        return tab.beginMainFrameLifecycle(
            from: webView,
            navigationID: context.navigationID,
            navigationLifetime: context.navigationLifetime,
            targetURL: targetURL,
            blankAdmission: blankAdmission(
                for: targetURL,
                context: context,
                tab: tab
            ),
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

    private func blankAdmission(
        for targetURL: URL?,
        context: SumiNavigationContext,
        tab: Tab
    ) -> BlankDocumentAdmission? {
        guard targetURL?.isSumiBlankDocumentURL == true else { return nil }
        guard let action = context.action else { return nil }
        let sourceURL = action.sourceFrame?.url
        let source: BlankDocumentAdmission.Source
        if action.navigationType.isBackForward {
            source = .history
        } else if tab.isPopupHost {
            source = .popup(openerPageID: nil, origin: sourceURL)
        } else if action.isUserInitiated {
            source = .explicitUserCommand
        } else if sourceURL != nil {
            source = .siteNavigation(origin: sourceURL)
        } else {
            return nil
        }
        return BlankDocumentAdmission(id: UUID(), source: source)
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

    private func settleAbortedNavigationPresentation(
        _ tab: Tab,
        on webView: WKWebView
    ) {
        if tab.loadingState.isLoading {
            tab.loadingState = .idle
        }
        tab.navigationRuntime.webViewRouting.pagePresentationDidChange(
            tab.id,
            webView
        )
        tab.applyCachedFaviconOrPlaceholder(for: tab.url)
        tab.refreshFaviconExtensionCache()
        tab.updateNavigationState()
        tab.stateChangeEmitter.postNavigationStateDidChange(for: tab)
        tab.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(tab)
        tab.navigationRuntime.extensionPropertiesRuntime.notifyTabPropertiesChanged(
            tab,
            [.URL, .loading]
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
