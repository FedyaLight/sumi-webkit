import Foundation
import WebKit

/// Aggregate boundary for a tab's main-frame runtime. The tab never retains or
/// mutates the intent, lifecycle, durable-document, or recovery components
/// independently, so cross-component invariants cannot be bypassed.
@MainActor
final class TabMainFrameRuntimeTransaction {
    struct LifecycleAcceptance {
        let role: TabMainFrameLifecycleRole
        let beganNewIntent: Bool
    }

    struct FailedSubmissionRollback {
        let targetURL: URL
        let navigationStateSource: WKWebView?
    }

    private let intentLedger: TabMainFrameIntentLedger
    private let lifecycle: TabMainFrameLifecycleMachine
    private let committedDocuments: TabCommittedDocumentLedger
    private let recovery: TabWebContentRecoveryPlanner

    init(initialURL: URL) {
        self.intentLedger = TabMainFrameIntentLedger(initialURL: initialURL)
        self.lifecycle = TabMainFrameLifecycleMachine()
        self.committedDocuments = TabCommittedDocumentLedger(
            initialURL: initialURL
        )
        self.recovery = TabWebContentRecoveryPlanner()
    }

    func beginRebuildIntent() -> UInt64 {
        intentLedger.beginRebuildIntent()
    }

    var rebuildIntentRevision: UInt64 {
        intentLedger.rebuildIntentRevision
    }

    func currentIntent(
        matching targetURL: URL
    ) -> TabMainFrameNavigationIntent? {
        intentLedger.current(matching: targetURL)
    }

    var currentIntent: TabMainFrameNavigationIntent {
        intentLedger.intent
    }

    func currentIntent(
        revision: UInt64
    ) -> TabMainFrameNavigationIntent? {
        intentLedger.current(revision: revision)
    }

    func isCurrentIntent(_ intent: TabMainFrameNavigationIntent) -> Bool {
        intentLedger.isCurrent(intent)
    }

    func isCurrentIntent(revision: UInt64, targetURL: URL) -> Bool {
        intentLedger.isCurrent(revision: revision, targetURL: targetURL)
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

    func submittedLease(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabMainFrameSubmissionLease? {
        intentLedger.submittedLease(
            on: webView,
            revision: revision,
            targetURL: targetURL
        )
    }

    func finishPreparedLoad(_ ticket: TabMainFramePreparedLoadTicket) {
        intentLedger.finishPreparedLoad(ticket)
    }

    func clearDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) {
        intentLedger.clearDeferredLoad(on: webView, intent: intent)
    }

    func hasOutstandingLoad(on webView: WKWebView, targetURL: URL) -> Bool {
        intentLedger.hasOutstandingLoad(on: webView, targetURL: targetURL)
            || lifecycle.loadingWebViews(
                revision: intentLedger.intent.revision
            ).contains(where: { $0 === webView })
    }

    func beginExplicitIntent(to targetURL: URL) -> TabMainFrameNavigationIntent {
        let intent = intentLedger.beginExplicitIntent(to: targetURL)
        lifecycle.resetForNewIntent()
        return intent
    }

    func beginPreparedLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFramePreparedLoadTicket? {
        intentLedger.beginPreparedLoad(
            on: webView,
            intent: intent,
            documentGeneration: lifecycle.documentGeneration,
            hasLifecycleParticipant: lifecycle.hasParticipant(
                on: webView,
                revision: intent.revision
            )
        )
    }

    func markDeferredLoad(
        on webView: WKWebView,
        intent: TabMainFrameNavigationIntent
    ) -> Bool {
        let authority = lifecycle.authorityState(revision: intent.revision)
        return intentLedger.markDeferredLoad(
            on: webView,
            intent: intent,
            documentGeneration: lifecycle.documentGeneration,
            isLifecycleAuthority: authority?.webViewID
                == ObjectIdentifier(webView)
        )
    }

    func claimDirectSubmission(
        on webView: WKWebView
    ) -> TabMainFrameSubmissionLease? {
        intentLedger.claimDirectSubmission(
            on: webView,
            documentGeneration: lifecycle.documentGeneration,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: intentLedger.intent.revision
            )
        )
    }

