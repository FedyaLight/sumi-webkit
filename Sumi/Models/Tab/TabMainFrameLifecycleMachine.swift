import Foundation
import SumiWebRuntime
import WebKit

struct TabMainFrameAuthorityPromotion {
    let continuation: TabMainFrameAuthorityContinuation
    let targetURLToAdopt: URL?
    let migratedEvidence: [TabCommittedDocumentEvidence]
}

enum TabMainFrameLifecycleRoutingResult {
    case accepted(role: TabMainFrameLifecycleRole, targetURLToAdopt: URL?)
    case unmatched
    case retired
}

struct TabMainFrameLifecycleDeparture {
    let removedParticipant: Bool
    let wasAuthoritative: Bool
}

enum TabMainFrameLifecycleAbortTransition {
    case ignored
    case participant
    case authority(TabMainFrameAuthorityPromotion?)
}

struct TabMainFrameRehydrationResult {
    let evidence: [TabCommittedDocumentEvidence]
    let authorityWebViewID: ObjectIdentifier?
}

/// Coordinates exact-navigation lifecycle routing, promotion and departure.
/// Publication settlement is exposed through cohesive active, terminal,
/// same-document and promotion components backed by the same state ledgers.
@MainActor
final class TabMainFrameLifecycleMachine {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityReducer: TabMainFrameAuthorityReducer
    private let effectClaims: TabMainFrameEffectLedger
    let activeNavigation: TabMainFrameActiveNavigationSettlement
    let terminal: TabMainFrameTerminalSettlement
    let sameDocument: TabMainFrameSameDocumentSettlement
    let promotion: TabMainFramePromotionReplaySettlement

    init() {
        let participants = TabMainFrameParticipantRegistry()
        let authorityState = TabMainFrameAuthorityState()
        let authorityReducer = TabMainFrameAuthorityReducer(
            authorityState: authorityState
        )
        let effectClaims = TabMainFrameEffectLedger()
        self.participants = participants
        self.authorityReducer = authorityReducer
        self.effectClaims = effectClaims
        let completedAuthority = TabMainFrameCompletedAuthorityProof(
            participants: participants,
            authorityState: authorityState,
            authorityReducer: authorityReducer
        )
        let terminal = TabMainFrameTerminalSettlement(
            participants: participants,
            authorityReducer: authorityReducer,
            effectClaims: effectClaims,
            completedAuthority: completedAuthority
        )
        self.activeNavigation = TabMainFrameActiveNavigationSettlement(
            participants: participants,
            authorityState: authorityState,
            authorityReducer: authorityReducer,
            effectClaims: effectClaims
        )
        self.terminal = terminal
        self.sameDocument = TabMainFrameSameDocumentSettlement(
            participants: participants,
            authorityReducer: authorityReducer,
            effectClaims: effectClaims,
            completedAuthority: completedAuthority
        )
        self.promotion = TabMainFramePromotionReplaySettlement(
            participants: participants,
            authorityReducer: authorityReducer,
            effectClaims: effectClaims,
            terminal: terminal
        )
    }

    var documentGeneration: UInt64 {
        authorityReducer.documentGeneration
    }

    func resetForNewIntent() {
        participants.removeAllForNewIntent().forEach(
            effectClaims.removeParticipant
        )
        authorityReducer.resetForNewIntent()
        effectClaims.resetForDocumentGeneration()
    }

    func hasParticipant(on webView: WKWebView, revision: UInt64) -> Bool {
        participants.contains(webView, revision: revision)
    }

    func hasLiveAuthority(revision: UInt64) -> Bool {
        authorityReducer.hasLiveAuthority(
            revision: revision,
            participants: participants
        )
    }

    func authorityState(
        revision: UInt64
    ) -> TabMainFrameIntentLedger.AuthorityState? {
        guard hasLiveAuthority(revision: revision),
              let authority = authorityReducer.authority else {
            return nil
        }
        return TabMainFrameIntentLedger.AuthorityState(
            webViewID: authority.webViewID,
            isCompleted: authority.isCompleted
        )
    }

    func activateSubmission(
        _ binding: TabMainFrameIntentLedger.SubmissionBinding,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard binding.revision == currentIntent.revision,
              let install = participants.installSubmission(
                  binding,
                  navigationID: navigationID,
                  navigationLifetime: navigationLifetime
              ) else {
            return false
        }
        if let replacedParticipantID = install.replacedParticipantID {
            effectClaims.removeParticipant(replacedParticipantID)
        }
        if binding.becomesAuthority {
            authorityReducer.installAuthority(
                revision: binding.revision,
                webViewID: binding.webViewID,
                documentGeneration: binding.documentGeneration,
                navigationID: navigationID
            )
        }
        return true
    }

    func semanticRevision(
        for webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) -> UInt64? {
        participants.semanticRevision(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime
        )
    }

    func loadingWebViews(revision: UInt64) -> [WKWebView] {
        participants.loadingWebViews(revision: revision)
    }

