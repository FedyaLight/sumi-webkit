import Foundation
import WebKit

/// Settles full-document terminal success. It preserves the exact completed
/// WKNavigation witness so an abandoned publication can only be recovered by
/// the same physical callback lifetime.
@MainActor
final class TabMainFrameTerminalSettlement {
    struct Result {
        let decision: TabMainFrameFinishDecision
        let evidence: TabCommittedDocumentEvidence?
        let presentationURLToAdopt: URL?
    }

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

    func settleFinish(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        terminalURL: URL?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Result {
        guard participants.exactActiveEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ) != nil else {
            return Result(
                decision: reissueFinishPublication(
                    from: webView,
                    navigationID: navigationID,
                    navigationLifetime: navigationLifetime,
                    currentIntent: currentIntent
                ),
                evidence: nil,
                presentationURLToAdopt: nil
            )
        }
        let settlement = authorityReducer.settleTerminalSuccess(
            from: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            terminalURL: terminalURL,
            currentIntent: currentIntent,
            participants: participants,
            effectClaims: effectClaims
        )
        switch settlement.role {
        case .stale:
            return Result(
                decision: .stale,
                evidence: settlement.evidence,
                presentationURLToAdopt: nil
            )
        case .participant:
            _ = participants.finish(
                webView: webView,
                navigationID: navigationID,
                navigationLifetime: navigationLifetime,
                revision: currentIntent.revision,
                kind: .document
            )
            return Result(
                decision: .completedReplica,
                evidence: settlement.evidence,
                presentationURLToAdopt: nil
            )
        case .authority:
            guard let completed = participants.finish(
                webView: webView,
                navigationID: navigationID,
                navigationLifetime: navigationLifetime,
                revision: currentIntent.revision,
                kind: .document
            ) else {
                return Result(
                    decision: .stale,
                    evidence: settlement.evidence,
                    presentationURLToAdopt: nil
                )
            }
            authorityReducer.markCompleted()
            let decision = finishPublication(
                for: completed,
                webView: webView
            )
            return Result(
                decision: decision,
                evidence: settlement.evidence,
                presentationURLToAdopt: settlement.presentationURLToAdopt
            )
        }
    }

    func promotedFinishPublication(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameFinishDecision {
        guard authorityReducer.isCurrentAuthority(
            continuation,
            revision: currentIntent.revision,
            participants: participants
        ), continuation.isCompleted,
           let participant = participants[continuation.webViewID],
           case .completed(_, .document) = participant.phase else {
            return .stale
        }
        if effectClaims.hasPublishedSharedFinish {
            return .alreadyPublished
        }
        return finishPublication(
            for: participant,
            webView: continuation.webView
        )
    }

    func consumeFinishPublication(
        _ publication: TabMainFrameFinishPublication,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(
            publication.authority,
            currentIntent: currentIntent
        ), publication.authority.completionKind == .document,
           let participant = participants[publication.authority.webViewID],
           publication.webView === participant.webViewReference.resolve(),
           publication.presentationURL == publication.authority.presentationURL,
           publication.isPDF == publication.authority.isPDF else {
            return false
        }
        return effectClaims.consumeSharedFinish(
            publication.permit,
            participantID: publication.authority.participantID
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameCompletedAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        completedAuthority.remainsCurrent(
            lease,
            currentIntent: currentIntent
        )
    }

    private func reissueFinishPublication(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameFinishDecision {
        guard let participant = participants.exactCompletedEntry(
            for: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision
        ), case .completed(_, .document) = participant.phase,
           participant.documentGeneration == authorityReducer.documentGeneration,
           let authority = authorityReducer.authority,
           authority.revision == participant.revision,
           authority.documentGeneration == participant.documentGeneration,
           authority.webViewID == ObjectIdentifier(webView),
           authority.isCompleted else {
            return .stale
        }
        if effectClaims.hasPublishedSharedFinish {
            return .alreadyPublished
        }
        return finishPublication(for: participant, webView: webView)
    }

    private func finishPublication(
        for participant: TabMainFrameParticipantRegistry.Entry,
        webView: WKWebView
    ) -> TabMainFrameFinishDecision {
        guard case .completed(_, .document) = participant.phase,
              let permit = effectClaims.reserveSharedFinish(
                  participantID: participant.id
              ), let lease = completedAuthority.issue(for: participant) else {
            return effectClaims.hasPublishedSharedFinish
                ? .alreadyPublished
                : .stale
        }
        return .publish(TabMainFrameFinishPublication(
            webView: webView,
            presentationURL: participant.targetURL,
            isPDF: participant.isPDFResponse ?? false,
            authority: lease,
            permit: permit
        ))
    }

}
