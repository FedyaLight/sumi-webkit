import Foundation
import SumiWebRuntime

/// Owns all one-shot main-frame side-effect claims. Participant and authority
/// code can prove eligibility, but cannot publish the same local/shared effect
/// twice or carry a claim across a document generation.
@MainActor
final class TabMainFrameEffectLedger {
    enum ClaimResult {
        case claimed
        case alreadyClaimed
    }

    struct SharedCommitIdentity: Equatable {
        let target: WebRuntimeNavigationIdentity
        let isPDF: Bool
    }

    struct Snapshot {
        let hasPublishedSharedCommit: Bool
        let hasPublishedSharedFinish: Bool
    }

    private enum SharedCommitState {
        case reserved(TabMainFrameCommitPermit, SharedCommitIdentity)
        case published(SharedCommitIdentity)
    }

    private var hasPublishedTransactionStart = false
    private var hasPublishedAuthorityTargetPreparation = false
    private var localStartParticipantIDs = Set<UUID>()
    private var sharedCommitState: SharedCommitState?
    private(set) var hasPublishedSharedFinish = false
    private var terminalSuccessParticipantID: UUID?

    var snapshot: Snapshot {
        Snapshot(
            hasPublishedSharedCommit: hasPublishedSharedCommit,
            hasPublishedSharedFinish: hasPublishedSharedFinish
        )
    }

    var hasPublishedSharedCommit: Bool {
        if case .published = sharedCommitState { return true }
        return false
    }

    var sharedCommitIdentity: SharedCommitIdentity? {
        switch sharedCommitState {
        case .reserved(_, let identity), .published(let identity): identity
        case nil: nil
        }
    }

    func resetForDocumentGeneration() {
        hasPublishedTransactionStart = false
        hasPublishedAuthorityTargetPreparation = false
        localStartParticipantIDs.removeAll()
        sharedCommitState = nil
        hasPublishedSharedFinish = false
        terminalSuccessParticipantID = nil
    }

    func markRehydrated(identity: SharedCommitIdentity) {
        hasPublishedTransactionStart = true
        hasPublishedAuthorityTargetPreparation = true
        sharedCommitState = .published(identity)
        hasPublishedSharedFinish = true
        terminalSuccessParticipantID = nil
    }

    func claimTransactionStart() -> ClaimResult {
        guard hasPublishedTransactionStart == false else {
            return .alreadyClaimed
        }
        hasPublishedTransactionStart = true
        return .claimed
    }

    func claimAuthorityTargetPreparation() -> ClaimResult {
        guard hasPublishedAuthorityTargetPreparation == false else {
            return .alreadyClaimed
        }
        hasPublishedAuthorityTargetPreparation = true
        return .claimed
    }

    func claimLocalStart(participantID: UUID) -> ClaimResult {
        localStartParticipantIDs.insert(participantID).inserted
            ? .claimed
            : .alreadyClaimed
    }

    func resetLocalStart(participantID: UUID) {
        localStartParticipantIDs.remove(participantID)
    }

    func claimSharedCommit(identity: SharedCommitIdentity) -> Bool {
        switch sharedCommitState {
        case nil:
            sharedCommitState = .published(identity)
            return true
        case .reserved(_, let reservedIdentity) where reservedIdentity == identity:
            sharedCommitState = .published(identity)
            return true
        case .reserved, .published:
            return false
        }
    }

    func reserveSharedCommit(
        identity: SharedCommitIdentity
    ) -> TabMainFrameCommitPermit? {
        switch sharedCommitState {
        case nil:
            let permit = TabMainFrameCommitPermit(id: UUID())
            sharedCommitState = .reserved(permit, identity)
            return permit
        case .reserved(let permit, let reservedIdentity)
            where reservedIdentity == identity:
            return permit
        case .reserved, .published:
            return nil
        }
    }

    func consumeSharedCommit(
        _ permit: TabMainFrameCommitPermit,
        identity: SharedCommitIdentity
    ) -> Bool {
        guard case .reserved(let reservedPermit, let reservedIdentity) = sharedCommitState,
              reservedPermit == permit,
              reservedIdentity == identity else {
            return false
        }
        sharedCommitState = .published(identity)
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
