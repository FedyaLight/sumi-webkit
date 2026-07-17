import SumiDomain
import SumiWebRuntime
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionFinalizationTests: XCTestCase {
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
            in: tabManager.modelContext
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
                    .map {
                        .shortcutPin(
                            $0.id,
                            returnPlacement: .essential(
                                profileId: deletedProfile.id,
                                index: $0.index
                            )
                        )
                    },
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
        XCTAssertTrue(migratedGroup.members.allSatisfy {
            guard case .essential(let profileID, _) = $0.returnPlacement else {
                return false
            }
            return profileID == fallbackProfile.id
        })
        XCTAssertFalse(
            tabManager.profileDeletion.containsReference(
                to: deletedProfile.id
            )
        )
        XCTAssertTrue(
            try fixture.admission.cancel(token)
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
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
        try persistProfiles(
            [deletedProfile, fallbackProfile],
            in: tabManager.modelContext
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
                members: pins.map {
                    .shortcutPin(
                        $0.id,
                        returnPlacement: .essential(
                            profileId: deletedProfile.id,
                            index: $0.index
                        )
                    )
                },
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
        XCTAssertTrue(
            try fixture.admission.cancel(token)
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

    func testFinalizationRejectsRuntimeReplacementWithoutMutatingReferences()
        async throws {
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
        let deletedSpace = try makeSpace(
            in: tabManager,
            name: "Deleted",
            profileId: deletedProfile.id
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: deletedProfile.id,
            index: 0,
            launchURL: URL(string: "https://deleted.example")!,
            title: "Deleted"
        )
        tabManager.structuralCollectionMutationOwner.setPinnedTabs(
            [pin],
            for: deletedProfile.id
        )
        let migration = Task { @MainActor in
            await tabManager.profileDeletion.migrate(
                deletedProfileID: deletedProfile.id,
                fallbackProfileID: fallbackProfile.id
            )
        }
        await Task.yield()

        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertEqual(try XCTUnwrap(transition.sealModel)(), .sealed)
        try XCTUnwrap(transition.publishCommit)()
        XCTAssertEqual(deletedSpace.profileId, fallbackProfile.id)

        let replacement = TestRuntimePorts.make(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
        tabManager.runtimePortConnection.attach(replacement)
        defer { tabManager.runtimePortConnection.detach() }
        try XCTUnwrap(transition.settlement)(.committed)

        let outcome = await migration.value
        XCTAssertEqual(outcome, .rejected)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pinnedByProfileSnapshot()[deletedProfile.id],
            [pin]
        )
    }

    func testMigrationRejectsReferenceCreatedWhileSettlementIsDeferred()
        async throws {
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
        let originalSpace = try makeSpace(
            in: tabManager,
            name: "Original",
            profileId: deletedProfile.id
        )
        let migration = Task { @MainActor in
            await tabManager.profileDeletion.migrate(
                deletedProfileID: deletedProfile.id,
                fallbackProfileID: fallbackProfile.id
            )
        }
        await Task.yield()

        let lateSpace = try makeSpace(
            in: tabManager,
            name: "Late",
            profileId: deletedProfile.id
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertEqual(try XCTUnwrap(transition.sealModel)(), .sealed)
        try XCTUnwrap(transition.publishCommit)()
        try XCTUnwrap(transition.settlement)(.committed)

        let outcome = await migration.value
        XCTAssertEqual(outcome, .rejected)
        XCTAssertEqual(originalSpace.profileId, fallbackProfile.id)
        XCTAssertEqual(lateSpace.profileId, deletedProfile.id)
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
        let container = try makeInMemoryStartupModelContainer()
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: container
            )
        )
        browser.runtimePortConnection.attach(
            TestRuntimePorts.make(
                currentProfileId: currentProfileId,
                defaultProfileId: defaultProfileId,
                profileExists: profileExists,
                profile: profile,
                webViewLifecycle: webViewLifecycle
                    ?? TestRuntimePorts.webViewLifecycle(
                        retirement: .rejecting
                    )
            )
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
        in context: ModelContext
    ) throws {
        for (index, profile) in profiles.enumerated() {
            context.insert(
                ProfileEntity(
                    id: profile.id,
                    name: profile.name,
                    icon: profile.icon,
                    index: index
                )
            )
        }
        try context.save()
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
