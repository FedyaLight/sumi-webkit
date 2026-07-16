import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class TabProfileTransitionRuntimeLeaseTests: XCTestCase {
    func testDetachedRuntimeRejectsProfileExistenceAdmission() throws {
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )

        XCTAssertFalse(
            tabManager.profileAssignments.policy.profileExists(UUID())
        )
        XCTAssertNil(
            tabManager.profileAssignments.policy.placementProfileIDs().current
        )
        XCTAssertNil(
            tabManager.profileAssignments.policy.placementProfileIDs().default
        )
    }

    func testPlacementProfileIDsRejectRuntimeAttachmentReplacement() throws {
        let currentProfileID = UUID()
        let defaultProfileID = UUID()
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        let replacementCurrentProfileID = UUID()
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementCurrentProfileID },
            defaultProfileId: { UUID() }
        )
        var didReplaceAttachment = false
        let original = TestRuntimePorts.make(
            currentProfileId: {
                if didReplaceAttachment == false {
                    didReplaceAttachment = true
                    tabManager.runtimePortConnection.attach(replacement)
                }
                return currentProfileID
            },
            defaultProfileId: { defaultProfileID }
        )
        tabManager.runtimePortConnection.attach(original)

        let profileIDs = tabManager.profileAssignments.policy
            .placementProfileIDs()

        XCTAssertTrue(didReplaceAttachment)
        XCTAssertNil(profileIDs.current)
        XCTAssertNil(profileIDs.default)
        XCTAssertEqual(
            tabManager.runtimePortConnection.current?.currentProfileId,
            replacementCurrentProfileID
        )
    }

    func testDetachedSpaceTransitionDoesNotPinSourceProfile() throws {
        let sourceProfileID = UUID()
        let targetProfileID = UUID()
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        let source = tabManager.spaceServices.catalog.createSpace(
            name: "Source",
            profileId: sourceProfileID
        )
        let target = tabManager.spaceServices.catalog.createSpace(
            name: "Target",
            profileId: targetProfileID
        )
        let tab = Tab()
        tab.spaceId = source.id

        let preparation = tabManager.profileAssignments.tabs
            .prepareForSpaceTransition(
                tab: tab,
                targetSpaceID: target.id
            )

        XCTAssertNil(preparation)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testLateSettlementFromSupersededAttachmentReportsLeaseLossWithoutPublication()
        throws {
        let profile = Profile(name: "Target")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        let original = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: transition.makeLifecycle()
        )
        var replacementProfileQueries = 0
        let replacementCurrentProfileID = UUID()
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementCurrentProfileID },
            defaultProfileId: { profile.id },
            profile: { profileID in
                replacementProfileQueries += 1
                return profileID == profile.id ? profile : nil
            }
        )
        tabManager.runtimePortConnection.attach(original)
        let tab = Tab()
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.profileAssignments.tabs.start(
                desiredProfileID: profile.id,
                tab: tab,
                requiresStructuralPersistence: true,
                settlementObserver: { settlements.append($0) }
            ),
            .deferred
        )
        let publicationRevision = tabManager.structuralLookupCoordinator
            .mutationRevision
        let persistenceRevision = tabManager.structuralPersistence
            .schedulingRevision
        XCTAssertTrue(
            tab.profileAssignment.commit(
                try XCTUnwrap(transition.tabIntent)
            )
        )
        tabManager.runtimePortConnection.attach(replacement)

        try XCTUnwrap(transition.tabSettlement)(.committed)

        XCTAssertEqual(settlements, [.leaseLost])
        XCTAssertEqual(
            tabManager.structuralLookupCoordinator.mutationRevision,
            publicationRevision
        )
        XCTAssertEqual(
            tabManager.structuralPersistence.schedulingRevision,
            persistenceRevision
        )
        XCTAssertEqual(replacementProfileQueries, 0)
        XCTAssertEqual(
            tabManager.runtimePortConnection.current?.currentProfileId,
            replacementCurrentProfileID
        )
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testImmediateExecutionReportsLeaseLossWhenIntentObserverReattachesRuntime()
        throws {
        let profile = Profile(name: "Target")
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        let replacement = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil }
        )
        let original = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil }
        )
        tabManager.runtimePortConnection.attach(original)
        let tab = Tab()
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.profileAssignments.tabs.start(
                desiredProfileID: profile.id,
                tab: tab,
                requiresStructuralPersistence: true,
                capturingIntent: { _ in
                    tabManager.runtimePortConnection.attach(replacement)
                },
                settlementObserver: { settlements.append($0) }
            ),
            .failed
        )

        XCTAssertEqual(settlements, [.leaseLost])
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
        XCTAssertNil(tab.profileId)
    }

    func testDeferredExecutionRejectsSupersededAdmissionLeaseBeforeReplacementQuery()
        throws {
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let transition = DeferredSpaceProfileTransition()
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        let original = TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profileID in
                switch profileID {
                case sourceProfile.id: sourceProfile
                case targetProfile.id: targetProfile
                default: nil
                }
            },
            webViewLifecycle: transition.makeLifecycle()
        )
        var replacementProfileQueries = 0
        var replacementExecutions = 0
        let replacement = TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profileID in
                replacementProfileQueries += 1
                return profileID == targetProfile.id ? targetProfile : nil
            },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                executeProfileAssignment: { tab, _, intent in
                    replacementExecutions += 1
                    return tab.profileAssignment.commit(intent)
                        ? .committed
                        : .stale
                }
            )
        )
        tabManager.runtimePortConnection.attach(original)
        let tab = Tab()
        var intent: DeferredWebViewProfileAssignmentIntent?
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.profileAssignments.tabs.start(
                desiredProfileID: targetProfile.id,
                tab: tab,
                requiresStructuralPersistence: true,
                capturingIntent: { intent = $0 },
                settlementObserver: { settlements.append($0) }
            ),
            .deferred
        )
        tabManager.runtimePortConnection.attach(replacement)

        XCTAssertFalse(
            tabManager.profileAssignments.tabs.executeDeferred(
                tab: tab,
                intent: try XCTUnwrap(intent)
            )
        )
        XCTAssertEqual(replacementProfileQueries, 0)
        XCTAssertEqual(replacementExecutions, 0)
        XCTAssertEqual(settlements, [.leaseLost])
        XCTAssertNil(tab.profileId)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testProfileDeletionPlanningDoesNotRecaptureReplacementAttachment()
        async throws {
        let deletedProfile = Profile(name: "Deleted")
        let fallbackProfile = Profile(name: "Fallback")
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        var replacementProfileQueries = 0
        let replacement = TestRuntimePorts.make(
            currentProfileId: { fallbackProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profile: { profileID in
                replacementProfileQueries += 1
                return profileID == fallbackProfile.id
                    ? fallbackProfile
                    : nil
            }
        )
        var didReplaceAttachment = false
        let original = TestRuntimePorts.make(
            currentProfileId: { deletedProfile.id },
            defaultProfileId: { fallbackProfile.id },
            profileExists: { $0 == fallbackProfile.id },
            profile: { profileID in
                guard profileID == deletedProfile.id else { return nil }
                if didReplaceAttachment == false {
                    didReplaceAttachment = true
                    tabManager.runtimePortConnection.attach(replacement)
                }
                return deletedProfile
            }
        )
        tabManager.runtimePortConnection.attach(original)
        let contextlessTab = Tab()
        tabManager.transientTabRegistryOwner.registerAuxiliaryMiniWindowTab(
            contextlessTab
        )

        let outcome = await tabManager.profileAssignments.deletion.migrate(
            deletedProfileID: deletedProfile.id,
            fallbackProfileID: fallbackProfile.id
        )

        XCTAssertEqual(outcome, .rejected)
        XCTAssertTrue(didReplaceAttachment)
        XCTAssertEqual(replacementProfileQueries, 0)
        XCTAssertNil(contextlessTab.profileId)
        XCTAssertFalse(contextlessTab.profileAssignment.hasUnsettledAssignment)
    }

    func testStartRejectsProfileResolvedBySupersededRuntimeAttachment() throws {
        let profile = Profile(name: "Target")
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        var replacementExecutions = 0
        let replacementCurrentProfileID = UUID()
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementCurrentProfileID },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                executeProfileAssignment: { tab, _, intent in
                    replacementExecutions += 1
                    return tab.profileAssignment.commit(intent)
                        ? .committed
                        : .stale
                }
            )
        )
        var didReplaceAttachment = false
        let original = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { profileID in
                guard profileID == profile.id else { return nil }
                if didReplaceAttachment == false {
                    didReplaceAttachment = true
                    tabManager.runtimePortConnection.attach(replacement)
                }
                return profile
            }
        )
        tabManager.runtimePortConnection.attach(original)
        let tab = Tab()
        let sourceRevision = tab.profileAssignment.changeRevision

        let outcome = tabManager.profileAssignments.tabs.start(
            desiredProfileID: profile.id,
            tab: tab,
            requiresStructuralPersistence: true
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertTrue(didReplaceAttachment)
        XCTAssertEqual(replacementExecutions, 0)
        XCTAssertEqual(tab.profileAssignment.changeRevision, sourceRevision)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(
            tabManager.runtimePortConnection.current?.currentProfileId,
            replacementCurrentProfileID
        )
    }

    func testStartWithSupersededCallerLeaseRejectsBeforeRuntimeQuery() throws {
        let profile = Profile(name: "Target")
        let tabManager = try makeInMemoryTabManager(
            attachRuntimePorts: false
        )
        defer { tabManager.runtimePortConnection.detach() }
        var originalProfileQueries = 0
        let original = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { profileID in
                originalProfileQueries += 1
                return profileID == profile.id ? profile : nil
            }
        )
        var replacementProfileQueries = 0
        let replacementCurrentProfileID = UUID()
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementCurrentProfileID },
            defaultProfileId: { profile.id },
            profile: { profileID in
                replacementProfileQueries += 1
                return profileID == profile.id ? profile : nil
            }
        )
        tabManager.runtimePortConnection.attach(original)
        let staleLease = tabManager.runtimePortConnection.captureLease()
        tabManager.runtimePortConnection.attach(replacement)
        let tab = Tab()
        let sourceRevision = tab.profileAssignment.changeRevision

        let outcome = tabManager.profileAssignments.tabs.start(
            desiredProfileID: profile.id,
            tab: tab,
            requiresStructuralPersistence: true,
            using: staleLease
        )

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(originalProfileQueries, 0)
        XCTAssertEqual(replacementProfileQueries, 0)
        XCTAssertEqual(tab.profileAssignment.changeRevision, sourceRevision)
        XCTAssertEqual(
            tabManager.runtimePortConnection.current?.currentProfileId,
            replacementCurrentProfileID
        )
    }

    func testRetainedServiceDoesNotRetainTabManager() throws {
        var tabManager: TabManager? = try makeInMemoryTabManager()
        let retainedService = try XCTUnwrap(
            tabManager?.profileAssignments.tabs
        )
        weak let releasedManager = tabManager

        tabManager = nil

        withExtendedLifetime(retainedService) {
            XCTAssertNil(releasedManager)
        }
    }
}
