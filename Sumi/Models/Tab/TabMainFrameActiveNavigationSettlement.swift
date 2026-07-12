import Foundation
import SumiWebRuntime
import WebKit

struct TabMainFrameCommitTransition {
    let role: TabMainFrameLifecycleRole
    let evidence: TabCommittedDocumentEvidence?
    let publication: TabMainFrameCommitPublication?
}

/// Issues and validates publications that belong to one active main-frame
/// navigation. Completed navigation and promotion settlement are deliberately
/// outside this component.
@MainActor
final class TabMainFrameActiveNavigationSettlement {
    private typealias SharedCommitIdentity =
        TabMainFrameEffectLedger.SharedCommitIdentity

    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityReducer: TabMainFrameAuthorityReducer
    private let effectClaims: TabMainFrameEffectLedger

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityReducer: TabMainFrameAuthorityReducer,
        effectClaims: TabMainFrameEffectLedger
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.authorityReducer = authorityReducer
        self.effectClaims = effectClaims
    }

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else { return .stale }
        switch effectClaims.claimTransactionStart() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyClaimed(lease)
        }
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else { return .stale }
        switch effectClaims.claimAuthorityTargetPreparation() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyClaimed(lease)
        }
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameEffectDecision<URL> {
        guard let participant = participants.exactEntry(for: webView),
              participant.revision == currentIntent.revision,
              participant.phase == .active(navigationID: navigationID) else {
            return .stale
        }
        switch effectClaims.claimLocalStart(participantID: participant.id) {
        case .claimed: return .publish(participant.targetURL)
        case .alreadyClaimed: return .alreadyClaimed(participant.targetURL)
        }
    }

    func settleCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        committedURL: URL,
        isPDF: Bool,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameCommitTransition {
        guard let record = authorityReducer.recordCommit(
            from: webView,
            navigationID: navigationID,
            committedURL: committedURL,
            isPDF: isPDF,
            currentIntent: currentIntent,
            participants: participants
        ) else {
            return TabMainFrameCommitTransition(
                role: .stale,
                evidence: nil,
                publication: nil
            )
        }
        guard record.role.isAuthority else {
            return TabMainFrameCommitTransition(
                role: record.role,
                evidence: record.evidence,
                publication: nil
            )
        }
        guard let authority = authorityLease(
            from: webView,
            navigationID: navigationID,
            currentIntent: currentIntent
        ) else {
            return TabMainFrameCommitTransition(
                role: .stale,
                evidence: record.evidence,
                publication: nil
            )
        }
        let identity = SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedURL),
            isPDF: isPDF
        )
        guard let permit = effectClaims.reserveSharedCommit(identity: identity) else {
            return TabMainFrameCommitTransition(
                role: .authority,
                evidence: record.evidence,
                publication: nil
            )
        }
        return TabMainFrameCommitTransition(
            role: .authority,
            evidence: record.evidence,
            publication: TabMainFrameCommitPublication(
                webView: webView,
                targetURL: committedURL,
                isPDF: isPDF,
                authority: authority,
                permit: permit
            )
        )
    }

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(
            publication.authority,
            currentIntent: currentIntent
        ), let participant = participants[publication.authority.webViewID],
           publication.webView === participant.webViewReference.resolve(),
           publication.targetURL == publication.authority.targetURL,
           participant.committedDocumentURL == publication.targetURL,
           (participant.isPDFResponse ?? false) == publication.isPDF else {
            return false
        }
        return effectClaims.consumeSharedCommit(
            publication.permit,
            identity: SharedCommitIdentity(
                target: WebRuntimeNavigationIdentity(publication.targetURL),
                isPDF: publication.isPDF
            )
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameActiveAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard lease.revision == currentIntent.revision,
              lease.documentGeneration == authorityReducer.documentGeneration,
              let participant = participants[lease.webViewID],
              participant.id == lease.participantID,
              participant.revision == lease.revision,
              participant.documentGeneration == lease.documentGeneration,
              participant.phase == .active(navigationID: lease.navigationID),
              participant.targetURL == lease.targetURL,
              participant.webViewReference.resolve() != nil else {
            return false
        }
        return authorityState.matches(lease)
    }

    func acceptTarget(
        _ targetURL: URL,
        from webView: WKWebView,
        navigationID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        let webViewID = ObjectIdentifier(webView)
        guard let navigationID,
              authorityReducer.isExactAuthority(
                  webViewID: webViewID,
                  navigationID: navigationID,
                  revision: currentIntent.revision
              ), let previousTarget = participants[webViewID]?.targetURL,
              participants.updateTarget(targetURL, webViewID: webViewID) else {
            return false
        }
        if previousTarget != targetURL {
            authorityState.noteTargetMutation(
                webViewID: webViewID,
                revision: currentIntent.revision
            )
        }
        return true
    }

    private func authorityLease(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameActiveAuthorityLease? {
        guard let participant = participants.exactEntry(for: webView),
              participant.revision == currentIntent.revision,
              participant.documentGeneration == authorityReducer.documentGeneration,
              participant.phase == .active(navigationID: navigationID),
              authorityReducer.isExactAuthority(
                  webViewID: ObjectIdentifier(webView),
                  navigationID: navigationID,
                  revision: currentIntent.revision
              ) else {
            return nil
        }
        return authorityState.activeLease(
            participantID: participant.id,
            webViewID: ObjectIdentifier(webView),
            navigationID: navigationID,
            revision: participant.revision,
            documentGeneration: participant.documentGeneration,
            targetURL: participant.targetURL
        )
    }
}
