import Foundation

@MainActor
final class SumiImportRuntimeStore: SumiImportRuntimeMutating {
    private let profileManager: ProfileManager
    private let tabManager: TabManager
    private unowned let profileSelection: any SumiImportProfileSelection

    init(
        profileManager: ProfileManager,
        tabManager: TabManager,
        profileSelection: any SumiImportProfileSelection
    ) {
        self.profileManager = profileManager
        self.tabManager = tabManager
        self.profileSelection = profileSelection
    }

    func checkpoint() -> SumiImportRuntimeState {
        SumiImportRuntimeState(
            profiles: profileManager.profiles,
            currentProfile: profileSelection.currentProfile,
            spaces: tabManager.spaceStateOwner.spaces,
            tabsBySpace: tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot(),
            foldersBySpace: tabManager.folderCollectionStateOwner.foldersBySpaceSnapshot(),
            pinnedByProfile: tabManager.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot(),
            spacePinnedShortcuts: tabManager.shortcutPinCollectionStateOwner
                .spacePinnedShortcutsSnapshot(),
            pendingPinnedWithoutProfile: tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot(),
            splitGroups: tabManager.splitGroupCollectionStateOwner.splitGroups,
            currentSpace: tabManager.spaceStateOwner.currentSpace,
            currentTab: tabManager.selectionStateOwner.currentTab
        )
    }

    func install(_ state: SumiImportRuntimeState) async throws {
        try await write(state, persistenceReason: "import transaction")
    }

    func restore(_ checkpoint: SumiImportRuntimeState) async throws {
        try await write(checkpoint, persistenceReason: "import rollback")
    }

    private func write(
        _ state: SumiImportRuntimeState,
        persistenceReason: String
    ) async throws {
        try profileManager.replaceProfiles(with: state.profiles)
        profileSelection.currentProfile = state.currentProfile
        tabManager.structuralInstallOwner.install(
            spaces: state.spaces,
            tabsBySpace: state.tabsBySpace,
            foldersBySpace: state.foldersBySpace,
            pinnedByProfile: state.pinnedByProfile,
            spacePinnedShortcuts: state.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: state.pendingPinnedWithoutProfile,
            splitGroups: state.splitGroups,
            currentSpace: state.currentSpace,
            currentTab: state.currentTab
        )
        guard await tabManager.structuralPersistence.persistFullReconcileAwaitingResult(reason: persistenceReason) else {
            throw SumiImportTransactionError.runtimePersistenceFailed
        }
    }
}
