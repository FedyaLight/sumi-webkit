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

    func stageAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard let first = placements.first,
              placements.allSatisfy({
                  $0.belongs(to: self)
                      && $0.state == .prepared
                      && $0.target.spaceID == first.target.spaceID
                      && sameTabs($0.target.tabs, first.target.tabs)
                      && $0.tab.spaceId == $0.source.spaceID
                      && $0.tab.profileId == $0.source.profileID
                      && $0.tab.profileAssignment.changeRevision
                          == $0.source.assignmentRevision
                      && !$0.tab.profileAssignment.hasUnsettledAssignment
              }),
              Set(placements.map { ObjectIdentifier($0.tab) }).count
                  == placements.count,
              sameTabs(
                  stateOwner.tabs(in: first.target.spaceID),
                  first.target.tabs
              ),
              placements.allSatisfy({ placement in
                  !first.target.tabs.contains(where: { $0 === placement.tab })
              }) else {
            _ = cancelAggregate(placements)
            return false
        }

        var stagedAdmissions: [PreparedRegularTabPlacement] = []
        for placement in placements {
            guard placement.admission.stage() else {
                stagedAdmissions.reversed().forEach {
                    precondition($0.admission.rollback())
                    $0.state = .cancelled
                }
                placements.dropFirst(stagedAdmissions.count + 1).forEach {
                    precondition(cancel($0))
                }
                placement.state = .cancelled
                return false
            }
            stagedAdmissions.append(placement)
        }

        var tabs = first.target.tabs
        for placement in placements {
            let index = max(
                0,
                min(placement.target.index ?? tabs.count, tabs.count)
            )
            placement.tab.spaceId = placement.target.spaceID
            placement.tab.isPinned = false
            placement.tab.isSpacePinned = false
            placement.tab.folderId = nil
            tabs.insert(placement.tab, at: index)
        }
        reindex(tabs)
        structuralMutations.setTabs(tabs, for: first.target.spaceID)
        placements.forEach {
            $0.stagedTargetTabs = tabs
            $0.state = .staged
        }
        return true
    }

    func finishAggregate(
        _ placements: [PreparedRegularTabPlacement],
        publishing publication: @MainActor () -> Void
    ) -> Bool {
        guard let first = placements.first,
              let targetTabs = first.stagedTargetTabs,
              placements.allSatisfy({
                  $0.belongs(to: self)
                      && $0.state == .staged
                      && $0.stagedTargetTabs.map {
                          sameTabs($0, targetTabs)
                      } == true
              }),
              sameTabs(stateOwner.tabs(in: first.target.spaceID), targetTabs),
              placements.allSatisfy({ $0.admission.settleProfile() })
        else { return false }

        guard placements.allSatisfy({ $0.admission.commit() }) else {
            preconditionFailure(
                "Settled regular-tab aggregate lost an admission lease"
            )
        }
        placements.forEach { $0.state = .committed }
        publication()
        structuralLookup.runAfterCurrentBatch { [placements] in
            precondition(
                placements.allSatisfy {
                    $0.admission.endCommittedLease()
                },
                "Committed regular-tab aggregate lost an admission lease"
            )
        }
        return true
    }

    func rollbackAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard let first = placements.first,
              let targetTabs = first.stagedTargetTabs,
              placements.allSatisfy({
                  $0.belongs(to: self)
                      && $0.state == .staged
                      && $0.stagedTargetTabs.map {
                          sameTabs($0, targetTabs)
                      } == true
                      && $0.admission.canRollback()
              }),
              sameTabs(stateOwner.tabs(in: first.target.spaceID), targetTabs)
        else { return false }

        structuralMutations.setTabs(
            first.target.tabs,
            for: first.target.spaceID
        )
        for placement in placements.reversed() {
            placement.tab.spaceId = placement.source.spaceID
            placement.tab.index = placement.source.index
            placement.tab.isPinned = placement.source.isPinned
            placement.tab.isSpacePinned = placement.source.isSpacePinned
            placement.tab.folderId = placement.source.folderID
            precondition(placement.admission.rollback())
            placement.state = .cancelled
        }
        return true
    }

    func cancelAggregate(
        _ placements: [PreparedRegularTabPlacement]
    ) -> Bool {
        guard placements.allSatisfy({
            $0.belongs(to: self) && $0.state == .prepared
        }) else { return placements.isEmpty }
        return placements.allSatisfy(cancel)
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
