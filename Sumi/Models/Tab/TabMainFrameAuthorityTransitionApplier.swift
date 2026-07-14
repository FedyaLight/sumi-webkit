import Foundation
import SumiWebRuntime
import WebKit

/// Applies authority-wide promotion and durable rehydration plans. Candidate
/// selection/reduction is pure; this boundary sequences the resulting snapshot
/// with generation-scoped authority and participant effects.
@MainActor
final class TabMainFrameAuthorityTransitionApplier {
    private let participants: TabMainFrameParticipantRegistry
    private let authorityState: TabMainFrameAuthorityState
    private let authorityEffects: TabMainFrameAuthorityEffectLedger
    private let participantEffects: TabMainFrameParticipantEffectLedger

    init(
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

    var documentGeneration: UInt64 {
        authorityState.snapshot.documentGeneration
    }

    func promoteAuthorityCandidate(
        preferredWebViewID: ObjectIdentifier?,
        currentIntent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.AuthorityPromotion? {
        let snapshot = authorityState.snapshot
        guard let candidate = TabMainFrameAuthorityReducer
            .selectPromotionCandidate(
                in: snapshot,
                from: participants.entries,
                revision: currentIntent.revision,
                preferredWebViewID: preferredWebViewID
            ),
            let webView = candidate.participant.webViewReference.resolve() else {
            authorityState.apply(TabMainFrameAuthorityReducer.clearAuthority(
                in: snapshot
            ))
            return nil
        }
        guard let preparation = authorityState.apply(
            TabMainFrameAuthorityReducer.preparePromotion(
                in: snapshot,
                of: candidate.participant,
                sharedCommitIdentity: authorityEffects.sharedCommitIdentity
            )
        ) else { return nil }
        var promotedParticipant = candidate.participant
        var migratedEvidence: [TabCommittedDocumentEvidence] = []
        if let migration = preparation.migration {
            authorityEffects.resetForDocumentGeneration()
            participantEffects.resetForDocumentGeneration()
            migratedEvidence = participants.migrateCommittedReplicas(
                revision: currentIntent.revision,
                from: migration.previousGeneration,
                to: documentGeneration,
                matching: migration.identity
            )
            promotedParticipant = participants.entry(for: candidate.webViewID)
                ?? promotedParticipant
        }
        return authorityState.apply(TabMainFrameAuthorityReducer.installPromotion(
            in: authorityState.snapshot,
            candidate: candidate,
            participant: promotedParticipant,
            webView: webView,
            targetURLToAdopt: preparation.targetURLToAdopt,
            migratedEvidence: migratedEvidence,
            hasPublishedSharedCommit: authorityEffects.hasPublishedSharedCommit,
            hasPublishedSharedFinish: authorityEffects.hasPublishedSharedFinish
        ))
    }

    func documentEvidence(
        for webView: WKWebView,
        currentIntent: TabMainFrameNavigationIntent
    ) -> (evidence: TabCommittedDocumentEvidence, isAuthority: Bool)? {
        let webViewID = ObjectIdentifier(webView)
        guard let sharedCommitIdentity = authorityEffects.sharedCommitIdentity,
              let proof = participants.committedDocumentProof(
                  webView: webView,
                  revision: currentIntent.revision,
                  documentGeneration: documentGeneration,
                  sharedCommitIdentity: sharedCommitIdentity
              ) else { return nil }
        return (
            proof.evidence,
            TabMainFrameAuthorityReducer.isCommittedDocumentAuthority(
                in: authorityState.snapshot,
                proof.entry,
                webViewID: webViewID
            )
        )
    }

    func rehydrate(
        _ candidates: [TabCommittedDocumentCandidate],
        preferredAuthorityWebViewID: ObjectIdentifier?,
        intent: TabMainFrameNavigationIntent
    ) -> TabMainFrameTransitionOutput.Rehydration {
        let rehydration = participants.rehydrate(
            candidates,
            preferredAuthorityWebViewID: preferredAuthorityWebViewID,
            intent: intent,
            documentGeneration: documentGeneration
        )
        rehydration.replacedParticipantIDs.forEach(retireEffects)
        participantEffects.markRehydrated(
            participantIDs: rehydration.entries.map(\.id)
        )
        guard let authorityWebViewID = rehydration.authorityWebViewID,
              let participant = rehydration.authorityEntry,
              let committedURL = participant.committedDocumentURL else {
            return TabMainFrameTransitionOutput.Rehydration(
                evidence: rehydration.evidence,
                authorityWebViewID: nil
            )
        }
        authorityState.apply(
            TabMainFrameAuthorityReducer.installAuthority(
                in: authorityState.snapshot,
                revision: intent.revision,
                webViewID: authorityWebViewID,
                documentGeneration: documentGeneration,
                navigationID: nil,
                hasCommittedDocument: true,
                isCompleted: true
            )
        )
        authorityEffects.markRehydrated(
            identity: TabMainFrameAuthorityEffectLedger.SharedCommitIdentity(
                target: WebRuntimeNavigationIdentity(committedURL),
                isPDF: participant.isPDFResponse ?? false
            )
        )
        return TabMainFrameTransitionOutput.Rehydration(
            evidence: rehydration.evidence,
            authorityWebViewID: authorityWebViewID
        )
    }

    private func retireEffects(_ participantID: UUID) {
        participantEffects.removeParticipant(participantID)
        authorityEffects.removeParticipant(participantID)
    }
}
