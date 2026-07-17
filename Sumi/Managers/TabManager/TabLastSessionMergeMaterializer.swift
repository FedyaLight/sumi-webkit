import Foundation

/// Applies a last-session merge plan as one structural transaction. Mutable
/// browser state is deliberately confined to role-exact materializers.
@MainActor
final class TabLastSessionMergeMaterializer {
    private let planning: TabLastSessionMergePlanningService
    private let profileAdmission: TabLastSessionProfileAdmissionTransaction
    private let structuralLookup: TabStructuralLookupCoordinator
    private let commitTransaction: TabLastSessionMergeCommitTransaction
    private let settlement: TabLastSessionMergeSettlement

    init(
        planning: TabLastSessionMergePlanningService,
        profileAdmission: TabLastSessionProfileAdmissionTransaction,
        structuralLookup: TabStructuralLookupCoordinator,
        commitTransaction: TabLastSessionMergeCommitTransaction,
        settlement: TabLastSessionMergeSettlement
    ) {
        self.planning = planning
        self.profileAdmission = profileAdmission
        self.structuralLookup = structuralLookup
        self.commitTransaction = commitTransaction
        self.settlement = settlement
    }

    @discardableResult
    func merge(_ snapshot: TabPersistenceSnapshot) -> Bool {
        let profileIDs = ProfileReferenceInventory(
            tabSnapshot: snapshot
        ).profileIDs
        return profileAdmission.withAdmittedReferences(profileIDs) {
            let prepared = planning.prepare(snapshot)
            structuralLookup.withTransaction {
                commitTransaction.commit(prepared)
                settlement.settle(prepared.plan)
            }
        }
    }
}
