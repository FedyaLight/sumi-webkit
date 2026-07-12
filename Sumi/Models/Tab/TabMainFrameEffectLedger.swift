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

    private enum SharedFinishState {
        case reserved(TabMainFrameFinishPermit, participantID: UUID)
        case published
    }

    private enum SameDocumentState {
        case reserved(TabMainFrameSameDocumentPermit)
        case published
    }

    private var hasPublishedTransactionStart = false
    private var hasPublishedAuthorityTargetPreparation = false
    private var localStartParticipantIDs = Set<UUID>()
    private var sharedCommitState: SharedCommitState?
    private var sharedFinishState: SharedFinishState?
    private var sameDocumentStateByParticipantID: [UUID: SameDocumentState] = [:]

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

    var hasPublishedSharedFinish: Bool {
        if case .published = sharedFinishState { return true }
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
        sharedFinishState = nil
        sameDocumentStateByParticipantID.removeAll()
    }

    func markRehydrated(identity: SharedCommitIdentity) {
        hasPublishedTransactionStart = true
        hasPublishedAuthorityTargetPreparation = true
        sharedCommitState = .published(identity)
        sharedFinishState = .published
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
        sameDocumentStateByParticipantID.removeValue(forKey: participantID)
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

    func reserveSharedFinish(participantID: UUID) -> TabMainFrameFinishPermit? {
        switch sharedFinishState {
        case nil:
            let permit = TabMainFrameFinishPermit(id: UUID())
            sharedFinishState = .reserved(permit, participantID: participantID)
            return permit
        case .reserved(let permit, let reservedParticipantID)
            where reservedParticipantID == participantID:
            return permit
        case .reserved, .published:
            return nil
        }
    }

    func consumeSharedFinish(
        _ permit: TabMainFrameFinishPermit,
        participantID: UUID
    ) -> Bool {
        guard case .reserved(
            let reservedPermit,
            let reservedParticipantID
        ) = sharedFinishState,
        reservedPermit == permit,
        reservedParticipantID == participantID else {
            return false
        }
        sharedFinishState = .published
        return true
    }

    func reserveSameDocument(
        participantID: UUID
    ) -> TabMainFrameSameDocumentPermit? {
        switch sameDocumentStateByParticipantID[participantID] {
        case nil:
            let permit = TabMainFrameSameDocumentPermit(id: UUID())
            sameDocumentStateByParticipantID[participantID] = .reserved(permit)
            return permit
        case .reserved(let permit):
            return permit
        case .published:
            return nil
        }
    }

    func consumeSameDocument(
        _ permit: TabMainFrameSameDocumentPermit,
        participantID: UUID
    ) -> Bool {
        guard case .reserved(let reservedPermit) =
                sameDocumentStateByParticipantID[participantID],
              reservedPermit == permit else {
            return false
        }
        sameDocumentStateByParticipantID[participantID] = .published
        return true
    }

    func removeParticipant(_ participantID: UUID) {
        localStartParticipantIDs.remove(participantID)
        sameDocumentStateByParticipantID.removeValue(forKey: participantID)
        if case .reserved(_, let reservedParticipantID) = sharedFinishState,
           reservedParticipantID == participantID {
            sharedFinishState = nil
        }
    }
}
