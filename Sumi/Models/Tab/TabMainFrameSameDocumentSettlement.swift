import Foundation
import WebKit

/// Settles the presentation-only completion of a same-document navigation.
/// It cannot publish full-document finish effects and its publication is
/// guarded by a dedicated one-shot permit.
@MainActor
final class TabMainFrameSameDocumentSettlement {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityReducer: TabMainFrameAuthorityReducer
    private let effectClaims: TabMainFrameEffectLedger
    private let completedAuthority: TabMainFrameCompletedAuthorityProof

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityReducer: TabMainFrameAuthorityReducer,
        effectClaims: TabMainFrameEffectLedger,
        completedAuthority: TabMainFrameCompletedAuthorityProof
    ) {
        self.participants = participants
        self.authorityReducer = authorityReducer
        self.effectClaims = effectClaims
        self.completedAuthority = completedAuthority
    }

    func settle(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        presentationURL: URL,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameSameDocumentDecision {
        let webViewID = ObjectIdentifier(webView)
        guard let participant = participants.exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) else {
            return .stale
        }
        let role = authorityReducer.claimDocumentAuthority(
            for: participant,
            webViewID: webViewID,
            navigationID: navigationID
        )
        guard role.isParticipant else { return .stale }
        let previousTarget = participant.targetURL
        guard participants.updateTarget(
            presentationURL,
            webViewID: webViewID
        ) else {
            return .stale
        }
        guard role.isAuthority else {
            _ = participants.finish(
                webView: webView,
                navigationID: navigationID,
                navigationLifetime: navigationLifetime,
                revision: currentIntent.revision,
                kind: .sameDocument
            )
            return .completedReplica
        }
        if previousTarget != presentationURL {
            authorityReducer.noteTargetMutation(
                webViewID: webViewID,
                revision: currentIntent.revision
            )
        }
        guard let completed = participants.finish(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision,
            kind: .sameDocument
        ) else {
            return .stale
        }
        authorityReducer.markCompleted()
        guard let permit = effectClaims.reserveSameDocument(
            participantID: completed.id
        ), let lease = completedAuthority.issue(for: completed) else {
            return .stale
        }
        return .publish(TabMainFrameSameDocumentPublication(
            webView: webView,
            presentationURL: completed.targetURL,
            authority: lease,
            permit: permit
        ))
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
        return effectClaims.consumeSameDocument(
            publication.permit,
            participantID: publication.authority.participantID
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameCompletedAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        lease.completionKind == .sameDocument
            && completedAuthority.remainsCurrent(
                lease,
                currentIntent: currentIntent
            )
    }

}
