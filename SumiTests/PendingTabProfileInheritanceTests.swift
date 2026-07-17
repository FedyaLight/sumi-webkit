import Combine
import Foundation
@testable import Sumi
import XCTest

@MainActor
final class PendingTabProfileInheritanceTests: XCTestCase {
    func testRejectedFollowerOverrideAfterSpaceCommitReturnsToInheritance() async throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let rejectedProfile = Profile(name: "Rejected")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                rejectedProfile.id: rejectedProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let structuralEvents = ProfileStructuralEventRecorder(
            tabManager: tabManager
        )

        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://rejected-follower.example",
            in: space,
            activate: false
        )
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: rejectedProfile.id
            )
        )

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)
        await Task.yield()
        tabManager.structuralPersistence.cancelPendingPersistence()
        tabManager.structuralPersistence.resetDirtySet()
        structuralEvents.reset()

        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(follower.profileAssignment.hasUnsettledAssignment)

        try XCTUnwrap(transition.tabSettlement)(.rejected(.failed))
        await Task.yield()

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(structuralEvents.count, 1)
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.dirtyTabIds
                .contains(follower.id)
        )
        XCTAssertNotNil(
            tabManager.structuralPersistence.scheduledPersistTask
        )
    }

    func testCancelledFollowerOverrideAfterSpaceCommitReturnsToInheritance() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let cancelledProfile = Profile(name: "Cancelled")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                cancelledProfile.id: cancelledProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://cancelled-follower.example",
            in: space,
            activate: false
        )
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: cancelledProfile.id
            )
        )
        let tabIntent = try XCTUnwrap(transition.tabIntent)

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        tabManager.tabProfileTransitions.cancelPendingDeletionIntent(
            tab: follower,
            intent: tabIntent
        )

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
    }

    func testAssigningInheritedProfileCancelsFollowerOverrideAfterSpaceCommit() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let overriddenProfile = Profile(name: "Overridden")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                overriddenProfile.id: overriddenProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://cancelled-by-assignment.example",
            in: space,
            activate: false
        )
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: overriddenProfile.id
            )
        )

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: pendingProfile.id
            )
        )

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
    }

    func testLateRejectedFollowerIntentCannotInvalidateNewOverride() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let firstOverride = Profile(name: "First Override")
        let secondOverride = Profile(name: "Second Override")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                firstOverride.id: firstOverride,
                secondOverride.id: secondOverride,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://late-settlement.example",
            in: space,
            activate: false
        )
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: firstOverride.id
            )
        )
        let firstIntent = try XCTUnwrap(transition.tabIntent)
        let firstSettlement = try XCTUnwrap(transition.tabSettlement)

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        follower.profileAssignment.abort(firstIntent)
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: secondOverride.id
            )
        )
        let secondIntent = try XCTUnwrap(transition.tabIntent)
        let secondSettlement = try XCTUnwrap(transition.tabSettlement)

        firstSettlement(.rejected(.stale))

        XCTAssertEqual(follower.profileId, pendingProfile.id)
        XCTAssertTrue(follower.profileAssignment.isCurrent(secondIntent))

        secondSettlement(.rejected(.failed))

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
    }

    func testRolledBackFollowerOverrideAfterSpaceCommitReturnsToInheritance() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let rolledBackProfile = Profile(name: "Rolled Back")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                rolledBackProfile.id: rolledBackProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let space = Space(name: "Profiled", profileId: existingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])

        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: space.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://rolled-back-follower.example",
            in: space,
            activate: false
        )
        XCTAssertTrue(
            tabManager.tabProfileTransitions.assign(
                follower,
                toProfile: rolledBackProfile.id
            )
        )
        let tabIntent = try XCTUnwrap(transition.tabIntent)

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)
        XCTAssertTrue(follower.profileAssignment.stage(tabIntent))
        XCTAssertEqual(follower.profileId, rolledBackProfile.id)
        XCTAssertTrue(follower.profileAssignment.rollback(tabIntent))
        XCTAssertEqual(follower.profileId, pendingProfile.id)

        try XCTUnwrap(transition.tabSettlement)(
            .rolledBack(.abort(.explicit))
        )

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(space.profileId, pendingProfile.id)
        XCTAssertFalse(follower.profileAssignment.hasUnsettledAssignment)
    }

    func testPendingProfileInheritanceDoesNotRetainFollower() {
        let inheritance = PendingTabProfileInheritance()
        let spaceID = UUID()
        weak var releasedTab: Tab?
        var tab: Tab? = Tab(
            url: URL(fileURLWithPath: "/"),
            spaceId: spaceID,
            loadsCachedFaviconOnInit: false
        )
        releasedTab = tab
        if let tab {
            inheritance.record(
                tab: tab,
                spaceID: spaceID,
                spaceRevision: 1,
                inheritedProfileID: UUID()
            )
        }

        tab = nil

        XCTAssertNil(releasedTab)
    }

    func testRolledBackPlacementKeepsCreationFollowerProvenance() throws {
        let existingProfile = Profile(name: "Existing")
        let pendingProfile = Profile(name: "Pending")
        let pinnedSourceProfile = Profile(name: "Pinned source")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeDeferredTabManager(
            profiles: [
                existingProfile.id: existingProfile,
                pendingProfile.id: pendingProfile,
                pinnedSourceProfile.id: pinnedSourceProfile,
            ],
            currentProfileID: { pendingProfile.id },
            transition: transition
        )
        let source = Space(name: "Source", profileId: existingProfile.id)
        let target = Space(name: "Target", profileId: pendingProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([source, target])
        XCTAssertEqual(
            tabManager.spaceProfileTransitions.start(
                spaceID: source.id,
                profileID: pendingProfile.id
            ),
            .deferred
        )
        let follower = tabManager.regularTabLifecycleOwner.createNewTab(
            in: source,
            activate: false
        )
        let preparation = TabSpaceProfileTransitionPreparation(
            tabID: follower.id,
            sourceSpaceID: source.id,
            targetSpaceID: target.id,
            sourceProfileID: pendingProfile.id,
            sourceAssignmentRevision:
                follower.profileAssignment.changeRevision,
            pinnedProfileID: pinnedSourceProfile.id
        )

        XCTAssertTrue(
            tabManager.tabProfileTransitions.stageSpaceTransition(
                preparation,
                for: follower
            )
        )
        follower.spaceId = target.id
        follower.spaceId = source.id
        XCTAssertTrue(
            tabManager.tabProfileTransitions.rollbackStagedSpaceTransition(
                preparation,
                for: follower
            )
        )
        XCTAssertEqual(follower.profileId, pendingProfile.id)

        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.finishModel)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertNil(follower.profileId)
        XCTAssertEqual(source.profileId, pendingProfile.id)
    }

    private func makeDeferredTabManager(
        profiles: [UUID: Profile],
        currentProfileID: @escaping @MainActor () -> UUID?,
        transition: DeferredSpaceProfileTransition
    ) throws -> BrowserManager {
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(
            TestRuntimePorts.make(
                currentProfileId: currentProfileID,
                defaultProfileId: currentProfileID,
                profile: { profiles[$0] },
                webViewLifecycle: transition.makeLifecycle()
            )
        )
        return tabManager
    }
}

@MainActor
private final class ProfileStructuralEventRecorder {
    private var cancellable: AnyCancellable?
    private(set) var count = 0

    init(tabManager: BrowserManager) {
        cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { [weak self] _ in
                self?.count += 1
            }
    }

    func reset() {
        count = 0
    }
}
