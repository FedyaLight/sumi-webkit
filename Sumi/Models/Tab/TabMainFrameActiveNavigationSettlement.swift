import Foundation
import SumiWebRuntime
import WebKit

/// Issues and validates publications that belong to one active main-frame
/// navigation. Completed navigation and promotion settlement are deliberately
/// outside this component.
@MainActor
final class TabMainFrameActiveNavigationSettlement {
    private typealias SharedCommitIdentity =
        TabMainFrameAuthorityEffectLedger.SharedCommitIdentity

    private let participantTransitions: TabMainFrameParticipantTransitionApplier
    private let authorityState: TabMainFrameAuthorityState
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let committer: TabMainFrameTransitionCommitter

    init(
        participantTransitions: TabMainFrameParticipantTransitionApplier,
        authorityState: TabMainFrameAuthorityState,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        committer: TabMainFrameTransitionCommitter
    ) {
        self.participantTransitions = participantTransitions
        self.authorityState = authorityState
        self.authorityEffects = authorityEffects
        self.committer = committer
    }

    func claimTransactionStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        ) else { return .stale }
        switch authorityEffects.claimTransactionStart() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyPublished(lease)
        }
    }

    func claimAuthorityTargetPreparation(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameActiveAuthorityLease> {
        guard let lease = authorityLease(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        ) else { return .stale }
        switch authorityEffects.claimAuthorityTargetPreparation() {
        case .claimed: return .publish(lease)
        case .alreadyClaimed: return .alreadyPublished(lease)
        }
    }

    func claimLocalStartEffects(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<URL> {
        participantTransitions.claimLocalStart(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            currentIntent: currentIntent
        )
    }

    func settleCommit(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        committedURL: URL,
        isPDF: Bool,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.Commit {
        guard let receipt = committer.commitDocument(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision,
            committedURL: committedURL,
            isPDF: isPDF
        ) else {
            return .init(role: .stale, evidence: nil, publication: nil)
        }
        switch receipt {
        case let .participant(participant):
            return .init(
                role: .participant,
                evidence: participant.committedEvidence(webView: webView),
                publication: nil
            )
        case let .authority(participant, authority, permit):
            let publication = permit.map {
                TabMainFrameCommitPublication(
                    webView: webView,
                    targetURL: committedURL,
                    isPDF: isPDF,
                    authority: authority,
                    permit: $0
                )
            }
            return .init(
                role: .authority,
                evidence: participant.committedEvidence(webView: webView),
                publication: publication
            )
        }
    }

    func consumeCommitPublication(
        _ publication: TabMainFrameCommitPublication,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(
            publication.authority,
            currentIntent: currentIntent
        ), let participant = participantTransitions.entry(
            for: publication.authority.webViewID
        ),
           publication.webView === participant.webViewReference.resolve(),
           publication.targetURL == publication.authority.targetURL,
           participant.committedDocumentURL == publication.targetURL,
           (participant.isPDFResponse ?? false) == publication.isPDF else {
            return false
        }
        return authorityEffects.consumeSharedCommit(
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
              lease.documentGeneration == authorityState.snapshot.documentGeneration,
              let participant = participantTransitions.entry(for: lease.webViewID),
              participant.matches(lease) else {
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
        guard let navigationID,
              participantTransitions.acceptActiveTarget(
                  targetURL,
                  webView: webView,
                  navigationID: navigationID,
                  revision: currentIntent.revision
              ) else { return false }
        return true
    }

    private func authorityLease(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameActiveAuthorityLease? {
        guard let participant = participantTransitions.entry(
            for: ObjectIdentifier(webView)
        ), participant.webViewReference.matches(webView),
           participant.revision == currentIntent.revision,
           participant.phase == .active(navigationID: navigationID),
           participant.navigationIdentityReference?.matches(
               navigationLifetime
           ) == true else { return nil }
        return authorityState.activeLease(in: authorityState.snapshot, participant: participant)
    }
}
