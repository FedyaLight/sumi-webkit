import Foundation

@MainActor
final class SumiImportRuntimeStore: SumiImportRuntimeMutating {
    private let profileManager: ProfileManager
    private let profileSelection: any SumiImportProfileSelection
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let state: TabStateStore
    private let structuralInstaller: TabStructuralInstallOwner
    private let persistence: TabStructuralPersistenceService
    private var activeMutation: (
        session: SumiImportRuntimeMutationSession,
        lease: ProfileReferenceMutationLease
    )?

    init(
        profileManager: ProfileManager,
        profileSelection: any SumiImportProfileSelection,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        state: TabStateStore,
        structuralInstaller: TabStructuralInstallOwner,
        persistence: TabStructuralPersistenceService
    ) {
        precondition(
            profileManager.profileReferenceAdmission === profileReferenceAdmission,
            "Import runtime owners must share one profile-reference admission ledger"
        )
        self.profileManager = profileManager
        self.profileSelection = profileSelection
        self.profileReferenceAdmission = profileReferenceAdmission
        self.state = state
        self.structuralInstaller = structuralInstaller
        self.persistence = persistence
    }

    func checkpoint() -> SumiImportRuntimeState {
        SumiImportRuntimeState(
            profiles: profileManager.profiles,
            currentProfile: profileSelection.currentProfile,
            spaces: state.spaces.spaces,
            tabsBySpace: state.regularTabs.tabsBySpaceSnapshot(),
            foldersBySpace: state.folders.foldersBySpaceSnapshot(),
            pinnedByProfile: state.shortcutPins.pinnedByProfileSnapshot(),
            spacePinnedShortcuts: state.shortcutPins.spacePinnedShortcutsSnapshot(),
            pendingPinnedWithoutProfile: state.shortcutPins
                .pendingPinnedWithoutProfileSnapshot(),
            splitGroups: state.splitGroups.groups,
            currentSpace: state.spaces.currentSpace,
            currentTab: state.selection.currentTab
        )
    }

    func beginMutation(
        covering candidates: [SumiImportRuntimeState]
    ) throws -> SumiImportRuntimeMutationSession {
        guard activeMutation == nil else {
            throw SumiImportRuntimeStoreError.mutationAlreadyActive
        }
        let profileIDs = candidates.reduce(into: Set<UUID>()) { result, state in
            result.formUnion(ProfileReferenceInventory(runtimeState: state).profileIDs)
        }
        let lease = try profileReferenceAdmission.beginReferenceMutation(
            to: profileIDs
        )
        let session = SumiImportRuntimeMutationSession()
        activeMutation = (session, lease)
        return session
    }

    func install(
        _ state: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        try await write(
            state,
            in: session,
            persistenceReason: "import transaction"
        )
    }

    func restore(
        _ checkpoint: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession
    ) async throws {
        try await write(
            checkpoint,
            in: session,
            persistenceReason: "import rollback"
        )
    }

    func endMutation(_ session: SumiImportRuntimeMutationSession) -> Bool {
        guard let activeMutation, activeMutation.session == session else {
            return false
        }
        guard profileReferenceAdmission.endReferenceMutation(
            activeMutation.lease
        ) else {
            return false
        }
        self.activeMutation = nil
        return true
    }

    private func write(
        _ state: SumiImportRuntimeState,
        in session: SumiImportRuntimeMutationSession,
        persistenceReason: String
    ) async throws {
        let inventory = ProfileReferenceInventory(runtimeState: state)
        guard let activeMutation, activeMutation.session == session else {
            throw SumiImportRuntimeStoreError.invalidMutationSession
        }
        let lease = activeMutation.lease
        guard profileReferenceAdmission.validate(
            lease,
            covers: inventory.profileIDs
        ) else {
            throw SumiImportRuntimeStoreError.referenceAdmissionLost
        }

        let targetProfileIDs = Set(state.profiles.map(\.id))
        let additiveProfiles = state.profiles + profileManager.profiles.filter {
            !targetProfileIDs.contains($0.id)
        }
        try profileManager.applyImportProfiles(
            additiveProfiles,
            mutationLease: lease
        )
        guard profileReferenceAdmission.validate(lease) else {
            throw SumiImportRuntimeStoreError.referenceAdmissionLost
        }
        profileSelection.applyImportProfileSelection(state.currentProfile)
        guard structuralInstaller.install(
            spaces: state.spaces,
            tabsBySpace: state.tabsBySpace,
            foldersBySpace: state.foldersBySpace,
            pinnedByProfile: state.pinnedByProfile,
            spacePinnedShortcuts: state.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: state.pendingPinnedWithoutProfile,
            splitGroups: state.splitGroups,
            currentSpace: state.currentSpace,
            currentTab: state.currentTab,
            referenceMutationLease: lease
        ) else {
            throw SumiImportRuntimeStoreError.structuralInstallRejected
        }
        guard await persistence.persistFullReconcileAwaitingResult(
            reason: persistenceReason
        ) else {
            throw SumiImportTransactionError.runtimePersistenceFailed
        }
        guard profileReferenceAdmission.validate(lease) else {
            throw SumiImportRuntimeStoreError.referenceAdmissionLost
        }
    }
}

private enum SumiImportRuntimeStoreError: Error {
    case mutationAlreadyActive
    case invalidMutationSession
    case referenceAdmissionLost
    case structuralInstallRejected
}
