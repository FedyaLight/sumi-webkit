import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
extension SpaceProfileRetirementTransactionTests {
    func testAdapterRejectsInvalidModelAndWrongRollbackReceiptFailClosed()
        throws {
        let repository = WebViewSessionRepository()
        let tabManager = try makeBrowser(webViewSessions: repository)
        let runtimeTeardown = makeRuntimeTeardown(for: tabManager)
        let tab = tabManager.tabFactory.makeTab(
            existingWebView: WKWebView(),
            loadsCachedFaviconOnInit: false
        )
        let transition = DeferredSpaceProfileTransition()
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: transition.makeLifecycle()
        )
        let retiredWebView = try XCTUnwrap(tab.webViewSession.parkedWebView)
        var invalidCommitCount = 0
        let invalidReceipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { false },
            commit: {
                invalidCommitCount += 1
                return true
            },
            rollback: { true }
        )

        guard case .modelValidationFailed = runtimeTeardown
            .retirement.begin(
                tabs: [tab],
                using: runtime,
                modelTransaction: invalidReceipt
            ) else { return XCTFail("Expected model validation rejection") }
        XCTAssertEqual(invalidCommitCount, 0)
        XCTAssertNotNil(tab.webViewSession.parkedWebView)

        let exactReceipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { true },
            commit: { true },
            rollback: { true }
        )
        guard case .began(let exactBatch) = runtimeTeardown
            .retirement.begin(
                tabs: [tab],
                using: runtime,
                modelTransaction: exactReceipt
            ) else { return XCTFail("Expected exact retirement batch") }
        let wrongReceipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { true },
            commit: { true },
            rollback: { true }
        )
        let wrongBatch = TabRuntimeRetirementBatch(
            tabs: exactBatch.tabs,
            runtimeTabIDs: exactBatch.runtimeTabIDs,
            runtime: exactBatch.runtime,
            lease: exactBatch.lease,
            modelTransaction: wrongReceipt
        )

        XCTAssertEqual(
            runtimeTeardown.retirement.rollback(wrongBatch),
            .modelTransactionMismatch
        )
        guard case .retiring = repository.residence(of: retiredWebView) else {
            return XCTFail("Wrong receipt must retain quarantine")
        }
        XCTAssertEqual(
            runtimeTeardown.retirement.rollback(exactBatch),
            .rolledBack
        )
    }

    func testRollbackRestoresRemovedExactSpaceWitness() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        try stageProfileChange(fixture, transition: transition)

        fixture.tabManager.spaceStateOwner.replaceSpaces([])
        XCTAssertFalse(try XCTUnwrap(transition.stagedModelIsExact)())

        try XCTUnwrap(transition.rollbackModel)()

        XCTAssertTrue(fixture.tabManager.spaceStateOwner.spaces.isEmpty)
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
    }

    func testRollbackDoesNotRebindToSameIDSpaceReplacement() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        try stageProfileChange(fixture, transition: transition)
        let replacement = Space(
            id: fixture.space.id,
            name: "Replacement",
            profileId: fixture.targetProfile.id
        )

        fixture.tabManager.spaceStateOwner.replaceSpaces([replacement])
        fixture.tabManager.spaceStateOwner.replaceCurrentSpace(replacement)
        XCTAssertFalse(try XCTUnwrap(transition.stagedModelIsExact)())

        try XCTUnwrap(transition.rollbackModel)()

        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertEqual(replacement.profileId, fixture.targetProfile.id)
        XCTAssertIdentical(
            fixture.tabManager.spaceStateOwner.currentSpace,
            replacement
        )
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
    }

    func testRollbackRestoresRemovedExactTabWitness() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        try stageProfileChange(fixture, transition: transition)

        fixture.tabManager.tabStateStore.regularTabs.replaceTabsBySpace([:])
        fixture.tabManager.structuralLookupCoordinator.rebuild()
        XCTAssertFalse(try XCTUnwrap(transition.stagedModelIsExact)())

        try XCTUnwrap(transition.rollbackModel)()

        XCTAssertTrue(
            fixture.tabManager.tabStateStore.regularTabs.allTabs().isEmpty
        )
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
    }

    func testRollbackDoesNotRebindToSameIDTabReplacement() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        try stageProfileChange(fixture, transition: transition)
        let replacement = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        replacement.profileId = fixture.targetProfile.id

        fixture.tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            fixture.space.id: [replacement],
        ])
        fixture.tabManager.structuralLookupCoordinator.rebuild()
        XCTAssertFalse(try XCTUnwrap(transition.stagedModelIsExact)())

        try XCTUnwrap(transition.rollbackModel)()

        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(replacement.profileId, fixture.targetProfile.id)
        XCTAssertFalse(replacement.profileAssignment.hasUnsettledAssignment)
        XCTAssertIdentical(
            fixture.tabManager.tabStateStore.regularTabs
                .tab(for: replacement.id),
            replacement
        )
    }

    func testPendingSameIDReplacementRejectsAndAbortsExactTabWitness()
        throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        let replacement = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        replacement.profileId = fixture.targetProfile.id
        fixture.tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            fixture.space.id: [replacement],
        ])
        fixture.tabManager.structuralLookupCoordinator.rebuild()

        XCTAssertFalse(try XCTUnwrap(transition.validateModel)())
        try XCTUnwrap(transition.settlement)(.rejected(.stale))

        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertFalse(replacement.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(replacement.profileId, fixture.targetProfile.id)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
    }

    func testTerminalDrainFinishesExactWitnessesAfterSameIDReplacement()
        throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        try stageProfileChange(fixture, transition: transition)
        let spaceReplacement = Space(
            id: fixture.space.id,
            name: "Replacement",
            profileId: fixture.sourceProfile.id
        )
        let tabReplacement = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        tabReplacement.profileId = fixture.sourceProfile.id
        fixture.tabManager.spaceStateOwner.replaceSpaces([spaceReplacement])
        fixture.tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            fixture.space.id: [tabReplacement],
        ])
        fixture.tabManager.structuralLookupCoordinator.rebuild()

        try XCTUnwrap(transition.settlement)(.terminalShutdown)

        XCTAssertEqual(fixture.space.profileId, fixture.targetProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertEqual(spaceReplacement.profileId, fixture.sourceProfile.id)
        XCTAssertEqual(tabReplacement.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(tabReplacement.profileAssignment.hasUnsettledAssignment)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
    }

    func testDuplicateCandidateIDIsRejectedBeforeIntentCreation() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        let duplicate = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        fixture.tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            fixture.space.id: [fixture.regularTab, duplicate],
        ])
        fixture.tabManager.structuralLookupCoordinator.rebuild()

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .failed
        )

        XCTAssertEqual(transition.assignmentCount, 0)
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertFalse(duplicate.profileAssignment.hasUnsettledAssignment)
    }

    func testAuxiliarySameIDCollisionIsRejectedBeforeIntentCreation() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        let auxiliary = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        fixture.tabManager.tabCollectionMembershipOwner
            .registerAuxiliaryMiniWindowTab(auxiliary)

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .failed
        )

        XCTAssertEqual(transition.assignmentCount, 0)
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertFalse(auxiliary.profileAssignment.hasUnsettledAssignment)
    }

    func testUniqueAuxiliaryTabIsNotAProfileAssignmentCandidate() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        let auxiliary = fixture.tabManager.tabFactory.makeTab(
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        fixture.tabManager.tabCollectionMembershipOwner
            .registerAuxiliaryMiniWindowTab(auxiliary)

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )

        let exactTabs = try XCTUnwrap(transition.exactTabs)
        XCTAssertEqual(exactTabs.count, 1)
        XCTAssertIdentical(exactTabs.first, fixture.regularTab)
        XCTAssertFalse(auxiliary.profileAssignment.hasUnsettledAssignment)
        try XCTUnwrap(transition.settlement)(.rejected(.stale))
    }

    func testRuntimeBoundaryReceivesExactTransactionTabWitness() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )

        let exactTabs = try XCTUnwrap(transition.exactTabs)
        XCTAssertEqual(exactTabs.count, 1)
        XCTAssertIdentical(exactTabs.first, fixture.regularTab)
        try XCTUnwrap(transition.settlement)(.rejected(.stale))
    }

    func testCreationFollowerRejectsDetachedSameIDTab() throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 0
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        let detached = fixture.tabManager.tabFactory.makeTab(
            id: fixture.regularTab.id,
            spaceId: fixture.space.id,
            loadsCachedFaviconOnInit: false
        )
        detached.profileId = fixture.targetProfile.id

        XCTAssertFalse(
            fixture.spaceProfiles.lifecycle
                .registerCreationFollower(
                    detached,
                    in: fixture.space.id,
                    profileID: fixture.targetProfile.id
                )
        )
        try XCTUnwrap(transition.settlement)(.rejected(.stale))
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasUnsettledAssignment)
        XCTAssertFalse(detached.profileAssignment.hasUnsettledAssignment)
    }

    func testDuplicateRetirementInputIsRejectedBeforeAnyTransactionMutation()
        throws {
        let repository = WebViewSessionRepository()
        let tabManager = try makeBrowser(webViewSessions: repository)
        let runtimeTeardown = makeRuntimeTeardown(for: tabManager)
        let webView = WKWebView()
        let tab = tabManager.tabFactory.makeTab(
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        let duplicateIdentity = tabManager.tabFactory.makeTab(
            id: tab.id,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        XCTAssertIdentical(tab.webViewSession.parkedWebView, webView)
        let generation = tab.webViewSession.generation
        let identityRegistry = WebViewRuntimeTabRegistry(
            webViewSessions: repository
        )
        XCTAssertEqual(identityRegistry.bind(tab), .bound)
        var capabilityCalls = 0
        let transition = DeferredSpaceProfileTransition(
            canRetireTabWebViews: { _ in
                capabilityCalls += 1
                return true
            },
            beginCommittedTabRetirement: { _ in
                capabilityCalls += 1
                return true
            },
            destroyRetiredWebViews: { _ in capabilityCalls += 1 },
            destroyAfterTerminalDrain: { _, _ in capabilityCalls += 1 }
        )
        let runtime = TestRuntimePorts.make(
            webViewLifecycle: transition.makeLifecycle()
        )

        func assertRejected(_ candidates: [Tab]) {
            var modelCalls = 0
            let receipt = WebViewRetirementModelTransactionReceipt(
                isCurrent: {
                    modelCalls += 1
                    return true
                },
                commit: {
                    modelCalls += 1
                    return true
                },
                rollback: {
                    modelCalls += 1
                    return true
                }
            )
            guard case .rejected(let reason) = runtimeTeardown
                .retirement.begin(
                    tabs: candidates,
                    using: runtime,
                    modelTransaction: receipt
                ) else {
                return XCTFail("Duplicate retirement input must be rejected")
            }
            XCTAssertEqual(reason, .invalid(tabID: tab.id))
            XCTAssertEqual(modelCalls, 0)
            XCTAssertEqual(capabilityCalls, 0)
            XCTAssertEqual(tab.webViewSession.generation, generation)
            XCTAssertIdentical(tab.webViewSession.parkedWebView, webView)
            XCTAssertEqual(repository.residence(of: webView), .parked(tabID: tab.id))
            XCTAssertFalse(identityRegistry.isRetiring(tab))
            XCTAssertIdentical(identityRegistry.boundTab(tab.id), tab)
            XCTAssertEqual(identityRegistry.bind(tab), .alreadyBound)
        }

        assertRejected([tab, tab])
        assertRejected([tab, duplicateIdentity])
    }

}
