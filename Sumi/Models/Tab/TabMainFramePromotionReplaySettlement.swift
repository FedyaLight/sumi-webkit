import Foundation
import SumiWebRuntime

/// Validates and settles replay work for one promoted lifecycle authority.
/// Candidate selection and installation remain in the authority applier;
/// full-document finish permits remain in terminal settlement.
@MainActor
final class TabMainFramePromotionReplaySettlement {
    private typealias SharedCommitIdentity =
        TabMainFrameAuthorityEffectLedger.SharedCommitIdentity

    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let terminal: TabMainFrameTerminalSettlement

    init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        terminal: TabMainFrameTerminalSettlement
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.authorityEffects = authorityEffects
        self.terminal = terminal
    }

    func claimSharedCommitEffects(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabCommittedDocumentEvidence? {
        guard remainsCurrent(continuation, currentIntent: currentIntent),
              let participant = participants.exactEntry(for: continuation.webView),
              participant.hasCommittedDocument,
              let committedDocumentURL = participant.committedDocumentURL else {
            return nil
        }
        guard authorityEffects.claimSharedCommit(identity: SharedCommitIdentity(
            target: WebRuntimeNavigationIdentity(committedDocumentURL),
            isPDF: continuation.isPDF
        )) else { return nil }
        return participant.committedEvidence(webView: continuation.webView)
    }

    func finishPublication(
        matching continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionDecision<TabMainFrameFinishPublication> {
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
        TabMainFrameTargetTransitionCommitter.commitPromotion(
            targetURL,
            continuation: continuation,
            revision: currentIntent.revision,
            participants: participants,
            state: authorityState
        )
    }

    func remainsCurrent(
        _ continuation: TabMainFrameAuthorityContinuation,
        currentIntent: TabMainFrameNavigationIntent
    ) -> Bool {
        TabMainFrameAuthorityReducer.isCurrentAuthority(
            in: authorityState.snapshot,
            continuation,
            revision: currentIntent.revision,
            participant: participants.exactEntry(for: continuation.webView)
        )
    }
}
