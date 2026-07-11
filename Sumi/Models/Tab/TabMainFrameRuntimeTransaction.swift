import Foundation
import SumiWebRuntime
import WebKit

@MainActor
protocol TabWebContentRecovery: AnyObject {
    func beginRecovery(on webView: WKWebView) -> TabWebContentProcessRecoveryPlan
    func isRecoveryRequired(on webView: WKWebView) -> Bool
}

/// Atomic boundary for main-frame transitions that change more than one
/// authority. `Tab` exposes narrow load, submission, document, and recovery
/// capabilities; lifecycle settlement is injected into its WebKit responder.
/// Only this transaction can replace intent or settle lifecycle authority.
@MainActor
final class TabMainFrameRuntimeTransaction:
    TabMainFrameSubmissionSettlement,
    TabMainFrameLifecycleSettlement,
    TabMainFramePromotionSettlement,
    TabWebContentRecovery
{
    struct LifecycleAcceptance {
        let role: TabMainFrameLifecycleRole
        let beganNewIntent: Bool
    }

    struct FailedSubmissionRollback {
        let targetURL: URL
        let navigationStateSource: WKWebView?
    }

    let mainFrameLoads: TabMainFrameLoadRuntime
    private let lifecycle: TabMainFrameLifecycleMachine
    let committedDocumentRuntime: TabCommittedDocumentRuntime
    private let recoveryMarkers: TabWebContentRecoveryMarkerLedger

    init(initialURL: URL) {
        let lifecycle = TabMainFrameLifecycleMachine()
        let mainFrameLoads = TabMainFrameLoadRuntime(
            initialURL: initialURL,
            lifecycle: lifecycle
        )
        self.mainFrameLoads = mainFrameLoads
        self.lifecycle = lifecycle
        self.committedDocumentRuntime = TabCommittedDocumentRuntime(
            initialURL: initialURL,
            evidenceSource: mainFrameLoads
        )
        self.recoveryMarkers = TabWebContentRecoveryMarkerLedger()
    }

    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        lifecycle.semanticRevision(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func beginExplicitIntent(to targetURL: URL) -> TabMainFrameNavigationIntent {
        let intent = mainFrameLoads.beginExplicitIntent(to: targetURL)
        lifecycle.resetForNewIntent()
        return intent
    }

    func bindSubmittedLoad(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        matching lease: TabMainFrameSubmissionLease?
    ) -> Bool {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let binding = mainFrameLoads.consumeSubmittedLoad(
                  on: webView,
                  matching: lease
              ) else {
            return false
        }
        guard lifecycle.activateSubmission(
            binding,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: mainFrameLoads.currentIntent
        ) else {
            return false
        }
        recoveryMarkers.clear(on: webView)
        return true
    }

    func failSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> TabMainFrameNavigationAbortResult {
        committedDocumentRuntime.performTransition(
            reason: .submissionFailure
        ) {
            let failure = mainFrameLoads.failSubmittedLoad(
                on: webView,
                matching: lease
            )
            guard failure.removedSubmission else { return .ignored }
            guard failure.wasAuthorityCandidate else { return .participant }
            if let continuation = promoteAuthority(
                preferredWebViewID: nil
            ) {
                return .authoritativeContinuation(continuation)
            }
            return .authoritativeTerminated
        }
    }

    func restoreDeferredLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease?
    ) {
        committedDocumentRuntime.performTransition(
            reason: .submissionFailure
        ) {
            let relinquishedAuthority = mainFrameLoads
                .restoreDeferredLoadAfterFailedSubmission(
                    on: webView,
                    revision: revision,
                    targetURL: targetURL,
                    matching: lease
                )
            if relinquishedAuthority {
                _ = promoteAuthority(
                    preferredWebViewID: nil
                )
            }
        }
    }

    func webViewsDidLeaveRuntime(
        _ webViews: [WKWebView],
        preferredAuthorityWebView: WKWebView?
    ) -> TabMainFrameRuntimeDepartureResult {
        committedDocumentRuntime.performTransition(
            reason: .replicaDeparture
        ) {
            var seen: Set<ObjectIdentifier> = []
            let departingWebViews = webViews.filter {
                seen.insert(ObjectIdentifier($0)).inserted
            }
            let departingWebViewIDs = Set(
                departingWebViews.map(ObjectIdentifier.init)
            )
            let preferredSurvivor = preferredAuthorityWebView.flatMap {
                departingWebViewIDs.contains(ObjectIdentifier($0)) ? nil : $0
            }

            departingWebViews.forEach { recoveryMarkers.clear(on: $0) }
            committedDocumentRuntime.removeWebViews(
                departingWebViews,
                preferredSourceWebView: preferredSurvivor
            )
            let pendingDeparture = mainFrameLoads.departure(of: departingWebViews)
            let lifecycleDeparture = lifecycle.departure(
                of: departingWebViews,
                currentIntent: mainFrameLoads.currentIntent
            )

            let wasAuthoritative = pendingDeparture.wasAuthorityCandidate
                || lifecycleDeparture.wasAuthoritative
            let continuation = wasAuthoritative
                ? promoteAuthority(
                    preferredWebViewID: preferredSurvivor.map(
                        ObjectIdentifier.init
                    )
                )
                : nil
            return TabMainFrameRuntimeDepartureResult(
                removedParticipant: pendingDeparture.removedLoad
                    || lifecycleDeparture.removedParticipant,
                wasAuthoritative: wasAuthoritative,
                continuation: continuation
            )
        }
    }

    func beginRecovery(
        on webView: WKWebView
    ) -> TabWebContentProcessRecoveryPlan {
        committedDocumentRuntime.performTransition(
            reason: .processRecovery
        ) {
            let intent = mainFrameLoads.currentIntent
            guard recoveryMarkers.markRequired(on: webView) else {
                return TabWebContentProcessRecoveryPlan(
                    scope: .replica(intent),
                    authorityContinuation: nil
                )
            }

            committedDocumentRuntime.removeWebView(webView)
            let pendingDeparture = mainFrameLoads.departure(of: webView)
            let lifecycleDeparture = lifecycle.departure(
                of: webView,
                currentIntent: intent
            )
            var continuation: TabMainFrameAuthorityContinuation?
            if pendingDeparture.wasAuthorityCandidate
                || lifecycleDeparture.wasAuthoritative
                || hasCurrentAuthority() == false {
                continuation = promoteAuthority(
                    preferredWebViewID: nil
                )
            }

            let scope: TabWebContentProcessRecoveryScope = hasCurrentAuthority()
                ? .replica(mainFrameLoads.currentIntent)
                : .global(mainFrameLoads.currentIntent.targetURL)
            return TabWebContentProcessRecoveryPlan(
                scope: scope,
                authorityContinuation: continuation
            )
        }
    }

    func isRecoveryRequired(on webView: WKWebView) -> Bool {
        recoveryMarkers.isRecoveryRequired(on: webView)
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        survivingCommittedURL: URL?,
        rollsBackWhenUnreplaced: Bool
    ) -> TabMainFrameNavigationAbortResult {
        committedDocumentRuntime.performTransition(
            reason: .navigationAbort
        ) {
            if let survivingCommittedURL {
                committedDocumentRuntime.noteSurvivingDocument(
                    on: webView,
                    committedURL: survivingCommittedURL
                )
            }
            switch lifecycle.abortNavigation(
                from: webView,
                navigationID: navigationID,
                navigationLifetime: navigationLifetime,
                currentIntent: mainFrameLoads.currentIntent
            ) {
            case .ignored:
                return .ignored
            case .participant:
                return .participant
            case .authority(let promotion):
                if let continuation = apply(promotion)
                    ?? promoteAuthority(
                        preferredWebViewID: nil
                    ) {
                    return .authoritativeContinuation(continuation)
                }
                guard rollsBackWhenUnreplaced else {
                    return .authoritativeTerminated
                }
                return .authoritativeRollback(
                    applyDurableDocumentRollback()
                )
            }
        }
    }

    func beginLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        navigationLifetime: AnyObject,
        targetURL: URL?,
        allowsUserInitiatedSupersession: Bool,
        continuationKind: TabMainFrameContinuationKind?
    ) -> LifecycleAcceptance {
        guard let navigationID, let targetURL else {
            return LifecycleAcceptance(role: .stale, beganNewIntent: false)
        }
        switch lifecycle.routeLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            continuationKind: continuationKind,
            currentIntent: mainFrameLoads.currentIntent
        ) {
        case .retired:
            return LifecycleAcceptance(role: .stale, beganNewIntent: false)
        case .accepted(let role, let targetURLToAdopt):
            if let targetURLToAdopt {
                mainFrameLoads.updateTargetWithinRevision(targetURLToAdopt)
                if continuationKind == .sameDocument,
                   committedDocumentRuntime.lease(for: webView) != nil {
                    committedDocumentRuntime.performTransition(reason: .sameDocumentPresentation) {
                        committedDocumentRuntime.updatePresentation(
                            targetURLToAdopt,
                            on: webView
                        )
                    }
                }
            }
            recoveryMarkers.clear(on: webView)
            return LifecycleAcceptance(role: role, beganNewIntent: false)
        case .unmatched:
            break
        }

        guard mainFrameLoads.canStartUnboundLifecycle(
            on: webView,
            allowsUserInitiatedSupersession: allowsUserInitiatedSupersession
        ) else {
            return LifecycleAcceptance(role: .stale, beganNewIntent: false)
        }

        let intent = mainFrameLoads.beginLifecycleIntent(to: targetURL)
        lifecycle.resetForNewIntent()
        lifecycle.startLifecycleOwnedIntent(
            intent,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
        recoveryMarkers.clear(on: webView)
        return LifecycleAcceptance(role: .authority, beganNewIntent: true)
    }

    func role(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> TabMainFrameLifecycleRole {
        lifecycle.lifecycleRole(
            from: webView,
            navigationID: navigationID,
            isCurrent: isCurrent,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        lifecycle.prepareAuthorityForCommit(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        lifecycle.claimTransactionStartEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        lifecycle.claimAuthorityTargetPreparation(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameEffectDecision<URL> {
        lifecycle.claimLocalStartEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func remainsCurrent(_ lease: TabMainFrameActiveAuthorityLease) -> Bool {
        lifecycle.remainsCurrent(
            lease,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimSharedFinishEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        lifecycle.claimSharedFinishEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimSharedFinishEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        lifecycle.claimPromotedSharedFinishEffects(
            matching: continuation,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func remainsCurrent(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        lifecycle.remainsCurrent(
            continuation,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func noteResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) {
        _ = lifecycle.recordResponse(
            isPDF: isPDF,
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func finish(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) {
        lifecycle.finishLifecycle(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func settleCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL
    ) -> TabMainFrameCommitDecision {
        let isPDF = lifecycle.responseIsPDF(
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        ) ?? false
        let transition = committedDocumentRuntime.performTransition(
            reason: .documentCommit
        ) {
            let transition = lifecycle.recordCommit(
                from: webView,
                navigationID: navigationID,
                committedURL: committedURL,
                isPDF: isPDF,
                currentIntent: mainFrameLoads.currentIntent
            )
            if let evidence = transition.evidence {
                committedDocumentRuntime.recordCommit(
                    evidence,
                    publishesCanonicalDocument: transition.publication != nil
                )
            }
            return transition
        }
        switch transition.role {
        case .stale:
            return .stale
        case .participant:
            return .recordedReplica
        case .authority where transition.publication == nil:
            return .alreadyPublished
        case .authority:
            guard let publication = transition.publication else {
                return .alreadyPublished
            }
            return .publish(publication)
        }
    }

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication
    ) -> Bool {
        lifecycle.consumeCommitPublication(
            publication,
            currentIntent: mainFrameLoads.currentIntent
        )
    }

    func claimAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool
    ) -> TabMainFrameLifecycleRole {
        committedDocumentRuntime.performTransition(
            reason: .terminalSuccess
        ) {
            let transition = lifecycle.claimAuthorityForTerminalSuccess(
                from: webView,
                navigationID: navigationID,
                terminalURL: terminalURL,
                completesDocumentNavigation: completesDocumentNavigation,
                currentIntent: mainFrameLoads.currentIntent
            )
            if let evidence = transition.evidence {
                committedDocumentRuntime.recordReplica(evidence)
            }
            if let presentationURL = transition.presentationURLToAdopt {
                committedDocumentRuntime.updatePresentation(
                    presentationURL,
                    on: webView
                )
            }
            return transition.role
        }
    }

    func claimSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        committedDocumentRuntime.performTransition(
            reason: .authorityPromotion
        ) {
            guard let evidence = lifecycle.claimPromotedSharedCommitEffects(
                matching: continuation,
                currentIntent: mainFrameLoads.currentIntent
            ) else {
                return false
            }
            committedDocumentRuntime.adoptCanonicalDocument(evidence)
            return true
        }
    }

    func acceptPromotedAuthorityTarget(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        let accepted = lifecycle.acceptPromotedTarget(
            targetURL,
            matching: continuation,
            currentIntent: mainFrameLoads.currentIntent
        ) || mainFrameLoads.isCurrentPendingAuthority(continuation)
        guard accepted else { return false }
        mainFrameLoads.updateTargetWithinRevision(targetURL)
        return true
    }

    func acceptLifecycleTarget(
        _ targetURL: URL,
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) -> Bool {
        guard lifecycle.acceptLifecycleTarget(
            targetURL,
            from: webView,
            navigationID: navigationID,
            currentIntent: mainFrameLoads.currentIntent
        ) else {
            return false
        }
        mainFrameLoads.updateTargetWithinRevision(targetURL)
        return true
    }

    func rollbackToDurableDocument() -> URL {
        committedDocumentRuntime.performTransition(
            reason: .navigationCancel
        ) {
            applyDurableDocumentRollback()
        }
    }

    private func applyDurableDocumentRollback() -> URL {
        let snapshot = committedDocumentRuntime.prepareRollbackSnapshot()
        let intent = mainFrameLoads.beginRollbackIntent(to: snapshot.targetURL)
        lifecycle.resetForNewIntent()
        let rehydration = lifecycle.rehydrate(
            snapshot.candidates,
            preferredAuthorityWebViewID: snapshot.preferredAuthorityWebViewID,
            intent: intent
        )
        committedDocumentRuntime.adoptRehydratedEvidence(
            rehydration.evidence,
            authorityWebViewID: rehydration.authorityWebViewID
        )
        return snapshot.targetURL
    }

    func rollbackAfterFailedSubmission(
        survivingWebViews: [WKWebView]
    ) -> FailedSubmissionRollback {
        committedDocumentRuntime.performTransition(
            reason: .submissionFailure
        ) {
            for webView in survivingWebViews {
                guard let committedURL = webView.committedURL else { continue }
                committedDocumentRuntime.noteSurvivingDocument(
                    on: webView,
                    committedURL: committedURL
                )
            }
            let navigationStateSource = committedDocumentRuntime.sourceWebView()
            return FailedSubmissionRollback(
                targetURL: applyDurableDocumentRollback(),
                navigationStateSource: navigationStateSource
            )
        }
    }

    private func hasCurrentAuthority() -> Bool {
        lifecycle.hasLiveAuthority(revision: mainFrameLoads.currentIntent.revision)
            || mainFrameLoads.hasPendingAuthority
    }

    private func promoteAuthority(
        preferredWebViewID: ObjectIdentifier?
    ) -> TabMainFrameAuthorityContinuation? {
        if let promotion = lifecycle.promoteAuthorityCandidate(
            preferredWebViewID: preferredWebViewID,
            currentIntent: mainFrameLoads.currentIntent
        ) {
            return apply(promotion)
        }
        return mainFrameLoads.promoteSubmittedAuthority(
            preferredWebViewID: preferredWebViewID
        )
    }

    private func apply(
        _ promotion: TabMainFrameAuthorityPromotion?
    ) -> TabMainFrameAuthorityContinuation? {
        guard let promotion else { return nil }
        committedDocumentRuntime.recordReplicas(promotion.migratedEvidence)
        if let targetURL = promotion.targetURLToAdopt {
            mainFrameLoads.updateTargetWithinRevision(targetURL)
        }
        return promotion.continuation
    }
}
