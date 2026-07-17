import Foundation

/// Owns the profile-reference lease and profile transition for one regular-tab
/// placement. Structural residence remains outside this authority.
@MainActor
final class RegularTabPlacementAdmission {
    private let policy: ProfileAssignmentPolicy
    private let references: ProfileReferenceAdmissionLedger
    private let profiles: TabProfileTransitionService

    init(
        policy: ProfileAssignmentPolicy,
        references: ProfileReferenceAdmissionLedger,
        profiles: TabProfileTransitionService
    ) {
        self.policy = policy
        self.references = references
        self.profiles = profiles
    }

    func canPlace(_ tab: Tab, in spaceID: UUID) -> Bool {
        let profileIDs = policy.regularInsertionProfileIDs(
            tab: tab,
            targetSpaceID: spaceID
        )
        return references.isAvailable
            && profileIDs.allSatisfy(references.isReferenceAllowed)
    }

    func prepare(
        _ tab: Tab,
        for spaceID: UUID,
        explicitProfileIDs: Set<UUID>?
    ) -> PreparedRegularTabPlacementAdmission? {
        let inferredProfileIDs = policy.regularInsertionProfileIDs(
            tab: tab,
            targetSpaceID: spaceID
        )
        guard !inferredProfileIDs.isEmpty || explicitProfileIDs != nil else {
            return nil
        }
        let profileIDs = explicitProfileIDs.map {
            $0.union(inferredProfileIDs)
        } ?? inferredProfileIDs
        guard profileIDs.allSatisfy(references.isReferenceAllowed) else {
            return nil
        }

        let lease: ProfileReferenceMutationLease
        do {
            lease = try references.beginReferenceMutation(to: profileIDs)
        } catch {
            return nil
        }
        guard references.validate(lease, covers: profileIDs) else {
            precondition(references.endReferenceMutation(lease))
            return nil
        }

        let transition: TabSpaceProfileTransitionPreparation?
        switch profiles.prepareForSpaceTransition(
            tab: tab,
            targetSpaceID: spaceID
        ) {
        case .unnecessary:
            transition = nil
        case .prepared(let preparation):
            transition = preparation
        case .rejected:
            precondition(references.endReferenceMutation(lease))
            return nil
        }

        return PreparedRegularTabPlacementAdmission(
            authority: self,
            tab: tab,
            sourceProfileID: tab.profileId,
            sourceAssignmentRevision: tab.profileAssignment.changeRevision,
            profileIDs: profileIDs,
            lease: lease,
            transition: transition
        )
    }

    func stage(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard receipt.belongs(to: self),
              receipt.state == .prepared,
              receipt.tab.profileId == receipt.sourceProfileID,
              receipt.tab.profileAssignment.changeRevision
                == receipt.sourceAssignmentRevision,
              !receipt.tab.profileAssignment.hasUnsettledAssignment,
              validate(receipt) else {
            _ = cancel(receipt)
            return false
        }

        if let transition = receipt.transition,
           !profiles.stageSpaceTransition(transition, for: receipt.tab) {
            _ = cancel(receipt)
            return false
        }
        let stagedProfileIDs = receipt.profileIDs.union(
            receipt.tab.profileId.map { [$0] } ?? []
        )
        guard references.validate(receipt.lease, covers: stagedProfileIDs) else {
            if let transition = receipt.transition {
                precondition(
                    profiles.rollbackStagedSpaceTransition(
                        transition,
                        for: receipt.tab
                    )
                )
            }
            _ = cancel(receipt)
            return false
        }
        receipt.state = .staged
        return true
    }

    func settleProfile(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard receipt.belongs(to: self),
              receipt.state == .staged,
              validate(receipt) else { return false }
        guard let transition = receipt.transition else { return true }
        return profiles.finishSpaceTransition(
            transition,
            for: receipt.tab
        ).wasAccepted
    }

    func commit(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard receipt.belongs(to: self),
              receipt.state == .staged,
              validate(receipt) else { return false }
        receipt.state = .committed
        return true
    }

    func canRollback(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard receipt.belongs(to: self),
              receipt.state == .staged,
              validate(receipt) else { return false }
        return receipt.transition.map {
            profiles.canRollbackStagedSpaceTransition($0, for: receipt.tab)
        } ?? true
    }

    func rollback(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard canRollback(receipt) else { return false }
        if let transition = receipt.transition {
            precondition(
                profiles.rollbackStagedSpaceTransition(
                    transition,
                    for: receipt.tab
                )
            )
        }
        receipt.state = .cancelled
        return endLease(receipt)
    }

    func cancel(_ receipt: PreparedRegularTabPlacementAdmission) -> Bool {
        guard receipt.belongs(to: self), receipt.state == .prepared else {
            return false
        }
        receipt.state = .cancelled
        return endLease(receipt)
    }

    func abandon(_ receipt: PreparedRegularTabPlacementAdmission) {
        guard receipt.belongs(to: self), receipt.state == .staged else {
            return
        }
        receipt.state = .abandoned
        precondition(
            endLease(receipt),
            "Diverged regular-tab admission lost its reference lease"
        )
    }

    func endCommittedLease(
        _ receipt: PreparedRegularTabPlacementAdmission
    ) -> Bool {
        guard receipt.belongs(to: self), receipt.state == .committed else {
            return false
        }
        return endLease(receipt)
    }

    private func validate(
        _ receipt: PreparedRegularTabPlacementAdmission
    ) -> Bool {
        references.validate(receipt.lease, covers: receipt.profileIDs)
    }

    private func endLease(
        _ receipt: PreparedRegularTabPlacementAdmission
    ) -> Bool {
        references.endReferenceMutation(receipt.lease)
    }
}

@MainActor
final class PreparedRegularTabPlacementAdmission {
    enum State {
        case prepared
        case staged
        case committed
        case cancelled
        case abandoned
    }

    private unowned let authority: RegularTabPlacementAdmission
    let tab: Tab
    let sourceProfileID: UUID?
    let sourceAssignmentRevision: UInt64
    let profileIDs: Set<UUID>
    let lease: ProfileReferenceMutationLease
    let transition: TabSpaceProfileTransitionPreparation?
    var state = State.prepared

    init(
        authority: RegularTabPlacementAdmission,
        tab: Tab,
        sourceProfileID: UUID?,
        sourceAssignmentRevision: UInt64,
        profileIDs: Set<UUID>,
        lease: ProfileReferenceMutationLease,
        transition: TabSpaceProfileTransitionPreparation?
    ) {
        self.authority = authority
        self.tab = tab
        self.sourceProfileID = sourceProfileID
        self.sourceAssignmentRevision = sourceAssignmentRevision
        self.profileIDs = profileIDs
        self.lease = lease
        self.transition = transition
    }

    func belongs(to authority: RegularTabPlacementAdmission) -> Bool {
        self.authority === authority
    }

    func stage() -> Bool { authority.stage(self) }
    func settleProfile() -> Bool { authority.settleProfile(self) }
    func commit() -> Bool { authority.commit(self) }
    func canRollback() -> Bool { authority.canRollback(self) }
    func rollback() -> Bool { authority.rollback(self) }
    func cancel() -> Bool { authority.cancel(self) }
    func abandon() { authority.abandon(self) }
    func endCommittedLease() -> Bool { authority.endCommittedLease(self) }
}
