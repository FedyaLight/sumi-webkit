import Foundation

/// Owns one-shot effects tied to one exact participant identity. Removing or
/// replacing a participant retires its permits without mutating authority-wide
/// publication state.
@MainActor
final class TabMainFrameParticipantEffectLedger {
    enum ClaimResult {
        case claimed
        case alreadyClaimed
    }

    fileprivate enum SameDocumentState {
        case reserved(TabMainFrameSameDocumentPermit)
        case published
    }

    struct MutationPlan<Output> {
        fileprivate let expectedRevision: UInt64
        fileprivate let localStartParticipantIDs: Set<UUID>
        fileprivate let sameDocumentStates: [UUID: SameDocumentState]
        let output: Output
    }

    private var localStartParticipantIDs = Set<UUID>()
    private var sameDocumentStateByParticipantID: [UUID: SameDocumentState] = [:]
    private var mutationRevision: UInt64 = 0
    var revision: UInt64 { mutationRevision }

    func prepareContinuation(
        participantID: UUID,
        resetsDocumentGeneration: Bool
    ) -> MutationPlan<Void> {
        var localStarts = resetsDocumentGeneration
            ? Set<UUID>()
            : localStartParticipantIDs
        var sameDocumentStates = resetsDocumentGeneration
            ? [:]
            : sameDocumentStateByParticipantID
        localStarts.remove(participantID)
        sameDocumentStates.removeValue(forKey: participantID)
        return MutationPlan(
            expectedRevision: mutationRevision,
            localStartParticipantIDs: localStarts,
            sameDocumentStates: sameDocumentStates,
            output: ()
        )
    }

    func prepareSameDocument(
        participantID: UUID
    ) -> MutationPlan<TabMainFrameSameDocumentPermit?> {
        let permit: TabMainFrameSameDocumentPermit?
        var sameDocumentStates = sameDocumentStateByParticipantID
        switch sameDocumentStates[participantID] {
        case nil:
            let issued = TabMainFrameSameDocumentPermit(id: UUID())
            permit = issued
            sameDocumentStates[participantID] = .reserved(issued)
        case .reserved(let issued):
            permit = issued
        case .published:
            permit = nil
        }
        return MutationPlan(
            expectedRevision: mutationRevision,
            localStartParticipantIDs: localStartParticipantIDs,
            sameDocumentStates: sameDocumentStates,
            output: permit
        )
    }

    func canApply<Output>(_ plan: MutationPlan<Output>) -> Bool {
        plan.expectedRevision == mutationRevision
    }

    @discardableResult
    func applyPrevalidated<Output>(_ plan: MutationPlan<Output>) -> Output {
        precondition(canApply(plan), "participant effect plan must be prevalidated")
        localStartParticipantIDs = plan.localStartParticipantIDs
        sameDocumentStateByParticipantID = plan.sameDocumentStates
        mutationRevision &+= 1
        return plan.output
    }

    func resetForDocumentGeneration() {
        localStartParticipantIDs.removeAll()
        sameDocumentStateByParticipantID.removeAll()
        mutationRevision &+= 1
    }

    func markRehydrated(participantIDs: [UUID]) {
        localStartParticipantIDs.formUnion(participantIDs)
        mutationRevision &+= 1
    }

    func claimLocalStart(participantID: UUID) -> ClaimResult {
        if localStartParticipantIDs.insert(participantID).inserted {
            mutationRevision &+= 1
            return .claimed
        }
        return .alreadyClaimed
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
        mutationRevision &+= 1
        return true
    }

    func removeParticipant(_ participantID: UUID) {
        localStartParticipantIDs.remove(participantID)
        sameDocumentStateByParticipantID.removeValue(forKey: participantID)
        mutationRevision &+= 1
    }
}
