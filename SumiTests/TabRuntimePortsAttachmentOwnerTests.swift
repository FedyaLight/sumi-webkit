import XCTest

@testable import Sumi
import SumiWebRuntime

@MainActor
final class TabRuntimePortsAttachmentOwnerTests: XCTestCase {
    func testAttachBootstrapsExactRuntimeAndCanonicalState() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        let canonical = Tab()
        canonical.spaceId = space.id
        let staleSelection = Tab(id: canonical.id)
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [canonical],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin]
        )
        tabManager.selectionStateOwner.replaceCurrentTab(staleSelection)
        var preparedTabIDs: [UUID] = []
        var themedSpaceIDs: [UUID] = []
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { preparedTabIDs.append($0.id) }
            ),
            syncWorkspaceThemeAcrossWindows: { received, animate in
                XCTAssertFalse(animate)
                themedSpaceIDs.append(received.id)
            }
        )

        let outcome = tabManager.runtimePortsAttachmentOwner.attach(runtime)

        XCTAssertEqual(outcome, .attached)
        XCTAssertTrue(tabManager.runtimePortConnection.current != nil)
        XCTAssertEqual(preparedTabIDs, [canonical.id])
        XCTAssertIdentical(tabManager.selectionStateOwner.currentTab, canonical)
        XCTAssertEqual(themedSpaceIDs, [space.id])
        XCTAssertEqual(space.profileId, profileID)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).map(\.id),
            [pendingPin.id]
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testSecondAttachIsBusyUntilExplicitDetach() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        var secondPrepareCount = 0
        let first = TestRuntimePorts.make()
        let second = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in secondPrepareCount += 1 }
            )
        )

        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.canAttach)
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(first),
            .attached
        )
        XCTAssertFalse(tabManager.runtimePortsAttachmentOwner.canAttach)
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(second),
            .busy
        )
        XCTAssertEqual(secondPrepareCount, 0)

        tabManager.runtimePortsAttachmentOwner.detach()
        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.canAttach)
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(second),
            .attached
        )
    }

    func testProfileQueryReentryCannotMutateAttachmentBeforeLeaseClaim() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        var replacementPreparationCount = 0
        let replacement = TestRuntimePorts.make(
            currentProfileId: { secondProfileID },
            defaultProfileId: { secondProfileID },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in replacementPreparationCount += 1 }
            )
        )
        var currentQueryCount = 0
        var defaultQueryCount = 0
        var reentrantDetachResults: [Bool] = []
        var reentrantAttachOutcomes: [TabRuntimePortsAttachmentOwner.Outcome] = []
        let first = TestRuntimePorts.make(
            currentProfileId: {
                currentQueryCount += 1
                reentrantDetachResults.append(
                    tabManager.runtimePortsAttachmentOwner.detach()
                )
                reentrantAttachOutcomes.append(
                    tabManager.runtimePortsAttachmentOwner.attach(replacement)
                )
                return firstProfileID
            },
            defaultProfileId: {
                defaultQueryCount += 1
                reentrantDetachResults.append(
                    tabManager.runtimePortsAttachmentOwner.detach()
                )
                reentrantAttachOutcomes.append(
                    tabManager.runtimePortsAttachmentOwner.attach(replacement)
                )
                return firstProfileID
            }
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(first),
            .attached
        )

        XCTAssertEqual(currentQueryCount, 1)
        XCTAssertEqual(defaultQueryCount, 1)
        XCTAssertEqual(reentrantDetachResults, [false, false])
        XCTAssertEqual(reentrantAttachOutcomes, [.busy, .busy])
        XCTAssertEqual(replacementPreparationCount, 0)
        XCTAssertFalse(tabManager.runtimePortsAttachmentOwner.canAttach)
        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(replacement),
            .attached
        )
    }

    func testBusyStructuralStateDefersPinAdoptionWithoutRejectingAttachment() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [ShortcutPin(
                id: UUID(),
                role: .essential,
                profileId: nil,
                index: 0,
                launchURL: URL(string: "https://example.com")!,
                title: "Pending"
            )]
        )
        let structural = try XCTUnwrap(
            tabManager.structuralCollectionMutationOwner.prepareAggregate()
        )
        var preparationCount = 0
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in preparationCount += 1 }
            )
        )

        let outcome = tabManager.runtimePortsAttachmentOwner.attach(runtime)

        XCTAssertEqual(outcome, .attached)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)
        XCTAssertEqual(space.profileId, profileID)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().count,
            1
        )
        XCTAssertTrue(structural.rollback())
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).count,
            1
        )
    }

    func testPreparationReentryCannotMixRuntimeGenerations() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let firstSettings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let secondSettings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: firstProfileID)
        let tab = Tab()
        tab.spaceId = space.id
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin]
        )
        var firstThemeCount = 0
        var secondPrepareCount = 0
        var replacementOutcome: TabRuntimePortsAttachmentOwner.Outcome?
        let replacement = TestRuntimePorts.make(
            currentProfileId: { secondProfileID },
            defaultProfileId: { secondProfileID },
            settings: { secondSettings },
            profile: { $0 == secondProfileID ? secondProfile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in secondPrepareCount += 1 }
            )
        )
        var didReenter = false
        let first = TestRuntimePorts.make(
            currentProfileId: { firstProfileID },
            defaultProfileId: { firstProfileID },
            settings: { firstSettings },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in
                    guard didReenter == false else { return }
                    didReenter = true
                    tabManager.runtimePortsAttachmentOwner.detach()
                    replacementOutcome = tabManager.runtimePortsAttachmentOwner
                        .attach(replacement)
                }
            ),
            syncWorkspaceThemeAcrossWindows: { _, _ in
                firstThemeCount += 1
            }
        )

        let firstOutcome = tabManager.runtimePortsAttachmentOwner.attach(first)

        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(secondPrepareCount, 1)
        XCTAssertEqual(firstThemeCount, 0)
        XCTAssertIdentical(tab.sumiSettings, secondSettings)
        XCTAssertEqual(space.profileId, firstProfileID)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: firstProfileID).isEmpty
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: secondProfileID).map(\.id) == [pendingPin.id]
        )
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testPreparationReentryPreparesExpandedMembershipFixedPoint() throws {
        let profileID = UUID()
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: profileID)
        let first = Tab()
        first.spaceId = space.id
        let replacement = Tab()
        replacement.spaceId = space.id
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Pending"
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [first],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin]
        )
        var prepared: [Tab] = []
        var unloaded: [Tab] = []
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                unloadTab: { unloaded.append($0) },
                prepareTab: { tab in
                    prepared.append(tab)
                    guard tab === first else { return }
                    tabManager.structuralCollectionMutationOwner.setTabs(
                        [replacement],
                        for: space.id
                    )
                }
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        XCTAssertEqual(prepared.count, 2)
        XCTAssertTrue(prepared.contains { $0 === first })
        XCTAssertTrue(prepared.contains { $0 === replacement })
        XCTAssertEqual(unloaded.count, 1)
        XCTAssertIdentical(unloaded.first, first)
        let terminalMembership = tabManager.tabCollectionMembershipOwner
            .allTabs()
        XCTAssertEqual(terminalMembership.count, 1)
        XCTAssertIdentical(terminalMembership.first, replacement)
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).map(\.id),
            [pendingPin.id]
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testPendingPinReplacementDuringPreparationCommitsCurrentSource() throws {
        let profileID = UUID()
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: profileID)
        let tab = Tab()
        tab.spaceId = space.id
        let original = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://original.example")!,
            title: "Original"
        )
        let replacement = ShortcutPin(
            id: original.id,
            role: .essential,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://replacement.example")!,
            title: "Replacement"
        )
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [original]
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in
                    tabManager.shortcutPinCollectionStateOwner.replaceAll(
                        pinnedByProfile: [:],
                        spacePinnedShortcuts: [:],
                        pendingPinnedWithoutProfile: [replacement]
                    )
                }
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let adopted = try XCTUnwrap(
            tabManager.shortcutPinCollectionStateOwner
                .essentialPins(for: profileID).first
        )
        XCTAssertEqual(adopted.id, replacement.id)
        XCTAssertEqual(adopted.title, replacement.title)
        XCTAssertEqual(adopted.launchURL, replacement.launchURL)
        XCTAssertTrue(
            tabManager.shortcutPinCollectionStateOwner
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testSameRegistryReattachInvalidatesPreviousLease() throws {
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let runtime = TestRuntimePorts.make()
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let firstLease = tabManager.runtimePortConnection.captureLease()

        tabManager.runtimePortsAttachmentOwner.detach()
        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )

        XCTAssertFalse(tabManager.runtimePortConnection.accepts(firstLease))
    }

    func testThemeReentryStopsStaleSettlementBeforeProfileReconciliation() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        let replacement = TestRuntimePorts.make(
            currentProfileId: { secondProfileID },
            defaultProfileId: { secondProfileID },
            profile: { $0 == secondProfileID ? secondProfile : nil }
        )
        var didReenter = false
        var replacementOutcome: TabRuntimePortsAttachmentOwner.Outcome?
        let first = TestRuntimePorts.make(
            currentProfileId: { firstProfileID },
            defaultProfileId: { firstProfileID },
            profile: { $0 == firstProfileID ? firstProfile : nil },
            syncWorkspaceThemeAcrossWindows: { _, _ in
                guard didReenter == false else { return }
                didReenter = true
                tabManager.runtimePortsAttachmentOwner.detach()
                replacementOutcome = tabManager.runtimePortsAttachmentOwner
                    .attach(replacement)
            }
        )

        let outcome = tabManager.runtimePortsAttachmentOwner.attach(first)

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(space.profileId, secondProfileID)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testCommittedPrefixSurvivesRollbackAndRetriesRemainingSpace() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let firstSpace = Space(name: "First", profileId: nil)
        let secondSpace = Space(name: "Second", profileId: nil)
        let tab = Tab()
        tab.spaceId = firstSpace.id
        tabManager.spaceStateOwner.replaceSpaces([firstSpace, secondSpace])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            firstSpace.id: [tab],
        ])
        var models: [any SpaceProfileWebViewReplacementTransaction] = []
        var settlements: [ProfileTransitionService.Settlement] = []
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, model, settlement in
                models.append(model)
                settlements.append(settlement)
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        var preparationCount = 0
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in preparationCount += 1 },
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)

        try publishCommit(models[0])
        settlements[0](.committed)

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(firstSpace.profileId, profileID)

        XCTAssertTrue(models[1].validateForStaging())
        try models[1].stage()
        try models[1].rollback()
        models[1].publishRollback()
        settlements[1](.rolledBack(.abort(.superseded)))

        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(firstSpace.profileId, profileID)
        XCTAssertNil(secondSpace.profileId)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)

        tabManager.profileAssignments.spaceAvailability.publish()

        XCTAssertEqual(models.count, 3)

        try publishCommit(models[2])
        settlements[2](.committed)

        XCTAssertEqual(firstSpace.profileId, profileID)
        XCTAssertEqual(secondSpace.profileId, profileID)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testRollbackKeepsAttachmentAndWaitsAfterOneEventDrivenRetry() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        var models: [any SpaceProfileWebViewReplacementTransaction] = []
        var settlements: [ProfileTransitionService.Settlement] = []
        var intents: [DeferredWebViewSpaceProfileAssignmentIntent] = []
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, intent, received, settlement in
                intents.append(intent)
                models.append(received)
                settlements.append(settlement)
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        var preparationCount = 0
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in preparationCount += 1 },
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let exactModel = try XCTUnwrap(models.first)
        XCTAssertTrue(exactModel.validateForStaging())
        try exactModel.stage()
        try exactModel.rollback()
        exactModel.publishRollback()
        try XCTUnwrap(settlements.first)(.rolledBack(.abort(.superseded)))

        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNil(space.profileId)
        XCTAssertNotNil(tabManager.runtimePortConnection.current)

        tabManager.profileAssignments.spaceAvailability.publish()

        XCTAssertEqual(models.count, 2)
        tabManager.profileAssignments.spaceLifecycle.cancelPending(intents[1])
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertEqual(models.count, 2)

        tabManager.profileAssignments.spaceAvailability.publish()

        XCTAssertEqual(models.count, 3)
        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testDetachConsumesPublishedCommitBeforeLateSettlement() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        var model: (any SpaceProfileWebViewReplacementTransaction)?
        var settlement: ProfileTransitionService.Settlement?
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, received, callback in
                model = received
                settlement = callback
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        XCTAssertEqual(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            ),
            profileID
        )
        let staged = try XCTUnwrap(model)
        XCTAssertTrue(staged.validateForStaging())
        try staged.stage()
        XCTAssertTrue(staged.stagedModelIsExact())
        XCTAssertTrue(staged.canClaimTerminalModel())
        XCTAssertEqual(staged.claimTerminalModel(), .sealed)
        staged.publishCommit()
        XCTAssertEqual(space.profileId, profileID)

        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())

        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNil(tabManager.runtimePortConnection.current)
        let terminalProfileID = space.profileId

        try XCTUnwrap(settlement)(.committed)

        XCTAssertEqual(space.profileId, terminalProfileID)
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testConflictedReconciliationRemainsOwnedUntilDetachDrainsIt() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        var model: (any SpaceProfileWebViewReplacementTransaction)?
        var settlement: ProfileTransitionService.Settlement?
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, received, callback in
                model = received
                settlement = callback
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let conflictedModel = try XCTUnwrap(model)
        XCTAssertTrue(conflictedModel.validateForStaging())
        try conflictedModel.stage()
        try XCTUnwrap(settlement)(.conflicted)

        XCTAssertNotNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNil(tabManager.runtimePortConnection.current)
    }

    func testDetachConsumesPublishedRollbackBeforeLateSettlement() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        var model: (any SpaceProfileWebViewReplacementTransaction)?
        var settlement: ProfileTransitionService.Settlement?
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, received, callback in
                model = received
                settlement = callback
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let rolledBack = try XCTUnwrap(model)
        XCTAssertTrue(rolledBack.validateForStaging())
        try rolledBack.stage()
        try rolledBack.rollback()
        rolledBack.publishRollback()

        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
        XCTAssertNil(space.profileId)
        XCTAssertNil(tabManager.runtimePortConnection.current)

        try XCTUnwrap(settlement)(.rolledBack(.abort(.superseded)))

        XCTAssertNil(space.profileId)
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testPostAttachmentTopologyConflictIsDrainedBeforeDetach() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let original = Space(name: "Current", profileId: nil)
        let replacement = Space(
            id: original.id,
            name: "Replacement",
            profileId: nil
        )
        let tab = Tab()
        tab.spaceId = original.id
        tabManager.spaceStateOwner.replaceSpaces([original])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            original.id: [tab],
        ])
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, _, _ in
                tabManager.spaceStateOwner.replaceSpaces([replacement])
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        var preparationCount = 0
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in preparationCount += 1 },
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNil(replacement.profileId)
        XCTAssertNotNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: original.id
            )
        )
        XCTAssertNotNil(tabManager.runtimePortConnection.current)

        tabManager.runtimePortsAttachmentOwner.detach()

        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: original.id
            )
        )
        XCTAssertNil(tabManager.runtimePortConnection.current)
    }

    func testRepositoryTerminalDrainReleasesDeferredWorkBeforeLateSettlement()
        throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        var model: (any SpaceProfileWebViewReplacementTransaction)?
        var settlement: ProfileTransitionService.Settlement?
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, received, callback in
                model = received
                settlement = callback
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        let exactModel = try XCTUnwrap(model)
        XCTAssertTrue(exactModel.validateForStaging())
        try exactModel.stage()
        XCTAssertTrue(exactModel.canSettleTerminalDrain())
        XCTAssertTrue(exactModel.settleTerminalDrain())
        let terminalProfileID = space.profileId

        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNotNil(tabManager.runtimePortConnection.current)

        try XCTUnwrap(settlement)(.committed)

        XCTAssertEqual(space.profileId, terminalProfileID)
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testExistingPendingTransitionWakesDeferredAttachmentWork() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let firstSpace = Space(name: "First", profileId: nil)
        let secondSpace = Space(name: "Second", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([firstSpace, secondSpace])
        var models: [any SpaceProfileWebViewReplacementTransaction] = []
        var settlements: [ProfileTransitionService.Settlement] = []
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, model, settlement in
                models.append(model)
                settlements.append(settlement)
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            defaultProfileId: { profileID },
            profile: { $0 == profileID ? profile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )
        tabManager.runtimePortConnection.attach(runtime)
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: firstSpace.id,
                profileID: profileID
            ),
            .deferred
        )
        tabManager.runtimePortConnection.detach()

        XCTAssertEqual(
            tabManager.runtimePortsAttachmentOwner.attach(runtime),
            .attached
        )
        XCTAssertEqual(models.count, 1)

        try publishCommit(models[0])
        settlements[0](.committed)

        XCTAssertEqual(firstSpace.profileId, profileID)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: secondSpace.id
            ),
            profileID
        )
        XCTAssertTrue(tabManager.runtimePortsAttachmentOwner.detach())
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: secondSpace.id
            )
        )
    }

    func testReplacementAttachmentDuringReconciliationFailsClosed() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])

        var replacementPreparationCount = 0
        var replacementTransitionCount = 0
        let replacementTransitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, settlement in
                let outcome = tab.profileAssignment.commit(intent)
                    ? TabProfileAssignmentExecutionOutcome.committed
                    : .stale
                if let immediate = outcome.immediateSettlement {
                    settlement(immediate)
                }
                return outcome
            },
            executeSpace: { _, _, _, model, settlement in
                replacementTransitionCount += 1
                guard model.validateForStaging() else {
                    settlement(.rejected(.stale))
                    return .stale
                }
                let outcome = ProfileTransitionModelOnlySettlement.execute(
                    .transaction(model)
                )
                settlement(outcome.settlement)
                return outcome.tabExecution
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let replacement = TestRuntimePorts.make(
            currentProfileId: { secondProfileID },
            defaultProfileId: { secondProfileID },
            profile: { $0 == secondProfileID ? secondProfile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in replacementPreparationCount += 1 },
                profileTransitions: replacementTransitions
            )
        )
        var replacementOutcome: TabRuntimePortsAttachmentOwner.Outcome?
        var reentrantDetachResult: Bool?
        let reentrantTransitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, model, settlement in
                guard model.validateForStaging() else { return .stale }
                do {
                    try model.stage()
                } catch {
                    return .failed
                }
                XCTAssertEqual(space.profileId, firstProfileID)
                reentrantDetachResult = tabManager.runtimePortsAttachmentOwner
                    .detach()
                replacementOutcome = tabManager.runtimePortsAttachmentOwner
                    .attach(replacement)
                settlement(.committed)
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let first = TestRuntimePorts.make(
            currentProfileId: { firstProfileID },
            defaultProfileId: { firstProfileID },
            profile: { $0 == firstProfileID ? firstProfile : nil },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: reentrantTransitions
            )
        )

        let firstOutcome = tabManager.runtimePortsAttachmentOwner.attach(first)

        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(reentrantDetachResult, true)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(replacementPreparationCount, 1)
        XCTAssertEqual(replacementTransitionCount, 0)
        XCTAssertEqual(space.profileId, firstProfileID)
        XCTAssertNil(
            tabManager.profileAssignments.spaceLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNotNil(tabManager.runtimePortConnection.current)
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    func testSpaceRemainsReservedUntilPublishedModelSettlementArrives() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let tabManager = try makeInMemoryTabManager(attachRuntimePorts: false)
        let committedSpace = Space(name: "Committed", profileId: nil)
        let rolledBackSpace = Space(name: "Rolled Back", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([
            committedSpace,
            rolledBackSpace,
        ])
        var models: [any SpaceProfileWebViewReplacementTransaction] = []
        var intents: [DeferredWebViewSpaceProfileAssignmentIntent] = []
        var settlements: [ProfileTransitionService.Settlement] = []
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, intent, model, settlement in
                intents.append(intent)
                models.append(model)
                settlements.append(settlement)
                return .deferred
            },
            executePrepared: { _, _, _ in .rejectedUnstaged(.failed) }
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { firstProfileID },
            defaultProfileId: { firstProfileID },
            profile: { id in
                switch id {
                case firstProfileID: firstProfile
                case secondProfileID: secondProfile
                default: nil
                }
            },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                profileTransitions: transitions
            )
        )
        tabManager.runtimePortConnection.attach(runtime)

        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: committedSpace.id,
                profileID: firstProfileID
            ),
            .deferred
        )
        try publishCommit(models[0])
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: committedSpace.id,
                profileID: secondProfileID
            ),
            .failed
        )
        settlements[0](.committed)
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: committedSpace.id,
                profileID: secondProfileID
            ),
            .deferred
        )
        tabManager.profileAssignments.spaceLifecycle.cancelPending(intents[1])

        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: rolledBackSpace.id,
                profileID: firstProfileID
            ),
            .deferred
        )
        XCTAssertTrue(models[2].validateForStaging())
        try models[2].stage()
        try models[2].rollback()
        models[2].publishRollback()
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: rolledBackSpace.id,
                profileID: secondProfileID
            ),
            .failed
        )
        settlements[2](.rolledBack(.abort(.superseded)))
        XCTAssertEqual(
            tabManager.profileAssignments.spaces.start(
                spaceID: rolledBackSpace.id,
                profileID: secondProfileID
            ),
            .deferred
        )
        tabManager.profileAssignments.spaceLifecycle.cancelPending(intents[3])
        tabManager.runtimePortConnection.detach()
        tabManager.structuralPersistence.cancelPendingPersistence()
    }

    private func publishCommit(
        _ model: any SpaceProfileWebViewReplacementTransaction
    ) throws {
        XCTAssertTrue(model.validateForStaging())
        try model.stage()
        XCTAssertTrue(model.stagedModelIsExact())
        XCTAssertTrue(model.canClaimTerminalModel())
        XCTAssertEqual(model.claimTerminalModel(), .sealed)
        XCTAssertTrue(model.claimedModelIsExact())
        model.publishCommit()
    }
}