    func routeLifecycle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        targetURL: URL,
        continuationKind: TabMainFrameContinuationKind?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRoutingResult {
        guard participants.isRetiredNavigationIdentity(
            navigationID,
            lifetime: navigationLifetime
        ) == false else {
            return .retired
        }

        // WebKit may deliver the same terminal same-document callback more
        // than once. A completed physical navigation must never be reactivated
        // as its own continuation because that would reset one-shot permits.
        if participants.exactCompletedEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) != nil {
            return .retired
        }

        let webViewID = ObjectIdentifier(webView)
        let existingRole = lifecycleRole(
            webViewID: webViewID,
            navigationID: navigationID,
            currentIntent: currentIntent
        )
        if existingRole != .stale {
            participants.attachNavigationIdentityIfPossible(
                navigationID: navigationID,
                lifetime: navigationLifetime,
                webViewID: webViewID
            )
            return .accepted(role: existingRole, targetURLToAdopt: nil)
        }

        guard let continuationKind else { return .unmatched }
        let continuation = authorityReducer.transferToContinuation(
            webViewID: webViewID,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            targetURL: targetURL,
            kind: continuationKind,
            currentIntent: currentIntent,
            participants: participants,
            effectClaims: effectClaims
        )
        guard continuation.role != .stale else { return .unmatched }
        return .accepted(
            role: continuation.role,
            targetURLToAdopt: continuation.targetURLToAdopt
        )
    }

    func startLifecycleOwnedIntent(
        _ intent: TabMainFrameNavigationIntent,
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject
    ) {
        let webViewID = ObjectIdentifier(webView)
        let install = participants.installLifecycleOwnedEntry(
            intent: intent,
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            documentGeneration: documentGeneration
        )
        if let replacedParticipantID = install.replacedParticipantID {
            effectClaims.removeParticipant(replacedParticipantID)
        }
        authorityReducer.installAuthority(
            revision: intent.revision,
            webViewID: webViewID,
            documentGeneration: documentGeneration,
            navigationID: navigationID
        )
    }

    func lifecycleRole(
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        isCurrent: Bool?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        guard isCurrent != false, let navigationID else { return .stale }
        return lifecycleRole(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            currentIntent: currentIntent
        )
    }

    func prepareAuthorityForCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.claimDocumentAuthority(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    func recordResponse(
        isPDF: Bool,
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.recordResponse(
            isPDF: isPDF,
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.lifecycleRole(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }

    func responseIsPDF(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool? {
        participants.responseIsPDF(
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            revision: currentIntent.revision
        )
    }

    func departure(
        of webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleDeparture {
        departure(
            of: [webView],
            currentIntent: currentIntent
        )
    }

    func departure(
        of webViews: [WKWebView],
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleDeparture {
        let departingWebViewIDs = Set(webViews.compactMap { webView in
            participants.exactEntry(for: webView).map { _ in
                ObjectIdentifier(webView)
            }
        })
        let removed = participants.removeAll(webViews)
        removed.forEach { effectClaims.removeParticipant($0.id) }
        guard authorityReducer.removeAuthorityIfMatching(
            webViewIDs: departingWebViewIDs,
            revision: currentIntent.revision
        ) else {
            return TabMainFrameLifecycleDeparture(
                removedParticipant: removed.isEmpty == false,
                wasAuthoritative: false
            )
        }
        return TabMainFrameLifecycleDeparture(
            removedParticipant: removed.isEmpty == false,
            wasAuthoritative: true
        )
    }

    func abortNavigation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleAbortTransition {
        let webViewID = ObjectIdentifier(webView)
        let isAuthoritative = authorityReducer.isExactAuthority(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        )
        guard let participant = participants.removeExactActiveNavigation(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else {
            return .ignored
        }
        effectClaims.removeParticipant(participant.id)
        guard isAuthoritative else { return .participant }
        authorityReducer.clearAuthority()
        return .authority(promoteAuthorityCandidate(
            preferredWebViewID: nil,
            currentIntent: currentIntent
        ))
    }

    func promoteAuthorityCandidate(
        preferredWebViewID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameAuthorityPromotion? {
        authorityReducer.promoteAuthorityCandidate(
            participants: participants,
            effectClaims: effectClaims,
            preferredWebViewID: preferredWebViewID,
            currentIntent: currentIntent
        )
    }

    func documentEvidence(
        for webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> (evidence: TabCommittedDocumentEvidence, isAuthority: Bool)? {
        let webViewID = ObjectIdentifier(webView)
        guard let sharedCommitIdentity = effectClaims.sharedCommitIdentity,
              let proof = participants.committedDocumentProof(
                  webView: webView,
                  revision: currentIntent.revision,
                  documentGeneration: documentGeneration,
                  sharedCommitIdentity: sharedCommitIdentity
              ) else {
            return nil
        }
        return (
            proof.evidence,
            authorityReducer.isCommittedDocumentAuthority(
                proof.entry,
                webViewID: webViewID
            ),
        )
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFrameRehydrationResult {
        authorityReducer.rehydrate(
            candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID,
            intent: intent,
            participants: participants,
            effectClaims: effectClaims
        )
    }

    private func lifecycleRole(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameLifecycleRole {
        guard let participant = participants.activeEntry(
            webViewID: webViewID,
            navigationID: navigationID,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        return authorityReducer.lifecycleRole(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
    }
}
