import Foundation
import SumiWebRuntime

/// Owns all one-shot main-frame side-effect claims. Participant and authority
/// code can prove eligibility, but cannot publish the same local/shared effect
/// twice or carry a claim across a document generation.
@MainActor
final class TabMainFrameEffectLedger {
    struct SharedCommitIdentity: Equatable {
        let target: WebRuntimeNavigationIdentity
        let isPDF: Bool
    }

    struct Snapshot {
        let hasPublishedSharedCommit: Bool
        let hasPublishedSharedFinish: Bool
    }

    private var hasPublishedTransactionStart = false
    private var hasPublishedAuthorityTargetPreparation = false
    private var localStartParticipantIDs = Set<UUID>()
    private(set) var hasPublishedSharedCommit = false
    private(set) var sharedCommitIdentity: SharedCommitIdentity?
    private(set) var hasPublishedSharedFinish = false
    private var terminalSuccessParticipantID: UUID?

    var snapshot: Snapshot {
        Snapshot(
            hasPublishedSharedCommit: hasPublishedSharedCommit,
            hasPublishedSharedFinish: hasPublishedSharedFinish
        )
    }

    func resetForDocumentGeneration() {
        hasPublishedTransactionStart = false
        hasPublishedAuthorityTargetPreparation = false
        localStartParticipantIDs.removeAll()
        hasPublishedSharedCommit = false
        sharedCommitIdentity = nil
        hasPublishedSharedFinish = false
        terminalSuccessParticipantID = nil
    }

    func markRehydrated(identity: SharedCommitIdentity) {
        hasPublishedTransactionStart = true
        hasPublishedAuthorityTargetPreparation = true
        hasPublishedSharedCommit = true
        sharedCommitIdentity = identity
        hasPublishedSharedFinish = true
        terminalSuccessParticipantID = nil
    }

    func claimTransactionStart(isExactAuthority: Bool) -> Bool {
        guard isExactAuthority, hasPublishedTransactionStart == false else {
            return false
        }
        hasPublishedTransactionStart = true
        return true
    }

    func claimAuthorityTargetPreparation(isExactAuthority: Bool) -> Bool {
        guard isExactAuthority,
              hasPublishedAuthorityTargetPreparation == false else {
            return false
        }
        hasPublishedAuthorityTargetPreparation = true
        return true
    }

    func claimLocalStart(participantID: UUID) -> Bool {
        localStartParticipantIDs.insert(participantID).inserted
    }

    func resetLocalStart(participantID: UUID) {
        localStartParticipantIDs.remove(participantID)
    }

    func claimSharedCommit(identity: SharedCommitIdentity) -> Bool {
        guard hasPublishedSharedCommit == false else { return false }
        hasPublishedSharedCommit = true
        sharedCommitIdentity = identity
        return true
    }

    func reserveTerminalSuccess(participantID: UUID) -> Bool {
        guard terminalSuccessParticipantID == nil
                || terminalSuccessParticipantID == participantID else {
            return false
        }
        terminalSuccessParticipantID = participantID
        return true
    }

    func claimSharedFinish(
        isExactAuthority: Bool,
        participantID: UUID
    ) -> Bool {
        guard isExactAuthority,
              terminalSuccessParticipantID == nil
                || terminalSuccessParticipantID == participantID,
              hasPublishedSharedFinish == false else {
            return false
        }
        hasPublishedSharedFinish = true
        terminalSuccessParticipantID = nil
        return true
    }

    func claimPromotedSharedFinish(
        isCurrentAuthority: Bool,
        isCompleted: Bool
    ) -> Bool {
        guard isCurrentAuthority,
              isCompleted,
              hasPublishedSharedFinish == false else {
            return false
        }
        hasPublishedSharedFinish = true
        return true
    }

    func removeParticipant(_ participantID: UUID) {
        localStartParticipantIDs.remove(participantID)
        if terminalSuccessParticipantID == participantID {
            terminalSuccessParticipantID = nil
        }
    }
}
