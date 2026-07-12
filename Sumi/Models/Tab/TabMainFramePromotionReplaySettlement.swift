import Foundation
import SumiWebRuntime

/// Validates and settles replay work for one promoted lifecycle authority.
/// Candidate selection and authority installation remain in the lifecycle
/// machine; full-document finish permits remain in terminal settlement.
@MainActor
final class TabMainFramePromotionReplaySettlement {
    private typealias SharedCommitIdentity =
        TabMainFrameEffectLedger.SharedCommitIdentity

    private let participants: TabMainFrameParticipantRegistry
    private let authorityReducer: TabMainFrameAuthorityReducer
    private let effectClaims: TabMainFrameEffectLedger
    private let terminal: TabMainFrameTerminalSettlement

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityReducer: TabMainFrameAuthorityReducer,
        effectClaims: TabMainFrameEffectLedger,
        terminal: TabMainFrameTerminalSettlement
    ) {
        self.participants = participants
        self.authorityReducer = authorityReducer
        self.effectClaims = effectClaims
        self.terminal = terminal
    }

    func claimSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabCommittedDocumentEvidence? {
        guard remainsCurrent(continuation, currentIntent: currentIntent),
              let participant = participants[continuation.webViewID],
              participant.hasCommittedDocument,
              let committedDocumentURL = participant.committedDocumentURL else {
            return nil
        }
        guard effectClaims.claimSharedCommit(identity: SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedDocumentURL),
            isPDF: continuation.isPDF
        )) else { return nil }
        return participant.committedEvidence(webView: continuation.webView)
    }

    func finishPublication(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameFinishDecision {
        terminal.promotedFinishPublication(
            matching: continuation,
            currentIntent: currentIntent
        )
    }

    func acceptTarget(
        _ targetURL: URL,
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        guard remainsCurrent(continuation, currentIntent: currentIntent),
              let previousTarget = participants[continuation.webViewID]?.targetURL,
              participants.updateTarget(
                  targetURL,
                  webViewID: continuation.webViewID
              ) else {
            return false
        }
        if previousTarget != targetURL {
            authorityReducer.noteTargetMutation(
                webViewID: continuation.webViewID,
                revision: currentIntent.revision
            )
        }
        return true
    }

    func remainsCurrent(
        _ continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        authorityReducer.isCurrentAuthority(
            continuation,
            revision: currentIntent.revision,
            participants: participants
        )
    }
}
