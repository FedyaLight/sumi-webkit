import Foundation
import WebKit

/// Settles a committed full-document terminal callback. It preserves the
/// exact completed WKNavigation witness so an abandoned publication can only
/// be recovered by the same physical callback lifetime.
@MainActor
final class TabMainFrameTerminalSettlement {
    struct Result {
        let decision: TabMainFrameTransitionDecision<TabMainFrameFinishPublication>
        let evidence: TabCommittedDocumentEvidence?
        let presentationURLToAdopt: URL?
    }

    private let participants: TabMainFrameParticipantRegistry
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let completedAuthority: TabMainFrameCompletedAuthorityProof
    private let committer: TabMainFrameTransitionCommitter

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        completedAuthority: TabMainFrameCompletedAuthorityProof,
        committer: TabMainFrameTransitionCommitter
    ) {
        self.participants = participants
        self.authorityEffects = authorityEffects
        self.completedAuthority = completedAuthority
        self.committer = committer
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
        guard let receipt = committer.commitTerminal(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: currentIntent.revision,
            terminalURL: terminalURL
        ) else {
            return .init(decision: .stale, evidence: nil, presentationURLToAdopt: nil)
        }
        switch receipt {
        case let .participant(participant, reduction):
            return .init(
                decision: .participant,
                evidence: participant.committedEvidence(webView: webView),
                presentationURLToAdopt: reduction.presentationURLToAdopt
            )
        case let .authority(participant, reduction, lease, permit):
            let decision = permit.map {
                TabMainFrameTransitionDecision.publish(TabMainFrameFinishPublication(
                    webView: webView,
                    presentationURL: participant.targetURL,
                    isPDF: participant.isPDFResponse ?? false,
                    authority: lease,
                    permit: $0
                ))
            } ?? .alreadyPublished(nil)
            return .init(
                decision: decision,
                evidence: participant.committedEvidence(webView: webView),
                presentationURLToAdopt: reduction.presentationURLToAdopt
            )
        }
    }

    func promotedFinishPublication(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication> {
        guard continuation.isCompleted,
           let participant = completedAuthority.participant(
               matching: .continuation(continuation),
               currentIntent: currentIntent
           ),
           case .completed(_, .document) = participant.phase else {
            return .stale
        }
        if authorityEffects.hasPublishedSharedFinish {
            return .alreadyPublished(nil)
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
        return authorityEffects.consumeSharedFinish(
            publication.permit,
            participantID: publication.authority.participantID
        )
    }

    func remainsCurrent(
        _ lease: TabMainFrameCompletedAuthorityLease,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        completedAuthority.participant(
            matching: .lease(lease),
            currentIntent: currentIntent
        ) != nil
    }

    private func reissueFinishPublication(
        from webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication> {
        guard let participant = completedAuthority.participant(
            matching: .terminal(webView, navigationID, navigationLifetime),
            currentIntent: currentIntent
        ) else {
            return .stale
        }
        if authorityEffects.hasPublishedSharedFinish {
            return .alreadyPublished(nil)
        }
        return finishPublication(for: participant, webView: webView)
    }

    private func finishPublication(
        for participant: TabMainFrameParticipantRegistry.Entry,
        webView: WKWebView
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication> {
        guard case .completed(_, .document) = participant.phase,
              let permit = authorityEffects.reserveSharedFinish(
                  participantID: participant.id
              ), let lease = completedAuthority.issue(for: participant) else {
            return authorityEffects.hasPublishedSharedFinish
                ? .alreadyPublished(nil)
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