    func claimDeferredSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL
    ) -> TabDeferredMainFrameLoadClaim {
        intentLedger.claimDeferredSubmission(
            on: webView,
            revision: revision,
            targetURL: targetURL,
            hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                revision: intentLedger.intent.revision
            )
        )
    }

    func bindSubmittedLoad(
        on webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        matching lease: TabMainFrameSubmissionLease?
    ) -> Bool {
        guard ObjectIdentifier(navigationLifetime) == navigationID,
              let binding = intentLedger.consumeSubmittedLoad(
                  on: webView,
                  matching: lease,
                  hasLifecycleAuthority: lifecycle.hasLiveAuthority(
                      revision: intentLedger.intent.revision
                  )
              ) else {
            return false
        }
        guard lifecycle.activateSubmission(
            binding,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: intentLedger.intent
        ) else {
            return false
        }
        recovery.finish(on: webView)
        return true
    }

    func failSubmittedLoad(
        on webView: WKWebView,
        matching lease: TabMainFrameSubmissionLease?
    ) -> TabMainFrameNavigationAbortResult {
        let failure = intentLedger.failSubmittedLoad(
            on: webView,
            matching: lease
        )
        guard failure.removedSubmission else { return .ignored }
        guard failure.wasAuthorityCandidate else { return .participant }
        if let continuation = promoteAuthority(preferredWebViewID: nil) {
            return .authoritativeContinuation(continuation)
        }
        return .authoritativeTerminated
    }

    func restoreDeferredLoadAfterFailedSubmission(
        on webView: WKWebView,
        revision: UInt64,
        targetURL: URL,
        matching lease: TabMainFrameSubmissionLease?
    ) {
        let relinquishedAuthority = intentLedger
            .restoreDeferredLoadAfterFailedSubmission(
                on: webView,
                revision: revision,
                targetURL: targetURL,
                matching: lease
            )
        if relinquishedAuthority {
            _ = promoteAuthority(preferredWebViewID: nil)
        }
    }

    func webViewDidLeaveRuntime(
        _ webView: WKWebView,
        preferredAuthorityWebView: WKWebView?
    ) -> TabMainFrameRuntimeDepartureResult {
        recovery.remove(webView)
        committedDocuments.removeWebView(webView)
        let pendingDeparture = intentLedger.departure(of: webView)
        let lifecycleDeparture = lifecycle.departure(
            of: webView,
            preferredAuthorityWebView: preferredAuthorityWebView,
            currentIntent: intentLedger.intent
        )

        let wasAuthoritative = pendingDeparture.wasAuthorityCandidate
            || lifecycleDeparture.wasAuthoritative
        var continuation = apply(lifecycleDeparture.promotion)
        if wasAuthoritative && continuation == nil {
            continuation = promoteAuthority(
                preferredWebViewID: preferredAuthorityWebView.map(
                    ObjectIdentifier.init
                )
            )
        }
        return TabMainFrameRuntimeDepartureResult(
            removedParticipant: pendingDeparture.removedLoad
                || lifecycleDeparture.removedParticipant,
            wasAuthoritative: wasAuthoritative,
            continuation: continuation
        )
    }

    func beginWebContentProcessRecovery(
        on webView: WKWebView
    ) -> TabWebContentProcessRecoveryPlan {
        let intent = intentLedger.intent
        guard recovery.markRequired(on: webView) else {
            return TabWebContentProcessRecoveryPlan(
                scope: .replica(intent),
                authorityContinuation: nil
            )
        }

        committedDocuments.removeWebView(webView)
        let pendingDeparture = intentLedger.departure(of: webView)
        let lifecycleDeparture = lifecycle.departure(
            of: webView,
            preferredAuthorityWebView: nil,
            currentIntent: intent
        )
        var continuation = apply(lifecycleDeparture.promotion)
        if pendingDeparture.wasAuthorityCandidate
            || lifecycleDeparture.wasAuthoritative
            || hasCurrentAuthority() == false {
            continuation = continuation
                ?? promoteAuthority(preferredWebViewID: nil)
        }

        let scope: TabWebContentProcessRecoveryScope = hasCurrentAuthority()
            ? .replica(intentLedger.intent)
            : .global(intentLedger.intent.targetURL)
        return TabWebContentProcessRecoveryPlan(
            scope: scope,
            authorityContinuation: continuation
        )
    }

    func requiresWebContentProcessRecovery(on webView: WKWebView) -> Bool {
        recovery.requiresRecovery(on: webView)
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        survivingCommittedURL: URL?,
        rollsBackWhenUnreplaced: Bool
    ) -> TabMainFrameNavigationAbortResult {
        if let survivingCommittedURL {
            committedDocuments.noteSurvivingDocument(
                on: webView,
                committedURL: survivingCommittedURL
            )
        }
        switch lifecycle.abortNavigation(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: intentLedger.intent
        ) {
        case .ignored:
            return .ignored
        case .participant:
            return .participant
        case .authority(let promotion):
            if let continuation = apply(promotion)
                ?? promoteAuthority(preferredWebViewID: nil) {
                return .authoritativeContinuation(continuation)
            }
            guard rollsBackWhenUnreplaced else {
                return .authoritativeTerminated
            }
            return .authoritativeRollback(rollbackToDurableDocument())
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
            currentIntent: intentLedger.intent
        ) {
        case .retired:
            return LifecycleAcceptance(role: .stale, beganNewIntent: false)
        case .accepted(let role, let targetURLToAdopt):
            if let targetURLToAdopt {
                intentLedger.updateTargetWithinRevision(targetURLToAdopt)
            }
            recovery.finish(on: webView)
            return LifecycleAcceptance(role: role, beganNewIntent: false)
        case .unmatched:
            break
        }

        let authorityState = lifecycle.authorityState(
            revision: intentLedger.intent.revision
        )
        guard intentLedger.canStartUnboundLifecycle(
            on: webView,
            allowsUserInitiatedSupersession: allowsUserInitiatedSupersession,
            lifecycleAuthority: authorityState,
            hasLifecycleParticipant: lifecycle.hasParticipant(
                on: webView,
                revision: intentLedger.intent.revision
            )
        ) else {
            return LifecycleAcceptance(role: .stale, beganNewIntent: false)
        }

        let intent = intentLedger.beginLifecycleIntent(to: targetURL)
        lifecycle.resetForNewIntent()
        lifecycle.startLifecycleOwnedIntent(
            intent,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
        recovery.finish(on: webView)
        return LifecycleAcceptance(role: .authority, beganNewIntent: true)
    }

    func lifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?
    ) -> TabMainFrameLifecycleRole {
        lifecycle.lifecycleRole(
            from: webView,
            navigationID: navigationID,
            isCurrent: isCurrent,
            currentIntent: intentLedger.intent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        lifecycle.prepareAuthorityForCommit(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        lifecycle.claimTransactionStartEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        lifecycle.claimAuthorityTargetPreparation(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        lifecycle.claimLocalStartEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func claimSharedFinishEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool {
        lifecycle.claimSharedFinishEffects(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func claimPromotedSharedFinishEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        lifecycle.claimPromotedSharedFinishEffects(
            matching: continuation,
            currentIntent: intentLedger.intent
        )
    }

    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> TabMainFrameLifecycleRole {
        lifecycle.recordResponse(
            isPDF: isPDF,
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier
    ) -> Bool? {
        lifecycle.responseIsPDF(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func finishLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?
    ) {
        lifecycle.finishLifecycle(
            from: webView,
            navigationID: navigationID,
            currentIntent: intentLedger.intent
        )
    }

    func recordCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool
    ) -> TabMainFrameCommitSnapshotClaim {
        let transition = lifecycle.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: isPDF,
            currentIntent: intentLedger.intent
        )
        if let evidence = transition.evidence {
            committedDocuments.recordReplica(evidence)
            if transition.claim.shouldPublishSharedEffects {
                committedDocuments.adoptCanonicalDocument(evidence)
            }
        }
        return transition.claim
    }

    func claimAuthorityForTerminalSuccess(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        terminalURL: URL?,
        completesDocumentNavigation: Bool
    ) -> TabMainFrameLifecycleRole {
        let transition = lifecycle.claimAuthorityForTerminalSuccess(
            from: webView,
            navigationID: navigationID,
            terminalURL: terminalURL,
            completesDocumentNavigation: completesDocumentNavigation,
            currentIntent: intentLedger.intent
        )
        if let evidence = transition.evidence {
            committedDocuments.recordReplica(evidence)
        }
        if let presentationURL = transition.presentationURLToAdopt {
            committedDocuments.updatePresentation(presentationURL, on: webView)
        }
        return transition.role
    }

    func claimPromotedSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        guard let evidence = lifecycle.claimPromotedSharedCommitEffects(
            matching: continuation,
            currentIntent: intentLedger.intent
        ) else {
            return false
        }
        committedDocuments.adoptCanonicalDocument(evidence)
        return true
    }

    func acceptPromotedAuthorityTarget(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation
    ) -> Bool {
        let accepted = lifecycle.acceptPromotedTarget(
            targetURL,
            matching: continuation,
            currentIntent: intentLedger.intent
        ) || intentLedger.isCurrentPendingAuthority(continuation)
        guard accepted else { return false }
        intentLedger.updateTargetWithinRevision(targetURL)
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
            currentIntent: intentLedger.intent
        ) else {
            return false
        }
        intentLedger.updateTargetWithinRevision(targetURL)
        return true
    }

    func documentLease(for webView: WKWebView) -> TabMainFrameDocumentLease? {
        guard let proof = lifecycle.documentEvidence(
            for: webView,
            currentIntent: intentLedger.intent
        ) else {
            return nil
        }
        return committedDocuments.documentLease(
            matching: proof.evidence,
            isAuthority: proof.isAuthority
        )
    }

    func rollbackToDurableDocument() -> URL {
        let snapshot = committedDocuments.rollbackSnapshot()
        let intent = intentLedger.beginRollbackIntent(to: snapshot.targetURL)
        lifecycle.resetForNewIntent()
        let rehydration = lifecycle.rehydrate(
            snapshot.candidates,
            preferredAuthorityWebViewID: snapshot.preferredAuthorityWebViewID,
            intent: intent
        )
        committedDocuments.adoptRehydratedEvidence(
            rehydration.evidence,
            authorityWebViewID: rehydration.authorityWebViewID
        )
        return snapshot.targetURL
    }

    func rollbackAfterFailedSubmission(
        survivingWebViews: [WKWebView]
    ) -> FailedSubmissionRollback {
        for webView in survivingWebViews {
            guard let committedURL = webView.committedURL else { continue }
            committedDocuments.noteSurvivingDocument(
                on: webView,
                committedURL: committedURL
            )
        }
        let navigationStateSource = committedDocuments.sourceWebView()
        return FailedSubmissionRollback(
            targetURL: rollbackToDurableDocument(),
            navigationStateSource: navigationStateSource
        )
    }

    func loadingWebViews() -> [WKWebView] {
        let submitted = intentLedger.submittedWebViews()
        let active = lifecycle.loadingWebViews(
            revision: intentLedger.intent.revision
        )
        var seen = Set<ObjectIdentifier>()
        return (submitted + active).filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
    }

    private func hasCurrentAuthority() -> Bool {
        lifecycle.hasLiveAuthority(revision: intentLedger.intent.revision)
            || intentLedger.hasPendingAuthority()
    }

    private func promoteAuthority(
        preferredWebViewID: ObjectIdentifier?
    ) -> TabMainFrameAuthorityContinuation? {
        if let promotion = lifecycle.promoteAuthorityCandidate(
            preferredWebViewID: preferredWebViewID,
            currentIntent: intentLedger.intent
        ) {
            return apply(promotion)
        }
        return intentLedger.promoteSubmittedAuthority(
            preferredWebViewID: preferredWebViewID
        )
    }

    private func apply(
        _ promotion: TabMainFrameAuthorityPromotion?
    ) -> TabMainFrameAuthorityContinuation? {
        guard let promotion else { return nil }
        promotion.migratedEvidence.forEach(committedDocuments.recordReplica)
        if let targetURL = promotion.targetURLToAdopt {
            intentLedger.updateTargetWithinRevision(targetURL)
        }
        return promotion.continuation
    }
}
