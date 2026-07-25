import Foundation
import SumiDomain

@MainActor
final class TabStructuralInstallOwner {
    private let state: TabStateStore
    private let structuralLookup: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private let publication: TabStructuralInstallPublication
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger

    init(
        state: TabStateStore,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService,
        publication: TabStructuralInstallPublication,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) {
        self.state = state
        self.structuralLookup = structuralLookup
        self.persistence = persistence
        self.publication = publication
        self.profileReferenceAdmission = profileReferenceAdmission
    }

    @discardableResult
    func installRestoredCollections(
        _ restoredState: TabRestoreRuntimeState,
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        admitted: @escaping @MainActor () -> Bool,
        onInstalled: @escaping @MainActor () -> Void
    ) -> Bool {
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: ProfileReferenceInventory(
                    spaces: restoredState.spaces,
                    tabsBySpace: restoredState.tabsBySpace,
                    pinnedByProfile: restoredState.pinnedByProfile,
                    spacePinnedShortcuts: restoredState.spacePinnedShortcuts,
                    pendingPinnedWithoutProfile: restoredState.pendingPinnedWithoutProfile,
                    splitGroups: splitGroups,
                    currentSpace: currentSpace,
                    currentTab: currentTab
                ).profileIDs
            )
        } catch {
            return false
        }
        defer { endReferenceMutation(lease) }
        return installCore(
            spaces: restoredState.spaces,
            tabsBySpace: restoredState.tabsBySpace,
            foldersBySpace: restoredState.foldersBySpace,
            pinnedByProfile: restoredState.pinnedByProfile,
            spacePinnedShortcuts: restoredState.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: restoredState.pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab,
            resetDirtyState: false,
            referenceMutationLease: lease,
            admitted: admitted,
            onInstalled: onInstalled
        )
    }

    @discardableResult
    func install(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        foldersBySpace: [UUID: [TabFolder]],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin],
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        resetDirtyState: Bool = true,
        admitted: @escaping @MainActor () -> Bool = { true }
    ) -> Bool {
        let inventory = ProfileReferenceInventory(
            spaces: spaces,
            tabsBySpace: tabsBySpace,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab
        )
        let lease: ProfileReferenceMutationLease
        do {
            lease = try profileReferenceAdmission.beginReferenceMutation(
                to: inventory.profileIDs
            )
        } catch {
            return false
        }
        defer { endReferenceMutation(lease) }
        return installCore(
            spaces: spaces,
            tabsBySpace: tabsBySpace,
            foldersBySpace: foldersBySpace,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab,
            resetDirtyState: resetDirtyState,
            referenceMutationLease: lease,
            admitted: admitted,
            onInstalled: {}
        )
    }

    @discardableResult
    func install(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        foldersBySpace: [UUID: [TabFolder]],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin],
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        resetDirtyState: Bool = true,
        referenceMutationLease: ProfileReferenceMutationLease
    ) -> Bool {
        installCore(
            spaces: spaces,
            tabsBySpace: tabsBySpace,
            foldersBySpace: foldersBySpace,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab,
            resetDirtyState: resetDirtyState,
            referenceMutationLease: referenceMutationLease,
            admitted: { true },
            onInstalled: {}
        )
    }

    private func installCore(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        foldersBySpace: [UUID: [TabFolder]],
        pinnedByProfile: [UUID: [ShortcutPin]],
        spacePinnedShortcuts: [UUID: [ShortcutPin]],
        pendingPinnedWithoutProfile: [ShortcutPin],
        splitGroups: [SplitGroup],
        currentSpace: Space?,
        currentTab: Tab?,
        resetDirtyState: Bool,
        referenceMutationLease: ProfileReferenceMutationLease,
        admitted: @escaping @MainActor () -> Bool,
        onInstalled: @escaping @MainActor () -> Void
    ) -> Bool {
        let inventory = ProfileReferenceInventory(
            spaces: spaces,
            tabsBySpace: tabsBySpace,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            pendingPinnedWithoutProfile: pendingPinnedWithoutProfile,
            splitGroups: splitGroups,
            currentSpace: currentSpace,
            currentTab: currentTab
        )
        guard profileReferenceAdmission.validate(
            referenceMutationLease,
            covers: inventory.profileIDs
        ) else {
            return false
        }
        var didInstall = false
        structuralLookup.withTransaction {
            guard admitted(), profileReferenceAdmission.validate(
                referenceMutationLease,
                covers: inventory.profileIDs
            ) else { return }
            publication.willInstallState()
            guard admitted(), profileReferenceAdmission.validate(
                referenceMutationLease,
                covers: inventory.profileIDs
            ) else { return }
            state.spaces.replaceSpaces(spaces)
            state.regularTabs.replaceTabsBySpace(tabsBySpace)
            state.folders.replaceFoldersBySpace(foldersBySpace)
            for (spaceID, folders) in foldersBySpace where !folders.isEmpty {
                structuralLookup.publishFolderExpansionChange(
                    spaceID: spaceID,
                    expansionByFolderID: Dictionary(
                        uniqueKeysWithValues: folders.map {
                            ($0.id, $0.isOpen)
                        }
                    )
                )
            }
            state.splitGroups.replaceAll(with: splitGroups)
            state.shortcutPins.replaceAll(
                pinnedByProfile: pinnedByProfile,
                spacePinnedShortcuts: spacePinnedShortcuts,
                pendingPinnedWithoutProfile: pendingPinnedWithoutProfile
            )
            state.spaces.replaceCurrentSpace(currentSpace)
            state.selection.replaceCurrentTab(currentTab)
            structuralLookup.rebuild()
            persistence.markSnapshotCacheDirty()
            if resetDirtyState {
                persistence.resetDirtySet()
            }
            structuralLookup.requestPublish()
            onInstalled()
            didInstall = true
            publication.didInstallShortcuts(
                pinnedByProfile: pinnedByProfile,
                spacePinnedShortcuts: spacePinnedShortcuts
            )
        }
        return didInstall
    }

    private func endReferenceMutation(_ lease: ProfileReferenceMutationLease) {
        precondition(
            profileReferenceAdmission.endReferenceMutation(lease),
            "Tab structural install lost its exact profile-reference mutation lease"
        )
    }
}
