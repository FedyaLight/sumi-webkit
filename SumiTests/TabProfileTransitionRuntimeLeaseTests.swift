import Combine
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class TabProfileTransitionRuntimeLeaseTests: XCTestCase {
    func testDetachedRuntimeRejectsProfileExistenceAdmission() throws {
        let tabManager = BrowserManager()
        tabManager.tabRuntimeLifecycle.shutdown()
        let policy = ProfileAssignmentPolicy(
            runtimeConnection: tabManager.runtimePortConnection,
            spaces: tabManager.spaceStateOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            transientTabs: tabManager.tabStateStore.transientTabs
        )

        XCTAssertFalse(
            policy.profileExists(UUID())
        )
        XCTAssertNil(
            policy.placementProfileIDs().current
        )
        XCTAssertNil(
            policy.placementProfileIDs().default
        )
    }

    func testPlacementProfileIDsRejectRuntimeAttachmentReplacement() throws {
        let currentProfileID = UUID()
        let defaultProfileID = UUID()
        var replaceAttachment: (() -> Void)?
        let replacementCurrentProfileID = UUID()
        let replacement = TestRuntimePorts.make(
            currentProfileId: { replacementCurrentProfileID },
            defaultProfileId: { UUID() }
        )
        var didReplaceAttachment = false
        let original = TestRuntimePorts.make(
            currentProfileId: {
                if didReplaceAttachment == false,
                   let replaceAttachment {
                    didReplaceAttachment = true
                    replaceAttachment()
                }
                return currentProfileID
            },
            defaultProfileId: { defaultProfileID }
        )
        let tabManager = BrowserManager(runtimePorts: original)
        replaceAttachment = {
            tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(
                replacement
            )
        }
        defer { tabManager.tabRuntimeLifecycle.shutdown() }

        let policy = ProfileAssignmentPolicy(
            runtimeConnection: tabManager.runtimePortConnection,
            spaces: tabManager.spaceStateOwner,
            membership: tabManager.tabCollectionMembershipOwner,
            transientTabs: tabManager.tabStateStore.transientTabs
        )
        let profileIDs = policy.placementProfileIDs()

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
        let tabManager = BrowserManager()
        tabManager.tabRuntimeLifecycle.shutdown()
        let source = Space(
            name: "Source",
            profileId: sourceProfileID
        )
        let target = Space(
            name: "Target",
            profileId: targetProfileID
        )
        tabManager.spaceStateOwner.replaceSpaces([source, target])
        let tab = Tab()
        tab.spaceId = source.id

        let preparation = tabManager.tabProfileTransitions
            .prepareForSpaceTransition(
                tab: tab,
                targetSpaceID: target.id
            )

        XCTAssertEqual(preparation, .rejected)
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testPreparedRegularPlacementRollsBackStagedProfileTransition()
        throws {
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profiles[$0] }
        ))
        let source = Space(
            name: "Source",
            profileId: sourceProfile.id
        )
        let target = Space(
            name: "Target",
            profileId: targetProfile.id
        )
        tabManager.spaceStateOwner.replaceSpaces([source, target])
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: source,
            activate: false
        )

        let placement = try XCTUnwrap(
            tabManager.regularTabCollectionOwner.preparePlacement(
                tab,
                in: target.id,
                at: 0
            )
        )

        XCTAssertNil(tab.profileId)
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertNotNil(tabManager.regularTabCollectionOwner.remove(
            tab.id,
            from: source.id,
            currentSpaceId: source.id
        ))
        XCTAssertTrue(placement.stage())
        XCTAssertEqual(tab.profileId, sourceProfile.id)
        XCTAssertEqual(tab.spaceId, target.id)
        XCTAssertTrue(placement.rollback())
        XCTAssertNil(tab.profileId)
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertTrue(
            tabManager.regularTabCollectionOwner.tabs(in: target).isEmpty
        )
    }

    func testRegularPlacementRestoresSourceWhenTargetSnapshotChanges()
        throws {
        let profile = Profile(name: "Profile")
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil }
        ))
        let source = Space(
            name: "Source",
            profileId: profile.id
        )
        let target = Space(
            name: "Target",
            profileId: profile.id
        )
        tabManager.spaceStateOwner.replaceSpaces([source, target])
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            in: source,
            activate: false
        )
        let intruder = tabManager.tabFactory.makeTab(
            spaceId: target.id,
            loadsCachedFaviconOnInit: false
        )

        let placed = tabManager.regularTabCollectionOwner.place(
            tab,
            in: target.id,
            at: 0,
            removingFromSource: {
                guard tabManager.regularTabCollectionOwner.remove(
                    tab.id,
                    from: source.id,
                    currentSpaceId: source.id
                ) != nil else { return false }
                tabManager.structuralCollectionMutationOwner.setTabs(
                    [intruder],
                    for: target.id
                )
                return true
            }
        )

        XCTAssertFalse(placed)
        XCTAssertEqual(
            tabManager.regularTabCollectionOwner.tabs(in: source).map(\.id),
            [tab.id]
        )
        XCTAssertTrue(
            tabManager.regularTabCollectionOwner.tabs(in: target).isEmpty
        )
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertNil(tab.profileId)
    }

    func testLateSettlementFromSupersededAttachmentReportsLeaseLossWithoutPublication()
        throws {
        let profile = Profile(name: "Target")
        let transition = DeferredSpaceProfileTransition()
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
        let tabManager = BrowserManager(runtimePorts: original)
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let tab = Tab()
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.tabProfileTransitions.start(
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
        tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(replacement)

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
        let tabManager = BrowserManager(runtimePorts: original)
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let tab = Tab()
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.tabProfileTransitions.start(
                desiredProfileID: profile.id,
                tab: tab,
                requiresStructuralPersistence: true,
                capturingIntent: { _ in
                    tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(replacement)
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
        let tabManager = BrowserManager(runtimePorts: original)
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let tab = Tab()
        var intent: DeferredWebViewProfileAssignmentIntent?
        var settlements: [ProfileTransitionSettlement] = []

        XCTAssertEqual(
            tabManager.tabProfileTransitions.start(
                desiredProfileID: targetProfile.id,
                tab: tab,
                requiresStructuralPersistence: true,
                capturingIntent: { intent = $0 },
                settlementObserver: { settlements.append($0) }
            ),
            .deferred
        )
        tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(replacement)

        XCTAssertFalse(
            tabManager.tabProfileTransitions.executeDeferred(
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
        var replaceAttachment: (() -> Void)?
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
                if didReplaceAttachment == false,
                   let replaceAttachment {
                    didReplaceAttachment = true
                    replaceAttachment()
                }
                return deletedProfile
            }
        )
        let tabManager = BrowserManager(runtimePorts: original)
        replaceAttachment = {
            tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(
                replacement
            )
        }
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let contextlessTab = Tab()
        tabManager.tabCollectionMembershipOwner.attach(contextlessTab)
        tabManager.tabCollectionMembershipOwner
            .registerAuxiliaryMiniWindowTab(contextlessTab)

        let outcome = await tabManager.profileDeletion.migrate(
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
        var replaceAttachment: (() -> Void)?
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
                if didReplaceAttachment == false,
                   let replaceAttachment {
                    didReplaceAttachment = true
                    replaceAttachment()
                }
                return profile
            }
        )
        let tabManager = BrowserManager(runtimePorts: original)
        replaceAttachment = {
            tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(
                replacement
            )
        }
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let tab = Tab()
        let sourceRevision = tab.profileAssignment.changeRevision

        let outcome = tabManager.tabProfileTransitions.start(
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
        let tabManager = BrowserManager(runtimePorts: original)
        defer { tabManager.tabRuntimeLifecycle.shutdown() }
        let staleLease = tabManager.runtimePortConnection.captureLease()
        tabManager.tabRuntimeLifecycle.replaceRuntimePortsForTests(replacement)
        let tab = Tab()
        let sourceRevision = tab.profileAssignment.changeRevision

        let outcome = tabManager.tabProfileTransitions.start(
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

    func testRetainedServiceDoesNotRetainBrowserManager() throws {
        var tabManager: BrowserManager? = BrowserManager()
        let retainedService = try XCTUnwrap(
            tabManager?.tabProfileTransitions
        )
        weak let releasedManager = tabManager

        tabManager = nil

        withExtendedLifetime(retainedService) {
            XCTAssertNil(releasedManager)
        }
    }

    func testProfilelessPlacementWithoutAdmissionWitnessRejectsBeforeMutation()
        throws {
        let fixture = try RegularPlacementFailClosedFixture()
        let target = Space(name: "Unassigned")
        fixture.state.spaces.replaceSpaces([target])
        let tab = Tab()

        let placement = fixture.placement.prepare(
            tab,
            in: target.id,
            at: 0,
            admissionProfileIDs: nil
        )

        XCTAssertNil(placement)
        XCTAssertNil(tab.spaceId)
        XCTAssertNil(tab.profileId)
        XCTAssertTrue(fixture.state.regularTabs.tabs(in: target.id).isEmpty)
        XCTAssertFalse(fixture.membership.lookupContainsExact(tab))
    }

    func testProfileSettlementFailureDoesNotPublishMembership() throws {
        let fixture = try RegularPlacementFailClosedFixture()
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        let source = Space(name: "Source", profileId: sourceProfile.id)
        let target = Space(name: "Target", profileId: targetProfile.id)
        fixture.state.spaces.replaceSpaces([source, target])
        fixture.runtimeConnection.attach(TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profiles[$0] }
        ))
        let tab = Tab(spaceId: source.id)
        let placement = try XCTUnwrap(fixture.placement.prepare(
            tab,
            in: target.id,
            at: 0,
            admissionProfileIDs: nil
        ))
        var publicationCount = 0

        XCTAssertTrue(placement.stage())
        fixture.runtimeConnection.detach()
        XCTAssertFalse(placement.finish(publishing: {
            publicationCount += 1
            fixture.membership.attach(tab)
        }))

        XCTAssertEqual(publicationCount, 0)
        XCTAssertTrue(fixture.membership.lookupContainsExact(tab))
        XCTAssertTrue(placement.rollback())
        XCTAssertFalse(fixture.membership.lookupContainsExact(tab))
        XCTAssertTrue(fixture.state.regularTabs.tabs(in: target.id).isEmpty)
        XCTAssertEqual(tab.spaceId, source.id)
        XCTAssertNil(tab.profileId)
    }
}

@MainActor
private final class RegularPlacementFailClosedFixture {
    let state: TabStateStore
    let runtimeConnection: TabRuntimePortConnection
    let membership: TabCollectionMembershipOwner
    let placement: RegularTabPlacementTransaction
    private let retainedDatabase: SumiDatabase

    init() throws {
        let container = try makeInMemoryStartupDatabase()
        retainedDatabase = container
        let state = TabStateStore()
        self.state = state
        let runtimeConnection = TabRuntimePortConnection()
        self.runtimeConnection = runtimeConnection
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: TabStructureEventBus(),
            stateStore: state
        )
        let writes = TabStoreWriteExecutor(database: container)
        let persistence = TabStructuralPersistenceService(
            structuralStore: TabStructuralSnapshotStore(writes: writes),
            selectionStore: TabSelectionStore(writes: writes),
            runtimeStateCoalescer: RuntimeStateCoalescer { _ in },
            state: state
        )
        let mutations = TabStructuralCollectionMutationOwner(
            store: TabStructuralCollectionStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            snapshots: TabStructuralCollectionSnapshotStore(
                regularTabs: state.regularTabs,
                folders: state.folders,
                shortcutPins: state.shortcutPins
            ),
            publisher: TabStructuralMutationPublisher(
                persistence: persistence,
                faviconService: TabDependencyIsolationDefaults.faviconService,
                lookup: structuralLookup,
                changes: ObservableObjectPublisher(),
                regularTabs: state.regularTabs
            )
        )
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookup.lookupOwner,
            state: state,
            runtimePreparation: TabRuntimePreparationOwner(
                runtimeConnection: runtimeConnection
            ),
            runtimeConnection: runtimeConnection
        )
        self.membership = membership
        let policy = ProfileAssignmentPolicy(
            runtimeConnection: runtimeConnection,
            spaces: state.spaces,
            membership: membership,
            transientTabs: state.transientTabs
        )
        let profileTransitions = TabProfileTransitionService(
            runtimeConnection: runtimeConnection,
            policy: policy,
            pendingInheritance: PendingTabProfileInheritance(),
            publication: TabProfileTransitionPublication(
                spaces: state.spaces,
                membership: membership,
                persistence: persistence,
                structuralLookup: structuralLookup
            )
        )
        let admission = RegularTabPlacementAdmission(
            policy: policy,
            references: .testingAllowingReferences(),
            profiles: profileTransitions
        )
        placement = RegularTabPlacementTransaction(
            stateOwner: state.regularTabs,
            structuralMutations: mutations,
            structuralLookup: structuralLookup,
            admission: admission
        )
    }
}
