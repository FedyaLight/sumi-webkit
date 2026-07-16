import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionFinalizationTests: XCTestCase {
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
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { fallbackProfileID },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
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

        let outcome = await tabManager.profileAssignments.deletion.migrate(
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
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let deletedSpace = tabManager.spaceServices.catalog.createSpace(
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
            await tabManager.profileAssignments.deletion.migrate(
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
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let originalSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Original",
            profileId: deletedProfile.id
        )
        let migration = Task { @MainActor in
            await tabManager.profileAssignments.deletion.migrate(
                deletedProfileID: deletedProfile.id,
                fallbackProfileID: fallbackProfile.id
            )
        }
        await Task.yield()

        let lateSpace = tabManager.spaceServices.catalog.createSpace(
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
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] }
        )
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

        let outcome = await tabManager.profileAssignments.deletion.migrate(
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
        let tabManager = try makeInMemoryTabManager(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { profiles[$0] != nil },
            profile: { profiles[$0] },
            webViewLifecycle: transition.makeLifecycle()
        )
        let tab = Tab()
        tabManager.transientTabRegistryOwner.registerAuxiliaryMiniWindowTab(tab)
        var tabIntent: DeferredWebViewProfileAssignmentIntent?
        XCTAssertEqual(
            tabManager.profileAssignments.tabs.start(
                desiredProfileID: deletedProfile.id,
                tab: tab,
                requiresStructuralPersistence: false,
                capturingIntent: { tabIntent = $0 }
            ),
            .deferred
        )
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Fallback",
            profileId: fallbackProfile.id
        )
        var spaceIntent: DeferredWebViewSpaceProfileAssignmentIntent?
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: space.id,
                profileID: deletedProfile.id,
                capturingIntent: { spaceIntent = $0 }
            ),
            .deferred
        )

        let outcome = await tabManager.profileAssignments.deletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .rejected)
        tabManager.profileAssignments.tabs.cancelPendingDeletionIntent(
            tab: tab,
            intent: try XCTUnwrap(tabIntent)
        )
        tabManager.profileAssignments.spaceLifecycle.cancelPending(
            try XCTUnwrap(spaceIntent)
        )
    }
}
