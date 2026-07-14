import Foundation
import WebKit

/// Settles the presentation-only completion of a same-document navigation.
/// It cannot publish full-document finish effects and its publication is
/// guarded by a dedicated one-shot permit.
@MainActor
final class TabMainFrameSameDocumentSettlement {
    private let participants: TabMainFrameParticipantRegistry
    private let participantEffects: TabMainFrameParticipantEffectLedger
    private let completedAuthority: TabMainFrameCompletedAuthorityProof
    private let committer: TabMainFrameTransitionCommitter

    init(
        participants: TabMainFrameParticipantRegistry,
        participantEffects: TabMainFrameParticipantEffectLedger,
        completedAuthority: TabMainFrameCompletedAuthorityProof,
        committer: TabMainFrameTransitionCommitter
    ) {
        self.participants = participants
        self.participantEffects = participantEffects
        self.completedAuthority = completedAuthority
        self.committer = committer
    }

    func settle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        presentationURL: URL,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameSameDocumentPublication> {
        guard let receipt = committer.commitSameDocument(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision,
            presentationURL: presentationURL
        ) else { return .stale }
        switch receipt {
        case .participant:
            return .participant
        case let .authority(completed, lease, permit):
            return permit.map {
                .publish(TabMainFrameSameDocumentPublication(
                    webView: webView,
                    presentationURL: completed.targetURL,
                    authority: lease,
                    permit: $0
                ))
            } ?? .alreadyPublished(nil)
        }
    }

    func consume(
        _ publication: TabMainFrameSameDocumentPublication,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(
            publication.authority,
            currentIntent: currentIntent
        ), publication.authority.completionKind == .sameDocument,
           let participant = participants[publication.authority.webViewID],
           publication.webView === participant.webViewReference.resolve(),
           publication.presentationURL == participant.targetURL else {
            return false
        }
        return participantEffects.consumeSameDocument(
            publication.permit,
            participantID: publication.authority.participantID
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameCompletedAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        lease.completionKind == .sameDocument
            && completedAuthority.participant(
                matching: .lease(lease),
                currentIntent: currentIntent
            ) != nil
    }
}
