import Foundation

/// Application-facing tab-closing transaction. Candidate classification,
/// durable mutation, selection repair, and publication remain explicit phases.
@MainActor
final class TabClosureService {
    private let transactions: TabStructuralLookupCoordinator
    private let candidateRetirement: TabClosureCandidateRetirement
    private let regularCommit: RegularTabClosureCommitTransaction
    private let selectionRepair: RegularTabClosureSelectionRepair
    private let targets: RegularTabClosureTargetQuery

    init(
        transactions: TabStructuralLookupCoordinator,
        candidateRetirement: TabClosureCandidateRetirement,
        regularCommit: RegularTabClosureCommitTransaction,
        selectionRepair: RegularTabClosureSelectionRepair,
        targets: RegularTabClosureTargetQuery
    ) {
        self.transactions = transactions
        self.candidateRetirement = candidateRetirement
        self.regularCommit = regularCommit
        self.selectionRepair = selectionRepair
        self.targets = targets
    }

    func removeTab(_ id: UUID) {
        removeTabs([id])
    }

    func removeTabs(_ ids: [UUID]) {
        transactions.withTransaction {
            let classification = candidateRetirement.retire(ids)
            guard classification.regularCandidates.isEmpty == false else {
                return
            }
            let currentTabAtStart = selectionRepair.currentTab
            guard let committed = regularCommit.commit(
                classification.regularCandidates
            ) else { return }
            selectionRepair.repair(
                after: committed.removals,
                removedCurrentTab: currentTabAtStart,
                profileID: committed.runtime.currentProfileId
            )
            regularCommit.publish(committed)
        }
    }

    @discardableResult
    func removeExactRegularTab(
        _ tab: Tab,
        in spaceID: UUID,
        presentNotification: Bool = true
    ) -> Bool {
        transactions.withTransaction {
            let currentTabAtStart = selectionRepair.currentTab
            guard let committed = regularCommit.commitExact(
                tab,
                in: spaceID
            ) else {
                return false
            }
            selectionRepair.repair(
                after: committed.removals,
                removedCurrentTab: currentTabAtStart,
                profileID: committed.runtime.currentProfileId
            )
            regularCommit.publish(
                committed,
                presentNotification: presentNotification
            )
            return true
        }
    }

    func closeAllTabsBelow(_ tab: Tab) {
        let ids = targets.tabIDsBelow(tab)
        guard ids.isEmpty == false else { return }
        removeTabs(ids)
    }

    func clearRegularTabs(for spaceID: UUID) {
        let ids = targets.regularTabIDsToClear(in: spaceID)
        guard ids.isEmpty == false else { return }
        RuntimeDiagnostics.emit(
            "🧹 [TabClosureService] Clearing \(ids.count) regular tabs for space \(spaceID)"
        )
        removeTabs(ids)
    }
}
