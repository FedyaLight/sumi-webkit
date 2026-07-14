import Foundation
import WebKit

/// The single mutable commit boundary for planned main-frame transitions.
/// Every revision check happens before the first apply; plans contain values
/// only, so the commit phase cannot invoke callbacks or acquire new evidence.
@MainActor
final class TabMainFrameTransitionCommitter {
    enum DocumentReceipt {
        case participant(TabMainFrameParticipantRegistry.Entry)
        case authority(
            TabMainFrameParticipantRegistry.Entry,
            TabMainFrameActiveAuthorityLease,
            TabMainFrameCommitPermit?
        )
    }

    enum TerminalReceipt {
        case participant(
            TabMainFrameParticipantRegistry.Entry,
            TabMainFrameAuthorityReducer.TerminalSuccessReduction
        )
        case authority(
            TabMainFrameParticipantRegistry.Entry,
            TabMainFrameAuthorityReducer.TerminalSuccessReduction,
            TabMainFrameCompletedAuthorityLease,
            TabMainFrameFinishPermit?
        )
    }

    enum SameDocumentReceipt {
        case participant
        case authority(
            TabMainFrameParticipantRegistry.Entry,
            TabMainFrameCompletedAuthorityLease,
            TabMainFrameSameDocumentPermit?
        )
    }

    struct ContinuationReceipt {
        let participant: TabMainFrameParticipantRegistry.Entry
        let reduction: TabMainFrameAuthorityReducer.ContinuationReduction
    }

    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let participantEffects: TabMainFrameParticipantEffectLedger

    private init(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        participantEffects: TabMainFrameParticipantEffectLedger
    ) {
        self.participants = participants
        self.authorityState = authorityState
        self.authorityEffects = authorityEffects
        self.participantEffects = participantEffects
    }

    static func lifecycleComposition(
        participants: TabMainFrameParticipantRegistry,
        authorityState: TabMainFrameAuthorityState,
        authorityEffects: TabMainFrameAuthorityEffectLedger,
        participantEffects: TabMainFrameParticipantEffectLedger
    ) -> TabMainFrameTransitionCommitter {
        TabMainFrameTransitionCommitter(
            participants: participants,
            authorityState: authorityState,
            authorityEffects: authorityEffects,
            participantEffects: participantEffects
        )
    }

    func commitDocument(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        committedURL: URL,
        isPDF: Bool
    ) -> DocumentReceipt? {
        guard let mutation = participants.prepareCommit(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision,
            committedURL: committedURL,
            isPDF: isPDF
        ), let prepared = TabMainFramePreparedTransition.document(
            participant: mutation.plan,
            source: mutation.previousEntry,
            state: authorityState,
            effects: authorityEffects
        ),
              participants.canApply(prepared.participant),
              authorityState.canApply(prepared.authority) else { return nil }
        if let effect = prepared.effect, authorityEffects.canApply(effect) == false {
            return nil
        }
        let participant = participants.applyPrevalidated(prepared.participant)
        authorityState.applyPrevalidated(prepared.authority)
        let permit = prepared.effect.flatMap { authorityEffects.applyPrevalidated($0) }
        if let lease = prepared.lease {
            return .authority(participant, lease, permit)
        }
        return .participant(participant)
    }

    func commitTerminal(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        terminalURL: URL?
    ) -> TerminalReceipt? {
        guard let mutation = participants.prepareTerminalSuccess(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision,
            terminalURL: terminalURL
        ), let prepared = TabMainFramePreparedTransition.terminal(
            participant: mutation.plan,
            source: mutation.previousEntry,
            terminalURL: terminalURL,
            state: authorityState,
            effects: authorityEffects
        ),
              participants.canApply(prepared.participant),
              authorityState.canApply(prepared.authority) else { return nil }
        if let effect = prepared.effect, authorityEffects.canApply(effect) == false {
            return nil
        }
        let participant = participants.applyPrevalidated(prepared.participant)
        authorityState.applyPrevalidated(prepared.authority)
        let permit = prepared.effect.flatMap { authorityEffects.applyPrevalidated($0) }
        if let lease = prepared.lease {
            return .authority(participant, prepared.authority.output, lease, permit)
        }
        return .participant(participant, prepared.authority.output)
    }

    func commitSameDocument(
        webView: WKWebView,
        navigationID: ObjectIdentifier,
        navigationLifetime: AnyObject,
        revision: UInt64,
        presentationURL: URL
    ) -> SameDocumentReceipt? {
        guard let mutation = participants.prepareSameDocumentSuccess(
            webView: webView,
            navigationID: navigationID,
            navigationLifetime: navigationLifetime,
            revision: revision,
            presentationURL: presentationURL
        ), let prepared = TabMainFramePreparedTransition.sameDocument(
            participant: mutation.plan,
            source: mutation.previousEntry,
            state: authorityState,
            effects: participantEffects
        ),
              participants.canApply(prepared.participant),
              authorityState.canApply(prepared.authority) else { return nil }
        if let effect = prepared.effect, participantEffects.canApply(effect) == false {
            return nil
        }
        let participant = participants.applyPrevalidated(prepared.participant)
        authorityState.applyPrevalidated(prepared.authority)
        let permit = prepared.effect.flatMap { participantEffects.applyPrevalidated($0) }
        if let lease = prepared.lease {
            return .authority(participant, lease, permit)
        }
        return .participant
    }

    func commitContinuation(
        _ mutation: TabMainFrameParticipantRegistry.PreparedEntryMutation,
        targetURL: URL,
        kind: TabMainFrameContinuationKind,
        ownsAuthority: Bool
    ) -> ContinuationReceipt? {
        guard let prepared = TabMainFramePreparedTransition.continuation(
            participant: mutation.plan,
            source: mutation.previousEntry,
            targetURL: targetURL,
            kind: kind,
            ownsAuthority: ownsAuthority,
            state: authorityState,
            effects: authorityEffects,
            participantEffects: participantEffects
        ),
              participants.canApply(prepared.participant),
              authorityState.canApply(prepared.authority),
              participantEffects.canApply(prepared.participantEffect) else {
            return nil
        }
        if let effect = prepared.authorityEffect,
           authorityEffects.canApply(effect) == false {
            return nil
        }
        let participant = participants.applyPrevalidated(prepared.participant)
        authorityState.applyPrevalidated(prepared.authority)
        if let effect = prepared.authorityEffect {
            authorityEffects.applyPrevalidated(effect)
        }
        participantEffects.applyPrevalidated(prepared.participantEffect)
        return ContinuationReceipt(participant: participant, reduction: prepared.authority.output)
    }
}
