import XCTest

@testable import Sumi
import SumiWebRuntime

@MainActor
final class TabRuntimePortsAttachmentOwnerTests: XCTestCase {
    func testAttachBootstrapsExactRuntimeAndCanonicalState() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        let canonical = Tab()
        canonical.spaceId = space.id
        let staleSelection = Tab(id: canonical.id)
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.spaces.replaceCurrentSpace(space)
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [canonical],
        ])
        fixture.manager.stateStore.shortcutPins.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [pendingPin]
        )
        fixture.manager.stateStore.selection.replaceCurrentTab(staleSelection)
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

        let outcome = attachment.attach(runtime)

        XCTAssertEqual(outcome, .attached)
        XCTAssertTrue(fixture.manager.runtimePortConnection.current != nil)
        XCTAssertEqual(preparedTabIDs, [canonical.id])
        XCTAssertIdentical(fixture.manager.stateStore.selection.currentTab, canonical)
        XCTAssertEqual(themedSpaceIDs, [space.id])
        XCTAssertEqual(space.profileId, profileID)
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertEqual(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: profileID).map(\.id),
            [pendingPin.id]
        )
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testSecondAttachIsBusyUntilExplicitDetach() throws {
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        var secondPrepareCount = 0
        let first = TestRuntimePorts.make()
        let second = TestRuntimePorts.make(
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in secondPrepareCount += 1 }
            )
        )

        XCTAssertTrue(attachment.canAttach)
        XCTAssertEqual(
            attachment.attach(first),
            .attached
        )
        XCTAssertFalse(attachment.canAttach)
        XCTAssertEqual(
            attachment.attach(second),
            .busy
        )
        XCTAssertEqual(secondPrepareCount, 0)

        attachment.detach()
        XCTAssertTrue(attachment.canAttach)
        XCTAssertEqual(
            attachment.attach(second),
            .attached
        )
    }

    func testProfileQueryReentryCannotMutateAttachmentBeforeLeaseClaim() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
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
                    attachment.detach()
                )
                reentrantAttachOutcomes.append(
                    attachment.attach(replacement)
                )
                return firstProfileID
            },
            defaultProfileId: {
                defaultQueryCount += 1
                reentrantDetachResults.append(
                    attachment.detach()
                )
                reentrantAttachOutcomes.append(
                    attachment.attach(replacement)
                )
                return firstProfileID
            }
        )

        XCTAssertEqual(
            attachment.attach(first),
            .attached
        )

        XCTAssertEqual(currentQueryCount, 1)
        XCTAssertEqual(defaultQueryCount, 1)
        XCTAssertEqual(reentrantDetachResults, [false, false])
        XCTAssertEqual(reentrantAttachOutcomes, [.busy, .busy])
        XCTAssertEqual(replacementPreparationCount, 0)
        XCTAssertFalse(attachment.canAttach)
        XCTAssertTrue(attachment.detach())
        XCTAssertEqual(
            attachment.attach(replacement),
            .attached
        )
    }

    func testBusyStructuralStateDefersPinAdoptionWithoutRejectingAttachment() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        fixture.manager.stateStore.shortcutPins.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [ShortcutPin(
                id: UUID(),
                role: .favorite,
                profileId: nil,
                index: 0,
                launchURL: URL(string: "https://example.com")!,
                title: "Pending"
            )]
        )
        let structural = try XCTUnwrap(
            fixture.mutations.prepareAggregate()
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

        let outcome = attachment.attach(runtime)

        XCTAssertEqual(outcome, .attached)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)
        XCTAssertEqual(space.profileId, profileID)
        XCTAssertEqual(
            fixture.manager.stateStore.shortcutPins
                .pendingPinnedWithoutProfileSnapshot().count,
            1
        )
        XCTAssertTrue(structural.rollback())
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        XCTAssertEqual(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: profileID).count,
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
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: firstProfileID)
        let tab = Tab()
        tab.spaceId = space.id
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.spaces.replaceCurrentSpace(space)
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        fixture.manager.stateStore.shortcutPins.replaceAll(
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
                    attachment.detach()
                    replacementOutcome = attachment
                        .attach(replacement)
                }
            ),
            syncWorkspaceThemeAcrossWindows: { _, _ in
                firstThemeCount += 1
            }
        )

        let firstOutcome = attachment.attach(first)

        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(secondPrepareCount, 1)
        XCTAssertEqual(firstThemeCount, 0)
        XCTAssertIdentical(tab.sumiSettings, secondSettings)
        XCTAssertEqual(space.profileId, firstProfileID)
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: firstProfileID).isEmpty
        )
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: secondProfileID).map(\.id) == [pendingPin.id]
        )
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testPreparationUsesSingleSnapshotAndUnloadsReplacedTab() throws {
        let profileID = UUID()
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: profileID)
        let first = Tab()
        first.spaceId = space.id
        let replacement = Tab(id: first.id)
        replacement.spaceId = space.id
        let pendingPin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Pending"
        )
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [first],
        ])
        fixture.manager.stateStore.shortcutPins.replaceAll(
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
                    fixture.mutations.setTabs(
                        [replacement],
                        for: space.id
                    )
                }
            )
        )

        XCTAssertEqual(
            attachment.attach(runtime),
            .attached
        )
        XCTAssertEqual(prepared.count, 1)
        XCTAssertIdentical(prepared.first, first)
        XCTAssertEqual(unloaded.count, 1)
        XCTAssertIdentical(unloaded.first, first)
        let terminalMembership = fixture.membership
            .allTabs()
        XCTAssertEqual(terminalMembership.count, 1)
        XCTAssertIdentical(terminalMembership.first, replacement)
        XCTAssertEqual(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: profileID).map(\.id),
            [pendingPin.id]
        )
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testPendingPinReplacementDuringPreparationCommitsCurrentSource() throws {
        let profileID = UUID()
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: profileID)
        let tab = Tab()
        tab.spaceId = space.id
        let original = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://original.example")!,
            title: "Original"
        )
        let replacement = ShortcutPin(
            id: original.id,
            role: .favorite,
            profileId: nil,
            index: 0,
            launchURL: URL(string: "https://replacement.example")!,
            title: "Replacement"
        )
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        fixture.manager.stateStore.shortcutPins.replaceAll(
            pinnedByProfile: [:],
            spacePinnedShortcuts: [:],
            pendingPinnedWithoutProfile: [original]
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profileID },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                prepareTab: { _ in
                    fixture.manager.stateStore.shortcutPins.replaceAll(
                        pinnedByProfile: [:],
                        spacePinnedShortcuts: [:],
                        pendingPinnedWithoutProfile: [replacement]
                    )
                }
            )
        )

        XCTAssertEqual(
            attachment.attach(runtime),
            .attached
        )
        let adopted = try XCTUnwrap(
            fixture.manager.stateStore.shortcutPins
                .favoritePins(for: profileID).first
        )
        XCTAssertEqual(adopted.id, replacement.id)
        XCTAssertEqual(adopted.title, replacement.title)
        XCTAssertEqual(adopted.launchURL, replacement.launchURL)
        XCTAssertTrue(
            fixture.manager.stateStore.shortcutPins
                .pendingPinnedWithoutProfileSnapshot().isEmpty
        )
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testSameRegistryReattachInvalidatesPreviousLease() throws {
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let runtime = TestRuntimePorts.make()
        XCTAssertEqual(
            attachment.attach(runtime),
            .attached
        )
        let firstLease = fixture.manager.runtimePortConnection.captureLease()

        attachment.detach()
        XCTAssertEqual(
            attachment.attach(runtime),
            .attached
        )

        XCTAssertFalse(fixture.manager.runtimePortConnection.accepts(firstLease))
    }

    func testThemeReentryStopsStaleSettlementBeforeProfileReconciliation() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let fixture = try AttachmentFixture()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.spaces.replaceCurrentSpace(space)
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
                attachment.detach()
                replacementOutcome = attachment
                    .attach(replacement)
            }
        )

        let outcome = attachment.attach(first)

        XCTAssertEqual(outcome, .superseded)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(space.profileId, secondProfileID)
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testCommittedPrefixSurvivesRollbackAndRetriesRemainingSpace() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let firstSpace = Space(name: "First", profileId: nil)
        let secondSpace = Space(name: "Second", profileId: nil)
        let tab = Tab()
        tab.spaceId = firstSpace.id
        fixture.manager.stateStore.spaces.replaceSpaces([firstSpace, secondSpace])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
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
            attachment.attach(runtime),
            .attached
        )
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)

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
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)

        fixture.availability.publish()

        XCTAssertEqual(models.count, 3)

        try publishCommit(models[2])
        settlements[2](.committed)

        XCTAssertEqual(firstSpace.profileId, profileID)
        XCTAssertEqual(secondSpace.profileId, profileID)
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testRollbackKeepsAttachmentAndWaitsAfterOneEventDrivenRetry() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
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
            attachment.attach(runtime),
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
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)

        fixture.availability.publish()

        XCTAssertEqual(models.count, 2)
        fixture.transitionLifecycle.cancelPending(intents[1])
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertEqual(models.count, 2)

        fixture.availability.publish()

        XCTAssertEqual(models.count, 3)
        XCTAssertTrue(attachment.detach())
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testDetachConsumesPublishedCommitBeforeLateSettlement() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([space])
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
            attachment.attach(runtime),
            .attached
        )
        XCTAssertEqual(
            fixture.transitionLifecycle.inFlightProfileID(
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

        XCTAssertTrue(attachment.detach())

        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNil(fixture.manager.runtimePortConnection.current)
        let terminalProfileID = space.profileId

        try XCTUnwrap(settlement)(.committed)

        XCTAssertEqual(space.profileId, terminalProfileID)
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testConflictedReconciliationRemainsOwnedUntilDetachDrainsIt() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([space])
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
            attachment.attach(runtime),
            .attached
        )
        let conflictedModel = try XCTUnwrap(model)
        XCTAssertTrue(conflictedModel.validateForStaging())
        try conflictedModel.stage()
        try XCTUnwrap(settlement)(.conflicted)

        XCTAssertNotNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertTrue(attachment.detach())
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNil(fixture.manager.runtimePortConnection.current)
    }

    func testDetachConsumesPublishedRollbackBeforeLateSettlement() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([space])
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
            attachment.attach(runtime),
            .attached
        )
        let rolledBack = try XCTUnwrap(model)
        XCTAssertTrue(rolledBack.validateForStaging())
        try rolledBack.stage()
        try rolledBack.rollback()
        rolledBack.publishRollback()

        XCTAssertTrue(attachment.detach())
        XCTAssertNil(space.profileId)
        XCTAssertNil(fixture.manager.runtimePortConnection.current)

        try XCTUnwrap(settlement)(.rolledBack(.abort(.superseded)))

        XCTAssertNil(space.profileId)
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testPostAttachmentTopologyConflictIsDrainedBeforeDetach() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let original = Space(name: "Current", profileId: nil)
        let replacement = Space(
            id: original.id,
            name: "Replacement",
            profileId: nil
        )
        let tab = Tab()
        tab.spaceId = original.id
        fixture.manager.stateStore.spaces.replaceSpaces([original])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
            original.id: [tab],
        ])
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, _, _ in
                fixture.manager.stateStore.spaces.replaceSpaces([replacement])
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
            attachment.attach(runtime),
            .attached
        )
        XCTAssertEqual(preparationCount, 1)
        XCTAssertNil(replacement.profileId)
        XCTAssertNotNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: original.id
            )
        )
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)

        attachment.detach()

        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: original.id
            )
        )
        XCTAssertNil(fixture.manager.runtimePortConnection.current)
    }

    func testRepositoryTerminalDrainReleasesDeferredWorkBeforeLateSettlement()
        throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([space])
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
            attachment.attach(runtime),
            .attached
        )
        let exactModel = try XCTUnwrap(model)
        XCTAssertTrue(exactModel.validateForStaging())
        try exactModel.stage()
        XCTAssertTrue(exactModel.canSettleTerminalDrain())
        XCTAssertTrue(exactModel.settleTerminalDrain())
        let terminalProfileID = space.profileId

        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)

        try XCTUnwrap(settlement)(.committed)

        XCTAssertEqual(space.profileId, terminalProfileID)
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
    }

    func testExistingPendingTransitionWakesDeferredAttachmentWork() throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let firstSpace = Space(name: "First", profileId: nil)
        let secondSpace = Space(name: "Second", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([firstSpace, secondSpace])
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
        fixture.manager.runtimePortConnection.attach(runtime)
        XCTAssertEqual(
            fixture.spaceTransitions.start(
                spaceID: firstSpace.id,
                profileID: profileID
            ),
            .deferred
        )
        fixture.manager.runtimePortConnection.detach()

        XCTAssertEqual(
            attachment.attach(runtime),
            .attached
        )
        XCTAssertEqual(models.count, 1)

        try publishCommit(models[0])
        settlements[0](.committed)

        XCTAssertEqual(firstSpace.profileId, profileID)
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(
            fixture.transitionLifecycle.inFlightProfileID(
                for: secondSpace.id
            ),
            profileID
        )
        XCTAssertTrue(attachment.detach())
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: secondSpace.id
            )
        )
    }

    func testReplacementAttachmentDuringReconciliationFailsClosed() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let space = Space(name: "Current", profileId: nil)
        let tab = Tab()
        tab.spaceId = space.id
        fixture.manager.stateStore.spaces.replaceSpaces([space])
        fixture.manager.stateStore.regularTabs.replaceTabsBySpace([
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
                reentrantDetachResult = attachment
                    .detach()
                replacementOutcome = attachment
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

        let firstOutcome = attachment.attach(first)

        XCTAssertEqual(firstOutcome, .superseded)
        XCTAssertEqual(reentrantDetachResult, true)
        XCTAssertEqual(replacementOutcome, .attached)
        XCTAssertEqual(replacementPreparationCount, 1)
        XCTAssertEqual(replacementTransitionCount, 0)
        XCTAssertEqual(space.profileId, firstProfileID)
        XCTAssertNil(
            fixture.transitionLifecycle.inFlightProfileID(
                for: space.id
            )
        )
        XCTAssertNotNil(fixture.manager.runtimePortConnection.current)
        fixture.manager.structuralPersistence.cancelPendingPersistence()
    }

    func testSpaceRemainsReservedUntilPublishedModelSettlementArrives() throws {
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let firstProfile = Profile(id: firstProfileID, name: "First")
        let secondProfile = Profile(id: secondProfileID, name: "Second")
        let fixture = try AttachmentFixture().profileView()
        let attachment = fixture.attachment
        let committedSpace = Space(name: "Committed", profileId: nil)
        let rolledBackSpace = Space(name: "Rolled Back", profileId: nil)
        fixture.manager.stateStore.spaces.replaceSpaces([
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
        fixture.manager.runtimePortConnection.attach(runtime)

        XCTAssertEqual(
            fixture.spaceTransitions.start(
                spaceID: committedSpace.id,
                profileID: firstProfileID
            ),
            .deferred
        )
        try publishCommit(models[0])
        XCTAssertEqual(
            fixture.spaceTransitions.start(
                spaceID: committedSpace.id,
                profileID: secondProfileID
            ),
            .failed
        )
        settlements[0](.committed)
        XCTAssertEqual(
            fixture.spaceTransitions.start(
                spaceID: committedSpace.id,
                profileID: secondProfileID
            ),
            .deferred
        )
        fixture.transitionLifecycle.cancelPending(intents[1])

        XCTAssertEqual(
            fixture.spaceTransitions.start(
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
            fixture.spaceTransitions.start(
                spaceID: rolledBackSpace.id,
                profileID: secondProfileID
            ),
            .failed
        )
        settlements[2](.rolledBack(.abort(.superseded)))
        XCTAssertEqual(
            fixture.spaceTransitions.start(
                spaceID: rolledBackSpace.id,
                profileID: secondProfileID
            ),
            .deferred
        )
        fixture.transitionLifecycle.cancelPending(intents[3])
        fixture.manager.runtimePortConnection.detach()
        fixture.manager.structuralPersistence.cancelPendingPersistence()
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

@MainActor
private final class AttachmentFixture {
    let manager: TabManager
    let attachment: TabRuntimePortsAttachmentOwner
    let membership: TabCollectionMembershipOwner
    let mutations: TabStructuralCollectionMutationOwner

    private let spaceTransitions: SpaceProfileTransitionService
    private let transitionLifecycle: SpaceProfileTransitionRepository
    private let availability: SpaceProfileTransitionPublication

    init() throws {
        let container = try makeInMemoryStartupDatabase()
        let eventBus = TabStructureEventBus()
        let manager = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            loadPersistedState: false,
            tabStructureEventBus: eventBus
        )
        let state = manager.stateStore
        let connection = manager.runtimePortConnection
        let runtimePreparation = TabRuntimePreparationOwner(
            runtimeConnection: connection
        )
        let structuralLookup = TabStructuralLookupCoordinator(
            eventBus: eventBus,
            stateStore: state
        )
        let mutationPublisher = TabStructuralMutationPublisher(
            persistence: manager.structuralPersistence,
            faviconService: manager.faviconService,
            lookup: structuralLookup,
            changes: manager.objectWillChange,
            regularTabs: state.regularTabs
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
            publisher: mutationPublisher
        )
        let membership = TabCollectionMembershipOwner(
            structuralLookupOwner: structuralLookup.lookupOwner,
            state: state,
            runtimePreparation: runtimePreparation,
            runtimeConnection: connection
        )
        let runtimeTeardown = TabRuntimeTeardownService(
            persistence: manager.structuralPersistence,
            membership: membership,
            webViewSessions: manager.tabFactory.webViewSessions
        )
        let liveShortcutTabs = LiveShortcutTabRegistry(
            storage: state.transientTabs,
            structuralLookup: structuralLookup
        )
        let profileGraph = SpaceProfileTransitionService.compose(
            spaces: state.spaces,
            pins: state.shortcutPins,
            registry: liveShortcutTabs,
            runtimeConnection: connection,
            runtimeTeardown: runtimeTeardown,
            structuralLookup: structuralLookup,
            membership: membership,
            persistence: manager.structuralPersistence,
            pendingInheritance: PendingTabProfileInheritance(),
            changes: manager.objectWillChange
        )
        let pendingPins = PendingShortcutPinAdopter(
            pins: state.shortcutPins,
            structuralMutations: mutations,
            profileReferenceAdmission: manager.profileReferenceAdmission
        )
        let deferredWork = TabRuntimeAttachmentDeferredWorkOwner(
            connection: connection,
            spaceProfiles: SpaceProfileReconciliationService(
                spaces: state.spaces,
                runtimeConnection: connection,
                spaceTransitions: profileGraph.service,
                transitionLifecycle: profileGraph.lifecycle
            ),
            spaceAvailability: profileGraph.availability,
            pendingPins: pendingPins
        )
        attachment = TabRuntimePortsAttachmentOwner(
            connection: connection,
            bootstrap: TabRuntimeAttachmentBootstrap(
                connection: connection,
                membership: membership,
                runtimePreparation: runtimePreparation,
                selection: state.selection
            ),
            settlement: TabRuntimeAttachmentSettlement(
                connection: connection,
                spaces: state.spaces,
                deferredWork: deferredWork,
                restoreStarter: nil
            )
        )
        self.manager = manager
        self.membership = membership
        self.mutations = mutations
        spaceTransitions = profileGraph.service
        transitionLifecycle = profileGraph.lifecycle
        availability = profileGraph.availability
    }

    func profileView() -> ProfileAttachmentFixture {
        ProfileAttachmentFixture(owner: self)
    }

    fileprivate var profileService: SpaceProfileTransitionService {
        spaceTransitions
    }

    fileprivate var profileLifecycle: SpaceProfileTransitionRepository {
        transitionLifecycle
    }

    fileprivate var profileAvailability: SpaceProfileTransitionPublication {
        availability
    }
}

@MainActor
private struct ProfileAttachmentFixture {
    private let owner: AttachmentFixture

    init(owner: AttachmentFixture) {
        self.owner = owner
    }

    var manager: TabManager { owner.manager }
    var attachment: TabRuntimePortsAttachmentOwner { owner.attachment }
    var spaceTransitions: SpaceProfileTransitionService { owner.profileService }
    var transitionLifecycle: SpaceProfileTransitionRepository {
        owner.profileLifecycle
    }

    var availability: SpaceProfileTransitionPublication {
        owner.profileAvailability
    }
}
