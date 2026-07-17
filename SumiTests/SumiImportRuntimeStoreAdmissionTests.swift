import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiImportRuntimeStoreAdmissionTests: XCTestCase {
    func testProfileSnapshotReplacementCannotBypassDurableRetirement() throws {
        let container = try makeInMemoryStartupModelContainer()
        let profileManager = ProfileManager(context: container.mainContext)
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
        let entities = try container.mainContext.fetch(
            FetchDescriptor<ProfileEntity>()
        )
        XCTAssertEqual(entities.map(\.id), [original.id])
    }

    func testUnavailableAdmissionRejectsImportBeforeAnyRuntimeMutation() async throws {
        let container = try makeInMemoryStartupModelContainer()
        let admission = ProfileReferenceAdmissionLedger.failClosed()
        let profileManager = ProfileManager(
            context: container.mainContext,
            profileReferenceAdmission: admission
        )
        let tabManager = TabManager(
            context: container.mainContext,
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
