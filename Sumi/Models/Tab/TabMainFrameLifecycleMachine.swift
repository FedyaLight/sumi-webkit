import Foundation
import WebKit

/// Composes participant and authority transition appliers over one exact state
/// graph. It exposes lifecycle queries/settlements but does not itself sequence
/// registry and effect-ledger mutations.
@MainActor
final class TabMainFrameLifecycleMachine {
    private let participantTransitions: TabMainFrameParticipantTransitionApplier
    private let continuationTransitions: TabMainFrameContinuationTransitionApplier
    private let authorityTransitions: TabMainFrameAuthorityTransitionApplier
    let activeNavigation: TabMainFrameActiveNavigationSettlement
    let terminal: TabMainFrameTerminalSettlement
    let sameDocument: TabMainFrameSameDocumentSettlement
    let promotion: TabMainFramePromotionReplaySettlement

    init() {
        let participants = TabMainFrameParticipantRegistry()
        let authorityState = TabMainFrameAuthorityState()
        let authorityEffects = TabMainFrameAuthorityEffectLedger()
        let participantEffects = TabMainFrameParticipantEffectLedger()
        let committer = TabMainFrameTransitionCommitter.lifecycleComposition(
            participants: participants,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            participantEffects: participantEffects
        )
        let participantTransitions = TabMainFrameParticipantTransitionApplier(
            participants: participants,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            participantEffects: participantEffects
        )
        self.participantTransitions = participantTransitions
        self.continuationTransitions = TabMainFrameContinuationTransitionApplier(
            participants: participants,
            authorityState: authorityState,
            committer: committer
        )
        self.authorityTransitions = TabMainFrameAuthorityTransitionApplier(
            participants: participants,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            participantEffects: participantEffects
        )
        let completedAuthority = TabMainFrameCompletedAuthorityProof(
            participants: participants,
            authorityState: authorityState
        )
        let terminal = TabMainFrameTerminalSettlement(
            participants: participants,
            authorityEffects: authorityEffects,
            completedAuthority: completedAuthority,
            committer: committer
        )
        self.activeNavigation = TabMainFrameActiveNavigationSettlement(
            participantTransitions: participantTransitions,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            committer: committer
        )
        self.terminal = terminal
        self.sameDocument = TabMainFrameSameDocumentSettlement(
            participants: participants,
            participantEffects: participantEffects,
            completedAuthority: completedAuthority,
            committer: committer
        )
        self.promotion = TabMainFramePromotionReplaySettlement(
            participants: participants,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            terminal: terminal
        )
    }

    var documentGeneration: UInt64 {
        participantTransitions.documentGeneration
    }

    func resetForNewIntent() {
        participantTransitions.resetForNewIntent()
    }

    func hasParticipant(on webView: WKWebView, revision: UInt64) -> Bool {
        participantTransitions.hasParticipant(on: webView, revision: revision)
    }

    func hasLiveAuthority(revision: UInt64) -> Bool {
        participantTransitions.hasLiveAuthority(revision: revision)
    }

    func authorityState(
        revision: UInt64
    ) -> TabMainFrameIntentLedger.AuthorityState? {
        participantTransitions.authority(revision: revision)
    }

    func activateSubmission(
        _ binding: TabMainFrameIntentLedger.SubmissionBinding,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        participantTransitions.activateSubmission(
            binding,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        )
    }

    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        participantTransitions.semanticRevision(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func loadingWebViews(revision: UInt64) -> [WKWebView] {
        participantTransitions.loadingWebViews(revision: revision)
    }

    func activeAttemptOwner(
        on webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFramePendingAttemptOwner? {
        participantTransitions.activeAttemptOwner(
            on: webView,
            currentIntent: currentIntent
        )
    }

    func routeLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL,
        continuationKind: TabMainFrameContinuationKind?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleRouting {
        continuationTransitions.routeLifecycle(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            continuationKind: continuationKind,
            currentIntent: currentIntent
        )
    }

    func startLifecycleOwnedIntent(
        _ intent: TabMainFrameNavigationIntent,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) {
        participantTransitions.startLifecycleOwnedIntent(
            intent,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func lifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        participantTransitions.lifecycleRole(
            from: webView,
            navigationID: navigationID,
            isCurrent: isCurrent,
            currentIntent: currentIntent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        participantTransitions.prepareAuthorityForCommit(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        )
    }

    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        participantTransitions.recordResponse(
            isPDF: isPDF,
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        )
    }

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool? {
        participantTransitions.responseIsPDF(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        )
    }

    func departure(
        of webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleDeparture {
        departure(of: [webView], currentIntent: currentIntent)
    }

    func departure(
        of webViews: [WKWebView],
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleDeparture {
        participantTransitions.departure(
            of: webViews,
            currentIntent: currentIntent
        )
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.LifecycleAbort {
        switch participantTransitions.abortNavigation(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        ) {
        case .ignored: return .ignored
        case .participant: return .participant
        case .authority:
            return .authority(promoteAuthorityCandidate(
                preferredWebViewID: nil,
                currentIntent: currentIntent
            ))
        }
    }

    func promoteAuthorityCandidate(
        preferredWebViewID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.AuthorityPromotion? {
        authorityTransitions.promoteAuthorityCandidate(
            preferredWebViewID: preferredWebViewID,
            currentIntent: currentIntent
        )
    }

    func documentEvidence(
        for webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> (evidence: TabCommittedDocumentEvidence, isAuthority: Bool)? {
        authorityTransitions.documentEvidence(
            for: webView,
            currentIntent: currentIntent
        )
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.Rehydration {
        authorityTransitions.rehydrate(
            candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID,
            intent: intent
        )
    }
}
