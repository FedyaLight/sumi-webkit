import Foundation

/// Holds the admission lease across an ordered, replayable browser-shell
/// migration and validates the complete inventory before releasing it.
@MainActor
final class BrowserProfileReferenceMigrationTransaction {
    private let liveWindows: @MainActor () -> [BrowserWindowState]?
    private let primaryWindowSnapshotStore: WindowSessionSnapshotStore
    private let lastSessionWindowsStore: LastSessionWindowsStore
    private let startupRestore: BrowserStartupSessionRestoreOwner
    private let profileReferenceAdmission: ProfileReferenceAdmissionLedger
    private let recentlyClosedManager: RecentlyClosedManager
    private let glanceManager: GlanceManager
    private let inventory: BrowserProfileReferenceInventory

    init(
        liveWindows: @escaping @MainActor () -> [BrowserWindowState]?,
        primaryWindowSnapshotStore: WindowSessionSnapshotStore,
        lastSessionWindowsStore: LastSessionWindowsStore,
        startupRestore: BrowserStartupSessionRestoreOwner,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        recentlyClosedManager: RecentlyClosedManager,
        glanceManager: GlanceManager,
        inventory: BrowserProfileReferenceInventory
    ) {
        self.liveWindows = liveWindows
        self.primaryWindowSnapshotStore = primaryWindowSnapshotStore
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.startupRestore = startupRestore
        self.profileReferenceAdmission = profileReferenceAdmission
        self.recentlyClosedManager = recentlyClosedManager
        self.glanceManager = glanceManager
        self.inventory = inventory
    }

    func migrate(
        from deletedProfileID: UUID,
        to fallbackProfileID: UUID
    ) -> Bool {
        guard let liveWindows = liveWindows() else { return false }

        let mutationLease: ProfileReferenceMutationLease
        do {
            mutationLease = try profileReferenceAdmission
                .beginRetirementReferenceMigration(to: [fallbackProfileID])
        } catch {
            return false
        }

        for window in liveWindows
        where window.currentProfileId == deletedProfileID {
            window.currentProfileId = fallbackProfileID
        }

        let migrationSucceeded = recentlyClosedManager.retireProfileReferences(
            to: deletedProfileID,
            mutationLease: mutationLease
        )
            && glanceManager.retireProfileReference(to: deletedProfileID)
            && primaryWindowSnapshotStore
            .migrateDurableWindowProfileReference(
                from: deletedProfileID,
                to: fallbackProfileID
            )
            && lastSessionWindowsStore.migrateProfileReferences(
                from: deletedProfileID,
                to: fallbackProfileID
            )
            && startupRestore.migrateCachedProfileReferences(
                from: deletedProfileID,
                to: fallbackProfileID
            )
            && profileReferenceAdmission.validate(
                mutationLease,
                covers: [fallbackProfileID]
            )
            && inventory.containsReference(to: deletedProfileID) == false

        guard profileReferenceAdmission.endReferenceMutation(mutationLease)
        else { return false }
        return migrationSucceeded
    }
}
