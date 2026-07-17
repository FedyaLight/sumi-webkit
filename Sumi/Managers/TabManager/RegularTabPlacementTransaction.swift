import Foundation

/// Owns the reversible structural residence transition for one regular Tab.
/// Profile admission and transition state are settled by the exact admission
/// receipt carried alongside the structural snapshot.
@MainActor
final class RegularTabPlacementTransaction {
    private let stateOwner: RegularTabCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private let admission: RegularTabPlacementAdmission

    init(
        stateOwner: RegularTabCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        admission: RegularTabPlacementAdmission
    ) {
        self.stateOwner = stateOwner
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
        self.admission = admission
    }

    func canInsert(_ tab: Tab, in spaceID: UUID) -> Bool {
        admission.canPlace(tab, in: spaceID)
    }

    func prepare(
        _ tab: Tab,
        in spaceID: UUID,
        at insertionIndex: Int?,
        admissionProfileIDs: Set<UUID>?
    ) -> PreparedRegularTabPlacement? {
        guard let profileAdmission = admission.prepare(
            tab,
            for: spaceID,
            explicitProfileIDs: admissionProfileIDs
        ) else { return nil }
        let targetTabs = stateOwner.tabs(in: spaceID)
        guard !targetTabs.contains(where: { $0 === tab }) else {
            precondition(profileAdmission.cancel())
            return nil
        }
        return PreparedRegularTabPlacement(
            transaction: self,
            tab: tab,
            source: .init(
                spaceID: tab.spaceId,
                profileID: tab.profileId,
                assignmentRevision: tab.profileAssignment.changeRevision,
                index: tab.index,
                isPinned: tab.isPinned,
                isSpacePinned: tab.isSpacePinned,
                folderID: tab.folderId
            ),
            target: .init(
                spaceID: spaceID,
                index: insertionIndex,
                tabs: targetTabs
            ),
            admission: profileAdmission
        )
    }

    func stage(_ placement: PreparedRegularTabPlacement) -> Bool {
        guard placement.belongs(to: self),
              placement.state == .prepared,
              placement.tab.spaceId == placement.source.spaceID,
              placement.tab.profileId == placement.source.profileID,
              placement.tab.profileAssignment.changeRevision
                == placement.source.assignmentRevision,
              !placement.tab.profileAssignment.hasUnsettledAssignment,
              sameTabs(
                  stateOwner.tabs(in: placement.target.spaceID),
                  placement.target.tabs
              ) else {
            _ = cancel(placement)
            return false
        }
        guard placement.admission.stage() else { return false }

        var regularTabs = placement.target.tabs
        let safeIndex = max(
            0,
            min(placement.target.index ?? regularTabs.count, regularTabs.count)
        )
        placement.tab.spaceId = placement.target.spaceID
        placement.tab.isPinned = false
        placement.tab.isSpacePinned = false
        placement.tab.folderId = nil
        regularTabs.insert(placement.tab, at: safeIndex)
        reindex(regularTabs)
        structuralMutations.setTabs(regularTabs, for: placement.target.spaceID)
        placement.stagedTargetTabs = regularTabs
        placement.state = .staged
        return true
    }

    func finish(
        _ placement: PreparedRegularTabPlacement,
        publishing publication: @MainActor () -> Void
    ) -> Bool {
        guard placement.belongs(to: self),
              placement.state == .staged,
              placement.admission.settleProfile() else { return false }
        precondition(
            placement.admission.commit(),
            "Settled regular-tab placement lost its admission lease"
        )
        placement.state = .committed
        publication()
        structuralLookup.runAfterCurrentBatch { [placement] in
            precondition(
                placement.admission.endCommittedLease(),
                "Committed regular-tab placement lost its admission lease"
            )
        }
        return true
    }

    func rollback(_ placement: PreparedRegularTabPlacement) -> Bool {
        guard placement.belongs(to: self) else { return false }
        guard placement.state == .staged,
              let stagedTargetTabs = placement.stagedTargetTabs,
              sameTabs(
                  stateOwner.tabs(in: placement.target.spaceID),
                  stagedTargetTabs
              ),
              placement.admission.canRollback() else {
            settleDivergedRollback(placement)
            return false
        }
        structuralMutations.setTabs(
            placement.target.tabs,
            for: placement.target.spaceID
        )
        placement.tab.spaceId = placement.source.spaceID
        placement.tab.index = placement.source.index
        placement.tab.isPinned = placement.source.isPinned
        placement.tab.isSpacePinned = placement.source.isSpacePinned
        placement.tab.folderId = placement.source.folderID
        precondition(placement.admission.rollback())
        placement.state = .cancelled
        return true
    }

    func cancel(_ placement: PreparedRegularTabPlacement) -> Bool {
        guard placement.belongs(to: self), placement.state == .prepared else {
            return false
        }
        placement.state = .cancelled
        return placement.admission.cancel()
    }

    private func settleDivergedRollback(
        _ placement: PreparedRegularTabPlacement
    ) {
        placement.state = .abandoned
        placement.admission.abandon()
    }

    private func sameTabs(_ lhs: [Tab], _ rhs: [Tab]) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    private func reindex(_ regularTabs: [Tab]) {
        for (index, tab) in regularTabs.enumerated() {
            tab.index = index
        }
    }
}
