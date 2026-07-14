import Foundation
import SumiWebRuntime

/// Owns one-shot effects that belong to the logical main-frame authority.
/// Claims are generation-scoped and cannot be inherited by a replacement
/// participant without an explicit authority transition.
@MainActor
final class TabMainFrameAuthorityEffectLedger {
    enum ClaimResult {
        case claimed
        case alreadyClaimed
    }

    struct SharedCommitIdentity: Equatable {
        let target: WebRuntimeNavigationIdentity
        let isPDF: Bool
    }

    fileprivate enum SharedCommitState {
        case reserved(TabMainFrameCommitPermit, SharedCommitIdentity)
        case published(SharedCommitIdentity)
    }

    fileprivate enum SharedFinishState {
        case reserved(TabMainFrameFinishPermit, participantID: UUID)
        case published
    }

    struct MutationPlan<Output> {
        fileprivate let expectedRevision: UInt64
        fileprivate let transactionStart: Bool
        fileprivate let targetPreparation: Bool
        fileprivate let commitState: SharedCommitState?
        fileprivate let finishState: SharedFinishState?
        let output: Output
    }

    private var hasPublishedTransactionStart = false
    private var hasPublishedAuthorityTargetPreparation = false
    private var sharedCommitState: SharedCommitState?
    private var sharedFinishState: SharedFinishState?
    private var mutationRevision: UInt64 = 0
    var revision: UInt64 { mutationRevision }

    func prepareReset() -> MutationPlan<Void> {
        MutationPlan(
            expectedRevision: mutationRevision,
            transactionStart: false,
            targetPreparation: false,
            commitState: nil,
            finishState: nil,
            output: ()
        )
    }

    func prepareSharedCommit(
        identity: SharedCommitIdentity
    ) -> MutationPlan<TabMainFrameCommitPermit?> {
        let permit: TabMainFrameCommitPermit?
        let nextCommitState: SharedCommitState?
        switch sharedCommitState {
        case nil:
            let issued = TabMainFrameCommitPermit(id: UUID())
            permit = issued
            nextCommitState = .reserved(issued, identity)
        case .reserved(let issued, let reservedIdentity)
            where reservedIdentity == identity:
            permit = issued
            nextCommitState = sharedCommitState
        case .reserved, .published:
            permit = nil
            nextCommitState = sharedCommitState
        }
        return MutationPlan(
            expectedRevision: mutationRevision,
            transactionStart: hasPublishedTransactionStart,
            targetPreparation: hasPublishedAuthorityTargetPreparation,
            commitState: nextCommitState,
            finishState: sharedFinishState,
            output: permit
        )
    }

    func prepareSharedFinish(
        participantID: UUID
    ) -> MutationPlan<TabMainFrameFinishPermit?> {
        let permit: TabMainFrameFinishPermit?
        let nextFinishState: SharedFinishState?
        switch sharedFinishState {
        case nil:
            let issued = TabMainFrameFinishPermit(id: UUID())
            permit = issued
            nextFinishState = .reserved(issued, participantID: participantID)
        case .reserved(let issued, let reservedParticipantID)
            where reservedParticipantID == participantID:
            permit = issued
            nextFinishState = sharedFinishState
        case .reserved, .published:
            permit = nil
            nextFinishState = sharedFinishState
        }
        return MutationPlan(
            expectedRevision: mutationRevision,
            transactionStart: hasPublishedTransactionStart,
            targetPreparation: hasPublishedAuthorityTargetPreparation,
            commitState: sharedCommitState,
            finishState: nextFinishState,
            output: permit
        )
    }

    func canApply<Output>(_ plan: MutationPlan<Output>) -> Bool {
        plan.expectedRevision == mutationRevision
    }

    func applyPrevalidated<Output>(_ plan: MutationPlan<Output>) -> Output {
        precondition(canApply(plan), "authority effect plan must be prevalidated")
        hasPublishedTransactionStart = plan.transactionStart
        hasPublishedAuthorityTargetPreparation = plan.targetPreparation
        sharedCommitState = plan.commitState
        sharedFinishState = plan.finishState
        mutationRevision &+= 1
        return plan.output
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
        sharedCommitState = nil
        sharedFinishState = nil
        mutationRevision &+= 1
    }

    func markRehydrated(identity: SharedCommitIdentity) {
        hasPublishedTransactionStart = true
        hasPublishedAuthorityTargetPreparation = true
        sharedCommitState = .published(identity)
        sharedFinishState = .published
        mutationRevision &+= 1
    }

    func claimTransactionStart() -> ClaimResult {
        guard hasPublishedTransactionStart == false else {
            return .alreadyClaimed
        }
        hasPublishedTransactionStart = true
        mutationRevision &+= 1
        return .claimed
    }

    func claimAuthorityTargetPreparation() -> ClaimResult {
        guard hasPublishedAuthorityTargetPreparation == false else {
            return .alreadyClaimed
        }
        hasPublishedAuthorityTargetPreparation = true
        mutationRevision &+= 1
        return .claimed
    }

    func claimSharedCommit(identity: SharedCommitIdentity) -> Bool {
        switch sharedCommitState {
        case nil:
            sharedCommitState = .published(identity)
            mutationRevision &+= 1
            return true
        case .reserved(_, let reservedIdentity) where reservedIdentity == identity:
            sharedCommitState = .published(identity)
            mutationRevision &+= 1
            return true
        case .reserved, .published:
            return false
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
        mutationRevision &+= 1
        return true
    }

    func reserveSharedFinish(participantID: UUID) -> TabMainFrameFinishPermit? {
        applyPrevalidated(prepareSharedFinish(participantID: participantID))
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
        mutationRevision &+= 1
        return true
    }

    func removeParticipant(_ participantID: UUID) {
        if case .reserved(_, let reservedParticipantID) = sharedFinishState,
           reservedParticipantID == participantID {
            sharedFinishState = nil
            mutationRevision &+= 1
        }
    }
}
