import Combine
import Observation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class BrowserProfileReferenceRetirementCoordinatorTests: XCTestCase {
    func testMigrationMovesProcessEveryLiveWindowAndDurableSessionProjection() async throws {
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        var currentProfile: Profile? = deleted
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let unaffectedWindow = BrowserWindowState()
        firstWindow.currentProfileId = deleted.id
        secondWindow.currentProfileId = deleted.id
        unaffectedWindow.currentProfileId = fallback.id

        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        var primarySnapshot = makeSessionRecoveryWindowSession(
            currentTabId: UUID(),
            isShowingEmptyState: true
        )
        primarySnapshot.currentProfileId = deleted.id
        XCTAssertTrue(primaryStore.persist(primarySnapshot))

        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        var archivedSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        archivedSession.currentProfileId = deleted.id
        let archivedWindow = LastSessionWindowSnapshot(
            id: UUID(),
            session: archivedSession
        )
        let archivedTabSnapshot = try makeTabSnapshot(
            deletedProfileID: deleted.id,
            fallbackProfileID: fallback.id
        )
        XCTAssertTrue(
            archiveStore.updateSnapshots(
                [archivedWindow],
                tabSnapshot: archivedTabSnapshot
            )
        )
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let profileReferenceAdmission = try makeReservedAdmission(
            deleted: deleted,
            fallback: fallback
        )
        var reentrantMutationError: ProfileReferenceAdmissionLedgerError?
        withObservationTracking {
            _ = firstWindow.currentProfileId
        } onChange: {
            MainActor.assumeIsolated {
                do {
                    _ = try profileReferenceAdmission
                        .beginRetirementReferenceMigration(to: [fallback.id])
                } catch let error as ProfileReferenceAdmissionLedgerError {
                    reentrantMutationError = error
                } catch {
                    XCTFail("Unexpected mutation error: \(error)")
                }
            }
        }
        var switchedProfiles: [UUID] = []

        let coordinator = makeCoordinator(
                currentProfile: { currentProfile },
                switchToProfile: { profile in
                    switchedProfiles.append(profile.id)
                    currentProfile = profile
                },
                liveWindows: {
                    [firstWindow, secondWindow, unaffectedWindow]
                },
                primaryWindowSnapshotStore: primaryStore,
                lastSessionWindowsStore: archiveStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: profileReferenceAdmission,
                hasTabReference: { _ in false },
                prepareLiveFolderReferences: { true },
                recentlyClosedManager: RecentlyClosedManager(
                    profileReferenceAdmission: profileReferenceAdmission
                ),
                glanceManager: GlanceManager(),
                retireExtensionRuntimeProfile: { _, _ in true },
                extensionRuntimeContainsReference: { _ in false }
        )

        XCTAssertTrue(coordinator.containsReference(to: deleted.id))
        var didPrepareTabReferences = false
        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback,
            migrateTabReferences: {
                XCTAssertEqual(currentProfile?.id, fallback.id)
                didPrepareTabReferences = true
                return true
            }
        )
        XCTAssertTrue(didMigrate)
        XCTAssertTrue(didPrepareTabReferences)
        XCTAssertEqual(switchedProfiles, [fallback.id])
        XCTAssertEqual(reentrantMutationError, .mutationInProgress)
        XCTAssertEqual(firstWindow.currentProfileId, fallback.id)
        XCTAssertEqual(secondWindow.currentProfileId, fallback.id)
        XCTAssertEqual(unaffectedWindow.currentProfileId, fallback.id)
        XCTAssertEqual(
            try XCTUnwrap(primaryStore.loadSnapshot()).snapshot.currentProfileId,
            fallback.id
        )
        XCTAssertEqual(
            try XCTUnwrap(archiveStore.snapshots.first).session.currentProfileId,
            fallback.id
        )
        XCTAssertEqual(
            try XCTUnwrap(startupRestore.windowSnapshots.first)
                .session.currentProfileId,
            fallback.id
        )
        XCTAssertEqual(
            try XCTUnwrap(primaryStore.loadSnapshot()).snapshot.currentTabId,
            primarySnapshot.currentTabId
        )
        XCTAssertEqual(
            try XCTUnwrap(archiveStore.snapshots.first).session.currentTabId,
            archivedSession.currentTabId
        )
        XCTAssertFalse(
            try XCTUnwrap(archiveStore.tabSnapshot).profileIDs
                .contains(deleted.id)
        )
        XCTAssertFalse(
            try XCTUnwrap(startupRestore.tabSnapshot).profileIDs
                .contains(deleted.id)
        )
        XCTAssertEqual(
            try XCTUnwrap(archiveStore.tabSnapshot).tabs.first?.name,
            archivedTabSnapshot.tabs.first?.name
        )
        XCTAssertFalse(coordinator.containsReference(to: deleted.id))
    }

    func testMigrationFailsClosedWhenCanonicalSwitchDoesNotMoveProcessProfile() async throws {
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let currentProfile: Profile? = deleted
        let profileReferenceAdmission = try makeReservedAdmission(
            deleted: deleted,
            fallback: fallback
        )
        let coordinator = makeCoordinator(
                currentProfile: { currentProfile },
                switchToProfile: { _ in },
                liveWindows: { [] },
                primaryWindowSnapshotStore: primaryStore,
                lastSessionWindowsStore: archiveStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: profileReferenceAdmission,
                hasTabReference: { _ in false },
                prepareLiveFolderReferences: { true },
                recentlyClosedManager: RecentlyClosedManager(
                    profileReferenceAdmission: profileReferenceAdmission
                ),
                glanceManager: GlanceManager(),
                retireExtensionRuntimeProfile: { _, _ in true },
                extensionRuntimeContainsReference: { _ in false }
        )

        var didAttemptTabMigration = false
        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback,
            migrateTabReferences: {
                didAttemptTabMigration = true
                return true
            }
        )
        XCTAssertFalse(didMigrate)
        XCTAssertFalse(didAttemptTabMigration)
        XCTAssertEqual(currentProfile?.id, deleted.id)
        XCTAssertTrue(coordinator.containsReference(to: deleted.id))
    }

    func testMigrationFailsClosedWhileWindowAuthorityIsUnavailable() async throws {
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let profileReferenceAdmission = try makeReservedAdmission(
            deleted: deleted,
            fallback: fallback
        )
        let coordinator = makeCoordinator(
            currentProfile: { fallback },
            switchToProfile: { _ in },
            liveWindows: { nil },
            primaryWindowSnapshotStore: primaryStore,
            lastSessionWindowsStore: archiveStore,
            startupRestore: startupRestore,
            profileReferenceAdmission: profileReferenceAdmission,
            hasTabReference: { _ in false },
            prepareLiveFolderReferences: { true },
            recentlyClosedManager: RecentlyClosedManager(
                profileReferenceAdmission: profileReferenceAdmission
            ),
            glanceManager: GlanceManager(),
            retireExtensionRuntimeProfile: { _, _ in true },
            extensionRuntimeContainsReference: { _ in false }
        )

        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback
        )
        XCTAssertFalse(didMigrate)
        XCTAssertTrue(coordinator.containsReference(to: deleted.id))

        let lease = try profileReferenceAdmission
            .beginRetirementReferenceMigration(to: [fallback.id])
        XCTAssertTrue(
            profileReferenceAdmission.endReferenceMutation(lease)
        )
    }

    func testOverrideSessionIsNeverRewrittenByRetirementMigration() throws {
        let deletedID = UUID()
        let fallbackID = UUID()
        var durableSnapshot = makeSessionRecoveryWindowSession()
        durableSnapshot.currentProfileId = deletedID
        let overrideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumi-profile-retirement-\(UUID()).json")
        var overrideSnapshot = makeSessionRecoveryWindowSession(
            currentTabId: UUID()
        )
        overrideSnapshot.currentProfileId = deletedID
        let overrideData = try WindowSessionSnapshotCodec().encode(
            overrideSnapshot
        )
        try overrideData.write(to: overrideURL, options: .atomic)
        addTeardownBlock { try? FileManager.default.removeItem(at: overrideURL) }
        let store = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window",
            environment: {
                [WindowSessionSnapshotStore.overridePathEnvironmentKey: overrideURL.path]
            }
        )
        XCTAssertTrue(store.persist(durableSnapshot))

        XCTAssertTrue(
            store.migrateDurableWindowProfileReference(
                from: deletedID,
                to: fallbackID
            )
        )

        XCTAssertEqual(try Data(contentsOf: overrideURL), overrideData)
        guard case .loaded(let loadedOverride, _) = store.loadResult() else {
            return XCTFail("Expected immutable override snapshot")
        }
        XCTAssertEqual(loadedOverride.currentProfileId, deletedID)
        XCTAssertFalse(store.containsDurableWindowProfileReference(to: deletedID))
    }

    func testTabInventoryStillBlocksRetirementAfterWindowReferencesMigrate() async throws {
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let profileReferenceAdmission = try makeReservedAdmission(
            deleted: deleted,
            fallback: fallback
        )
        let coordinator = makeCoordinator(
                currentProfile: { fallback },
                switchToProfile: { _ in },
                liveWindows: { [] },
                primaryWindowSnapshotStore: primaryStore,
                lastSessionWindowsStore: archiveStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: profileReferenceAdmission,
                hasTabReference: { $0 == deleted.id },
                prepareLiveFolderReferences: { true },
                recentlyClosedManager: RecentlyClosedManager(
                    profileReferenceAdmission: profileReferenceAdmission
                ),
                glanceManager: GlanceManager(),
                retireExtensionRuntimeProfile: { _, _ in true },
                extensionRuntimeContainsReference: { _ in false }
        )

        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback
        )
        XCTAssertFalse(didMigrate)
        XCTAssertTrue(coordinator.containsReference(to: deleted.id))
    }

    func testExtensionInventoryStillBlocksRetirementAfterRuntimeMigration() async throws {
        let deleted = Profile(name: "Deleted")
        let fallback = Profile(name: "Fallback")
        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let profileReferenceAdmission = try makeReservedAdmission(
            deleted: deleted,
            fallback: fallback
        )
        var didRequestRuntimeRetirement = false
        let coordinator = makeCoordinator(
                currentProfile: { fallback },
                switchToProfile: { _ in },
                liveWindows: { [] },
                primaryWindowSnapshotStore: primaryStore,
                lastSessionWindowsStore: archiveStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: profileReferenceAdmission,
                hasTabReference: { _ in false },
                prepareLiveFolderReferences: { true },
                recentlyClosedManager: RecentlyClosedManager(
                    profileReferenceAdmission: profileReferenceAdmission
                ),
                glanceManager: GlanceManager(),
                retireExtensionRuntimeProfile: { profileID, fallbackProfileID in
                    didRequestRuntimeRetirement = profileID == deleted.id
                        && fallbackProfileID == fallback.id
                    return true
                },
                extensionRuntimeContainsReference: { $0 == deleted.id }
        )

        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback
        )

        XCTAssertTrue(didRequestRuntimeRetirement)
        XCTAssertFalse(didMigrate)
        XCTAssertTrue(coordinator.containsReference(to: deleted.id))
    }

    func testGlancePublicationHoldsAdmissionLeaseUntilSessionIsVisible() throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        var reservationError: ProfileReferenceAdmissionLedgerError?
        var attemptedReservation = false
        let publication = browserManager.glanceManager.objectWillChange.sink {
            guard attemptedReservation == false,
                  browserManager.glanceManager.currentSession == nil
            else { return }
            attemptedReservation = true
            do {
                _ = try browserManager.profileReferenceAdmission.reserve(
                    profile: deleted,
                    fallbackID: fallback.id
                )
            } catch {
                reservationError = error as? ProfileReferenceAdmissionLedgerError
            }
        }

        XCTAssertTrue(
            browserManager.glanceManager.presentExternalURL(
                URL(string: "https://glance-publication.example")!,
                from: nil
            )
        )
        withExtendedLifetime(publication) {}

        XCTAssertTrue(attemptedReservation)
        XCTAssertEqual(reservationError, .mutationInProgress)
        XCTAssertEqual(
            browserManager.glanceManager.currentSession?.previewTab.profileId,
            deleted.id
        )

        let token = try browserManager.profileReferenceAdmission.reserve(
            profile: deleted,
            fallbackID: fallback.id
        )
        XCTAssertTrue(
            try browserManager.profileReferenceAdmission.cancel(token)
        )
        browserManager.glanceManager.dismissGlance(
            persistsWindowSession: false
        )
    }

    func testReservedProfileRejectsGlanceBeforeSessionPublication() throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        let token = try browserManager.profileReferenceAdmission.reserve(
            profile: deleted,
            fallbackID: fallback.id
        )

        XCTAssertFalse(
            browserManager.glanceManager.presentExternalURL(
                URL(string: "https://blocked-glance.example")!,
                from: nil
            )
        )
        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertTrue(
            try browserManager.profileReferenceAdmission.cancel(token)
        )
    }

    func testGlanceInventoryBlocksUntilRetirementClosesPreview() async throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        XCTAssertTrue(
            browserManager.glanceManager.presentExternalURL(
                URL(string: "https://glance-retirement.example")!,
                from: nil
            )
        )
        let previewTab = try XCTUnwrap(
            browserManager.glanceManager.currentSession?.previewTab
        )
        XCTAssertEqual(previewTab.profileId, deleted.id)

        let primaryStore = WindowSessionSnapshotStore(
            database: try! SumiDatabase.inMemory(),
            key: "window"
        )
        let archiveStore = LastSessionWindowsStore(database: try! SumiDatabase.inMemory())
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: archiveStore
        )
        let retirementToken = try browserManager.profileReferenceAdmission.reserve(
            profile: deleted,
            fallbackID: fallback.id
        )
        XCTAssertTrue(
            try browserManager.profileReferenceAdmission
                .beginReferenceMigration(retirementToken)
        )
        let coordinator = makeCoordinator(
                currentProfile: { browserManager.currentProfile },
                switchToProfile: { browserManager.currentProfile = $0 },
                liveWindows: { [] },
                primaryWindowSnapshotStore: primaryStore,
                lastSessionWindowsStore: archiveStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: browserManager
                    .profileReferenceAdmission,
                hasTabReference: { _ in false },
                prepareLiveFolderReferences: { true },
                recentlyClosedManager: browserManager.recentlyClosedManager,
                glanceManager: browserManager.glanceManager,
                retireExtensionRuntimeProfile: { _, _ in true },
                extensionRuntimeContainsReference: { _ in false }
        )

        XCTAssertTrue(coordinator.containsReference(to: deleted.id))
        let didMigrate = await coordinator.migrateReferences(
            from: deleted.id,
            to: fallback
        )
        XCTAssertTrue(didMigrate)
        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertFalse(coordinator.containsReference(to: deleted.id))
    }

    func testPreparedArchivedWindowHoldsRetirementLeaseUntilCancellation() throws {
        let browserManager = BrowserManager()
        let deleted = try XCTUnwrap(browserManager.currentProfile)
        let fallback = try browserManager.profileManager.createProfile(
            name: "Fallback"
        )
        var session = makeSessionRecoveryWindowSession()
        session.currentProfileId = deleted.id
        let window = BrowserWindowState()

        XCTAssertTrue(
            browserManager.windowSessionBundle.restoreService
                .prepareArchivedWindow(
                    LastSessionWindowSnapshot(id: UUID(), session: session),
                    forRegistration: window
                )
        )
        XCTAssertThrowsError(
            try browserManager.profileReferenceAdmission.reserve(
                profile: deleted,
                fallbackID: fallback.id
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .mutationInProgress
            )
        }

        XCTAssertTrue(
            browserManager.windowSessionBundle.restoreService
                .cancelPreparedWindowRegistration(window)
        )
        let token = try browserManager.profileReferenceAdmission.reserve(
            profile: deleted,
            fallbackID: fallback.id
        )
        XCTAssertTrue(
            try browserManager.profileReferenceAdmission.cancel(token)
        )
    }

    private func makeCoordinator(
        currentProfile: @escaping @MainActor () -> Profile?,
        switchToProfile: @escaping @MainActor (Profile) async -> Void,
        liveWindows: @escaping @MainActor () -> [BrowserWindowState]?,
        primaryWindowSnapshotStore: WindowSessionSnapshotStore,
        lastSessionWindowsStore: LastSessionWindowsStore,
        startupRestore: BrowserStartupSessionRestoreOwner,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        hasTabReference: @escaping @MainActor (UUID) -> Bool,
        prepareLiveFolderReferences: @escaping @MainActor () async -> Bool,
        recentlyClosedManager: RecentlyClosedManager,
        glanceManager: GlanceManager,
        retireExtensionRuntimeProfile: @escaping @MainActor (
            UUID,
            UUID
        ) -> Bool,
        extensionRuntimeContainsReference: @escaping @MainActor (UUID) -> Bool
    ) -> BrowserProfileReferenceRetirementCoordinator {
        let inventory = BrowserProfileReferenceInventory(
            currentProfile: currentProfile,
            liveWindows: liveWindows,
            hasTabReference: hasTabReference,
            primaryWindowSnapshotStore: primaryWindowSnapshotStore,
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupRestore: startupRestore,
            recentlyClosedManager: recentlyClosedManager,
            glanceManager: glanceManager,
            extensionRuntimeContainsReference: extensionRuntimeContainsReference
        )
        return BrowserProfileReferenceRetirementCoordinator(
            preflight: BrowserProfileRetirementPreflight(
                currentProfile: currentProfile,
                switchToProfile: switchToProfile,
                prepareLiveFolderReferences: prepareLiveFolderReferences,
                retireExtensionRuntimeProfile: retireExtensionRuntimeProfile
            ),
            migration: BrowserProfileReferenceMigrationTransaction(
                liveWindows: liveWindows,
                primaryWindowSnapshotStore: primaryWindowSnapshotStore,
                lastSessionWindowsStore: lastSessionWindowsStore,
                startupRestore: startupRestore,
                profileReferenceAdmission: profileReferenceAdmission,
                recentlyClosedManager: recentlyClosedManager,
                glanceManager: glanceManager,
                inventory: inventory
            ),
            inventory: inventory
        )
    }

    private func makeTabSnapshot(
        deletedProfileID: UUID,
        fallbackProfileID: UUID
    ) throws -> TabPersistenceSnapshot {
        let spaceID = UUID()
        let firstPinID = UUID()
        let secondPinID = UUID()
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(firstPinID),
                    .shortcutPin(secondPinID),
                ],
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: spaceID,
                    profileId: deletedProfileID,
                    folderId: nil,
                    index: 2
                )
            )
        )
        return TabPersistenceSnapshot(
            spaces: [
                TabPersistenceSpace(
                    id: spaceID,
                    name: "Archived Space",
                    icon: "square",
                    index: 0,
                    workspaceThemeData: Data([1, 2, 3]),
                    profileId: deletedProfileID
                ),
            ],
            tabs: [
                TabPersistenceTab(
                    id: UUID(),
                    urlString: "https://example.com",
                    name: "Archived Tab",
                    index: 0,
                    spaceId: spaceID,
                    isPinned: true,
                    isSpacePinned: false,
                    profileId: deletedProfileID,
                    executionProfileId: deletedProfileID,
                    folderId: nil,
                    iconAsset: "globe",
                    currentURLString: "https://example.com/current",
                    canGoBack: true,
                    canGoForward: false
                ),
            ],
            folders: [],
            splitGroups: [group],
            state: TabPersistenceSelection(
                currentTabID: nil,
                currentSpaceID: spaceID
            )
        )
    }

    private func makeReservedAdmission(
        deleted: Profile,
        fallback: Profile
    ) throws -> ProfileReferenceAdmissionLedger {
        let database = try makeInMemoryStartupDatabase()
        try database.transaction {
            try $0.profiles.save(
                ProfileRecord(
                id: deleted.id,
                name: deleted.name,
                index: 0
                )
            )
            try $0.profiles.save(
                ProfileRecord(
                id: fallback.id,
                name: fallback.name,
                index: 1
                )
            )
        }
        let admission = try ProfileReferenceAdmissionLedger(database: database)
        let token = try admission.reserve(
            profile: deleted,
            fallbackID: fallback.id
        )
        _ = try admission.beginReferenceMigration(token)
        return admission
    }
}

@MainActor
private extension TabPersistenceSnapshot {
    var profileIDs: Set<UUID> {
        ProfileReferenceInventory(tabSnapshot: self).profileIDs
    }
}
