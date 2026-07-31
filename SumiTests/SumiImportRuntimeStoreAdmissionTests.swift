import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SumiImportRuntimeStoreAdmissionTests: XCTestCase {
    func testImportProfileSnapshotCanAddButNotRemoveIdentities() throws {
        let container = try makeInMemoryStartupDatabase()
        let profileManager = ProfileManager(database: container)
        let original = try profileManager.createProfile(name: "Original")
        let imported = Profile(name: "Imported")
        let lease = try profileManager.profileReferenceAdmission
            .beginReferenceMutation(to: [original.id, imported.id])
        defer {
            XCTAssertTrue(
                profileManager.profileReferenceAdmission
                    .endReferenceMutation(lease)
            )
        }

        try profileManager.applyImportProfiles(
            [original, imported],
            mutationLease: lease
        )

        XCTAssertEqual(profileManager.profiles.map(\.id), [original.id, imported.id])
        XCTAssertThrowsError(
            try profileManager.applyImportProfiles(
                [imported],
                mutationLease: lease
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileManagerMutationError,
                .invalidImportMutationLease
            )
        }
    }

    func testProfileSnapshotReplacementCannotBypassDurableRetirement() throws {
        let container = try makeInMemoryStartupDatabase()
        let profileManager = ProfileManager(database: container)
        let original = try profileManager.createProfile(name: "Original")

        XCTAssertThrowsError(
            try profileManager.replaceProfiles(with: [Profile(name: "Replacement")])
        ) { error in
            XCTAssertEqual(
                error as? ProfileManagerMutationError,
                .profileIdentityMutationRequiresRetirement
            )
        }
        XCTAssertEqual(profileManager.profiles.map(\.id), [original.id])
        let entities = try container.read { try $0.profiles.all() }
        XCTAssertEqual(entities.map(\.id), [original.id])
    }

    func testRollbackLeaseCoversImportedProfilesWithoutStructuralReferences() async throws {
        let container = try makeInMemoryStartupDatabase()
        let profileManager = ProfileManager(database: container)
        let original = try profileManager.createProfile(name: "Original")
        let imported = try profileManager.createProfile(name: "Imported")
        let admission = profileManager.profileReferenceAdmission
        let tabManager = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: admission,
            loadPersistedState: false
        )
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: tabManager.stateStore
        )
        let structuralInstall = TabStructuralInstallOwner(
            state: tabManager.stateStore,
            structuralLookup: structuralLookup,
            persistence: tabManager.structuralPersistence,
            publication: TabStructuralInstallPublication(
                changes: tabManager.objectWillChange,
                faviconService: tabManager.faviconService
            ),
            profileReferenceAdmission: admission
        )
        let store = SumiImportRuntimeStore(
            profileManager: profileManager,
            profileSelection: ImportProfileSelectionOracle(),
            profileReferenceAdmission: admission,
            state: tabManager.stateStore,
            structuralInstaller: structuralInstall,
            persistence: tabManager.structuralPersistence
        )
        let space = Space(name: "Original", profileId: original.id)
        let current = SumiImportRuntimeState(
            profiles: [original, imported],
            currentProfile: original,
            spaces: [space],
            tabsBySpace: [space.id: []],
            foldersBySpace: [space.id: []],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: nil
        )
        let rollback = SumiImportRuntimeState(
            profiles: [original],
            currentProfile: original,
            spaces: current.spaces,
            tabsBySpace: current.tabsBySpace,
            foldersBySpace: current.foldersBySpace,
            pinnedByProfile: current.pinnedByProfile,
            spacePinnedShortcuts: current.spacePinnedShortcuts,
            pendingPinnedWithoutProfile: current.pendingPinnedWithoutProfile,
            splitGroups: current.splitGroups,
            currentSpace: current.currentSpace,
            currentTab: current.currentTab
        )

        let session = try store.beginMutation(covering: [current, rollback])
        defer { XCTAssertTrue(store.endMutation(session)) }
        try await store.restore(rollback, in: session)

        XCTAssertEqual(Set(profileManager.profiles.map(\.id)), [original.id, imported.id])
        XCTAssertEqual(tabManager.stateStore.spaces.spaces.map(\.id), [space.id])
    }

    func testUnavailableAdmissionRejectsImportBeforeAnyRuntimeMutation() async throws {
        let container = try makeInMemoryStartupDatabase()
        let admission = ProfileReferenceAdmissionLedger.failClosed()
        let profileManager = ProfileManager(
            database: container,
            profileReferenceAdmission: admission
        )
        let tabManager = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: admission,
            loadPersistedState: false
        )
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: tabManager.tabStructureEventBus,
            stateStore: tabManager.stateStore
        )
        let structuralInstall = TabStructuralInstallOwner(
            state: tabManager.stateStore,
            structuralLookup: structuralLookup,
            persistence: tabManager.structuralPersistence,
            publication: TabStructuralInstallPublication(
                changes: tabManager.objectWillChange,
                faviconService: tabManager.faviconService
            ),
            profileReferenceAdmission: admission
        )
        let selection = ImportProfileSelectionOracle()
        let store = SumiImportRuntimeStore(
            profileManager: profileManager,
            profileSelection: selection,
            profileReferenceAdmission: admission,
            state: tabManager.stateStore,
            structuralInstaller: structuralInstall,
            persistence: tabManager.structuralPersistence
        )
        let profile = Profile(name: "Blocked")
        let space = Space(name: "Blocked", profileId: profile.id)
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: "Blocked",
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        let revisionBefore = structuralLookup.mutationRevision
        let candidate = SumiImportRuntimeState(
            profiles: [profile],
            currentProfile: profile,
            spaces: [space],
            tabsBySpace: [space.id: [tab]],
            foldersBySpace: [:],
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [],
            splitGroups: [],
            currentSpace: space,
            currentTab: tab
        )

        do {
            let session = try store.beginMutation(covering: [candidate])
            defer { XCTAssertTrue(store.endMutation(session)) }
            try await store.install(candidate, in: session)
            XCTFail("Unavailable admission must reject the import")
        } catch let error as ProfileReferenceAdmissionLedgerError {
            XCTAssertEqual(error, .unavailable)
        }

        XCTAssertTrue(profileManager.profiles.isEmpty)
        XCTAssertNil(selection.currentProfile)
        XCTAssertEqual(selection.applyCount, 0)
        XCTAssertTrue(tabManager.stateStore.spaces.spaces.isEmpty)
        XCTAssertTrue(
            tabManager.stateStore.regularTabs
                .tabsBySpaceSnapshot()
                .isEmpty
        )
        XCTAssertEqual(
            structuralLookup.mutationRevision,
            revisionBefore
        )
    }
}

@MainActor
private final class ImportProfileSelectionOracle: SumiImportProfileSelection {
    private(set) var currentProfile: Profile?
    private(set) var applyCount = 0

    func applyImportProfileSelection(_ profile: Profile?) {
        currentProfile = profile
        applyCount += 1
    }
}
