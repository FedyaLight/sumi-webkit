import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionFinalizationTests: XCTestCase {
    func testMigrationCreatesFallbackSpaceBeforeRemovingLastOwnedSpace()
        async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Default")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        let browser = fixture.browser
        try persistProfiles(
            [deletedProfile, fallbackProfile],
            in: browser.database
        )
        let deletedSpace = try makeSpace(
            in: browser,
            name: "Deleted",
            profileId: deletedProfile.id
        )
        let token = try fixture.admission.reserve(
            profile: deletedProfile,
            fallbackID: fallbackProfile.id
        )
        XCTAssertTrue(try fixture.admission.beginReferenceMigration(token))
        XCTAssertTrue(
            browser.profileDeletion.ensureFallbackSpace(
                for: fallbackProfile.id
            )
        )

        let outcome = await browser.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertNil(browser.spaceStateOwner.space(with: deletedSpace.id))
        let fallbackSpaces = browser.spaceStateOwner.spaces.filter {
            $0.profileId == fallbackProfile.id
        }
        XCTAssertEqual(fallbackSpaces.count, 1)
        XCTAssertEqual(fallbackSpaces.first?.name, "Space")
        XCTAssertEqual(
            fallbackSpaces.first?.workspaceTheme.gradientTheme.colors
                .first?.hex,
            "#F4EFDF"
        )
    }

    func testMigrationDeletesSpacesOwnedByRetiringProfile() async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        var unloadedTabIDs: [UUID] = []
        let transition = DeferredSpaceProfileTransition(
            unloadTab: { unloadedTabIDs.append($0.id) }
        )
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let browser = fixture.browser
        let deletedSpace = try makeSpace(
            in: browser,
            name: "Deleted",
            profileId: deletedProfile.id
        )
        let fallbackSpace = try makeSpace(
            in: browser,
            name: "Fallback",
            profileId: fallbackProfile.id
        )
        let deletedTab = browser.regularTabLifecycleOwner.createNewTab(
            in: deletedSpace,
            activate: false
        )
        deletedTab.profileId = deletedProfile.id

        let outcome = await browser.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertNil(browser.spaceStateOwner.space(with: deletedSpace.id))
        XCTAssertIdentical(
            browser.spaceStateOwner.space(with: fallbackSpace.id),
            fallbackSpace
        )
        XCTAssertNil(browser.tabCollectionMembershipOwner.tab(for: deletedTab.id))
        XCTAssertNil(transition.tabIntent)
        XCTAssertEqual(unloadedTabIDs, [deletedTab.id])
        XCTAssertTrue(
            browser.structuralPersistence.dirtySet.deletedSpaceIds
                .contains(deletedSpace.id)
        )
    }

    func testMigrationWaitsForLiveProfileRuntimeReplacement() async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let browser = fixture.browser
        let liveTab = Tab()
        liveTab.profileId = deletedProfile.id
        browser.tabStateStore.transientTabs
            .registerAuxiliaryMiniWindowTab(liveTab)
        var completedOutcome: ProfileDeletionMigrationOutcome?

        let migration = Task { @MainActor in
            let outcome = await browser.profileDeletion.migrate(
                deletedProfileID: deletedProfile.id,
                fallbackProfileID: fallbackProfile.id
            )
            completedOutcome = outcome
            return outcome
        }
        for _ in 0..<20 where transition.tabIntent == nil {
            await Task.yield()
        }

        XCTAssertNil(completedOutcome)
        let intent = try XCTUnwrap(transition.tabIntent)
        XCTAssertTrue(liveTab.profileAssignment.stage(intent))
        XCTAssertTrue(liveTab.profileAssignment.finish(intent))
        transition.tabSettlement?(.committed)

        let outcome = await migration.value
        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(liveTab.profileId, fallbackProfile.id)
        XCTAssertFalse(
            browser.profileDeletion.containsReference(to: deletedProfile.id)
        )
    }

    func testFinalizationMigratesPendingAndLiveSplitReferencesUnderRetirementLease()
        async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        let tabManager = fixture.browser
        try persistProfiles(
            [deletedProfile, fallbackProfile],
            in: tabManager.database
        )

        let deletedPin = makeEssentialPin(
            profileID: deletedProfile.id,
            title: "Deleted"
        )
        let firstFallbackPin = makeEssentialPin(
            profileID: fallbackProfile.id,
            title: "First fallback"
        )
        let secondFallbackPin = makeEssentialPin(
            profileID: fallbackProfile.id,
            title: "Second fallback"
        )
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfile.id,
            executionProfileId: deletedProfile.id,
            index: 0,
            launchURL: URL(string: "https://pending.example")!,
            title: "Pending"
        )
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [
                deletedProfile.id: [deletedPin],
                fallbackProfile.id: [firstFallbackPin, secondFallbackPin],
            ],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin]
        )

        let group = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: [deletedPin, firstFallbackPin, secondFallbackPin]
                    .map { .shortcutPin($0.id) },
                layoutKind: .grid,
                container: .shortcutSidebar(
                    spaceId: UUID(),
                    profileId: deletedProfile.id,
                    folderId: nil,
                    index: 0
                )
            )
        )
        XCTAssertTrue(tabManager.splitGroupMutations.insert(group))
        let fixturePersisted = await tabManager.structuralPersistence
            .persistFullReconcileAwaitingResult(
                reason: "profile retirement fixture"
            )
        XCTAssertTrue(
            fixturePersisted
        )
        let token = try fixture.admission.reserve(
            profile: deletedProfile,
            fallbackID: fallbackProfile.id
        )
        XCTAssertTrue(
            try fixture.admission
                .beginReferenceMigration(token)
        )

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .committed)
        let migrationPersisted = await tabManager.structuralPersistence
            .persistPendingStructuralChangesAwaitingResult()
        XCTAssertTrue(migrationPersisted)
        let persistedTabs = try tabManager.database.read {
            try $0.workspace.tabs()
        }
        XCTAssertFalse(persistedTabs.contains {
            $0.profileID == deletedProfile.id
                || $0.executionProfileID == deletedProfile.id
        })
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertNil(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[deletedProfile.id]
        )
        let fallbackPins = tabManager.shortcutPinCollectionStateOwner
            .essentialPins(for: fallbackProfile.id)
        XCTAssertEqual(
            fallbackPins.map(\.id),
            [firstFallbackPin.id, secondFallbackPin.id, pendingPin.id]
        )
        XCTAssertTrue(fallbackPins.allSatisfy {
            $0.profileId == fallbackProfile.id
                && $0.executionProfileId != deletedProfile.id
        })
        let migratedGroup = try XCTUnwrap(tabManager.splitGroupStore.groups.first)
        XCTAssertEqual(
            migratedGroup.memberIDs,
            [
                .shortcutPin(firstFallbackPin.id),
                .shortcutPin(secondFallbackPin.id),
            ]
        )
        guard case .shortcutSidebar(_, let ownerProfileID, _, _)
                = migratedGroup.container else {
            return XCTFail("The live shortcut container must remain typed")
        }
        XCTAssertEqual(ownerProfileID, fallbackProfile.id)
        XCTAssertFalse(
            tabManager.profileDeletion.containsReference(
                to: deletedProfile.id
            )
        )
    }

    func testFinalizationRejectsReentrantOldProfileSplitPublication()
        async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        let tabManager = fixture.browser
        let retiringSpace = try makeSpace(
            in: tabManager,
            name: "Retiring",
            profileId: deletedProfile.id
        )
        try persistProfiles(
            [deletedProfile, fallbackProfile],
            in: tabManager.database
        )
        let pins = [
            makeEssentialPin(
                profileID: fallbackProfile.id,
                title: "First"
            ),
            makeEssentialPin(
                profileID: fallbackProfile.id,
                title: "Second"
            ),
        ]
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile(
            [fallbackProfile.id: pins]
        )
        let staleGroup = try XCTUnwrap(
            SumiDomain.SplitGroup.make(
                members: pins.map { .shortcutPin($0.id) },
                layoutKind: .horizontal,
                container: .shortcutSidebar(
                    spaceId: UUID(),
                    profileId: deletedProfile.id,
                    folderId: nil,
                    index: 0
                )
            )
        )
        XCTAssertTrue(tabManager.splitGroupMutations.insert(staleGroup))
        let token = try fixture.admission.reserve(
            profile: deletedProfile,
            fallbackID: fallbackProfile.id
        )
        XCTAssertTrue(
            try fixture.admission
                .beginReferenceMigration(token)
        )
        var didPublishReentrantReference = false
        let observation = tabManager.objectWillChange.sink {
            guard didPublishReentrantReference == false,
                  let migrated = tabManager.splitGroupStore.groups.first,
                  let reentrant = migrated.changingContainer(
                      to: staleGroup.container
                  ) else { return }
            didPublishReentrantReference = tabManager.splitGroupMutations
                .replace(migrated, with: reentrant)
        }

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .rejected)
        XCTAssertTrue(didPublishReentrantReference)
        XCTAssertTrue(
            tabManager.profileDeletion.containsReference(
                to: deletedProfile.id
            )
        )
        XCTAssertIdentical(
            tabManager.spaceStateOwner.space(with: retiringSpace.id),
            retiringSpace
        )
        withExtendedLifetime(observation) {}
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testShortcutReferenceChangesPublishAsOneTerminalSnapshot()
        async throws {
        let deletedProfileID = UUID()
        let fallbackProfileID = UUID()
        let ownerProfileID = UUID()
        let spaceID = UUID()
        let profiles = [
            deletedProfileID: Profile(
                id: deletedProfileID,
                name: "Deleted"
            ),
            fallbackProfileID: Profile(
                id: fallbackProfileID,
                name: "Fallback"
            ),
            ownerProfileID: Profile(
                id: ownerProfileID,
                name: "Owner"
            ),
        ]
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfileID },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        let tabManager = fixture.browser
        let deletedPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfileID,
            index: 0,
            launchURL: URL(string: "https://deleted.example")!,
            title: "Deleted"
        )
        let profileReference = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: ownerProfileID,
            executionProfileId: deletedProfileID,
            index: 0,
            launchURL: URL(string: "https://profile-reference.example")!,
            title: "Profile reference"
        )
        let spaceReference = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: deletedProfileID,
            spaceId: spaceID,
            index: 0,
            launchURL: URL(string: "https://space-reference.example")!,
            title: "Space reference"
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [deletedPin],
            for: deletedProfileID
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [profileReference],
            for: ownerProfileID
        )
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [spaceReference],
            for: spaceID
        )
        var observedTerminalStates: [Bool] = []
        let observation = tabManager.objectWillChange.sink {
            observedTerminalStates.append(
                tabManager.shortcutPinCollectionStateOwner
                    .pinnedByProfileSnapshot()[deletedProfileID] == nil
                    && tabManager.shortcutPinCollectionStateOwner
                        .pinnedByProfileSnapshot()[ownerProfileID]?
                        .first?.executionProfileId == nil
                    && tabManager.shortcutPinCollectionStateOwner
                        .spacePinnedShortcutsSnapshot()[spaceID]?
                        .first?.executionProfileId == nil
            )
        }

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfileID,
            fallbackProfileID: fallbackProfileID
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(observedTerminalStates, [true])
        withExtendedLifetime(observation) {}
    }

    func testFinalizationRejectsShortcutReferenceCreatedDuringPublication()
        async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        let tabManager = fixture.browser
        let original = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfile.id,
            index: 0,
            launchURL: URL(string: "https://original.example")!,
            title: "Original"
        )
        let reentrant = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfile.id,
            index: 0,
            launchURL: URL(string: "https://reentrant.example")!,
            title: "Reentrant"
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [original],
            for: deletedProfile.id
        )
        var didReenter = false
        let observation = tabManager.objectWillChange.sink {
            guard didReenter == false else { return }
            didReenter = true
            tabManager.structuralCollectionMutationOwner.setPinnedTabs(
                [reentrant],
                for: deletedProfile.id
            )
        }

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .rejected)
        XCTAssertTrue(didReenter)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[deletedProfile.id],
            [reentrant]
        )
        withExtendedLifetime(observation) {}
    }

    func testMigrationRejectsTransitionsIntoDeletedProfile() async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let profiles = [
            deletedProfile.id: deletedProfile,
            fallbackProfile.id: fallbackProfile,
        ]
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeProfileDeletionFixture(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let tabManager = fixture.browser
        let tab = Tab()
        tabManager.tabStateStore.transientTabs.registerAuxiliaryMiniWindowTab(tab)
        var tabIntent: DeferredWebViewProfileAssignmentIntent?
        XCTAssertEqual(
            tabManager.tabProfileTransitions.start(
                desiredProfileID: deletedProfile.id,
                tab: tab,
                requiresStructuralPersistence: false,
                capturingIntent: { tabIntent = $0 }
            ),
            .deferred
        )
        let space = try makeSpace(
            in: tabManager,
            name: "Fallback",
            profileId: fallbackProfile.id
        )
        var spaceIntent: DeferredWebViewSpaceProfileAssignmentIntent?
        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: deletedProfile.id,
                capturingIntent: { spaceIntent = $0 }
            ),
            .deferred
        )

        let outcome = await tabManager.profileDeletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .rejected)
        tabManager.tabProfileTransitions.cancelPendingDeletionIntent(
            tab: tab,
            intent: try XCTUnwrap(tabIntent)
        )
        tabManager.spaceProfileTransitions.lifecycle.cancelPending(
            try XCTUnwrap(spaceIntent)
        )
    }

    private func makeProfileDeletionFixture(
        currentProfileId: @escaping () -> UUID?,
        defaultProfileId: @escaping () -> UUID? = { nil },
        profileExists: @escaping (UUID) -> Bool,
        profile: @escaping (UUID) -> Profile?,
        webViewLifecycle: TabManagerWebViewLifecycleService? = nil
    ) throws -> ProfileDeletionFixture {
        let container = try makeInMemoryStartupDatabase()
        let runtime = TestRuntimePorts.make(
            currentProfileId: currentProfileId,
            defaultProfileId: defaultProfileId,
            profileExists: profileExists,
            profile: profile,
            webViewLifecycle: webViewLifecycle
                ?? TestRuntimePorts.webViewLifecycle(
                    retirement: .rejecting
                )
        )
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            runtimePorts: runtime
        )
        return ProfileDeletionFixture(
            browser: browser,
            admission: browser.profileReferenceAdmission
        )
    }

    private func makeSpace(
        in browser: BrowserManager,
        name: String,
        profileId: UUID
    ) throws -> Space {
        try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: profileId
            )
        )
    }

    private func persistProfiles(
        _ profiles: [Profile],
        in database: SumiDatabase
    ) throws {
        try database.transaction {
            for (index, profile) in profiles.enumerated() {
                try $0.profiles.save(
                    ProfileRecord(
                    id: profile.id,
                    name: profile.name,
                    index: index
                    )
                )
            }
        }
    }

    private func makeEssentialPin(
        profileID: UUID,
        title: String
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: title
        )
    }
}

@MainActor
private struct ProfileDeletionFixture {
    let browser: BrowserManager
    let admission: ProfileReferenceAdmissionLedger
}
