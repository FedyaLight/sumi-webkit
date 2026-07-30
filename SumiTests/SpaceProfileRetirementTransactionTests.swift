import Combine
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SpaceProfileRetirementTransactionTests: XCTestCase {
    func testCommitSealsWholeModelBeforePublishingPhysicalTeardown()
        throws {
        var events: [String] = []
        var runtimeIdentityWasSealed = false
        var terminalModelWasFinished = false
        var terminalProbe: (() -> Void)?
        let transition = DeferredSpaceProfileTransition(
            beginCommittedTabRetirement: { tabs in
                XCTAssertEqual(tabs.count, 2)
                runtimeIdentityWasSealed = true
                return true
            },
            destroyRetiredWebViews: { generations in
                terminalProbe?()
                events.append(contentsOf: generations.map {
                    "destroy:\($0.tabID.uuidString)"
                })
            },
            unloadTab: { tab in
                events.append("teardown:\(tab.id.uuidString)")
            }
        )
        let fixture = try makeFixture(transition: transition, retirementCount: 2)
        terminalProbe = {
            terminalModelWasFinished = runtimeIdentityWasSealed
                && fixture.space.profileId
                == fixture.targetProfile.id
                && fixture.regularTab.profileAssignment.hasStagedSettlement
                    == false
                && fixture.retiredTabs.allSatisfy {
                    fixture.tabManager.liveShortcutTabs
                        .entry(containing: $0) == nil
                }
        }

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertTrue(fixture.regularTab.profileAssignment.hasStagedSettlement)

        XCTAssertTrue(try XCTUnwrap(transition.stagedModelIsExact)())
        XCTAssertTrue(try XCTUnwrap(transition.canSealModel)())
        XCTAssertEqual(try XCTUnwrap(transition.sealModel)(), .sealed)

        XCTAssertTrue(runtimeIdentityWasSealed)
        XCTAssertEqual(fixture.space.profileId, fixture.targetProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertTrue(fixture.retiredTabs.allSatisfy {
            fixture.tabManager.liveShortcutTabs.entry(containing: $0) == nil
        })
        XCTAssertTrue(events.isEmpty)

        try XCTUnwrap(transition.publishCommit)()

        XCTAssertTrue(terminalModelWasFinished)
        let orderedIDs = fixture.retiredTabs.map(\.id).sorted {
            $0.uuidString < $1.uuidString
        }
        XCTAssertEqual(
            Array(events.prefix(orderedIDs.count)),
            orderedIDs.map { "teardown:\($0.uuidString)" }
        )
        XCTAssertEqual(
            Array(events.dropFirst(orderedIDs.count)),
            orderedIDs.map { "destroy:\($0.uuidString)" }
        )
        XCTAssertTrue(fixture.retiredTabs.allSatisfy {
            $0.webViewSession.allKnownWebViews.isEmpty
        })
    }

    func testTerminalLeaseLossBeforeBatchPublicationClaimsRetirementDrain()
        throws {
        var normalDestroyCount = 0
        var terminalDestroyCount = 0
        var normalTeardownCount = 0
        let transition = DeferredSpaceProfileTransition(
            destroyRetiredWebViews: { generations in
                normalDestroyCount += generations.count
            },
            destroyAfterTerminalDrain: { generations, _ in
                terminalDestroyCount += generations.count
            },
            unloadTab: { _ in normalTeardownCount += 1 }
        )
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 1
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        let finishModel = try XCTUnwrap(transition.finishModel)

        fixture.tabManager.structuralLookupCoordinator.withTransaction {
            finishModel()
            XCTAssertEqual(fixture.space.profileId, fixture.targetProfile.id)
            XCTAssertFalse(
                fixture.regularTab.profileAssignment.hasStagedSettlement
            )
            XCTAssertTrue(fixture.runtimeAttachment.detach())
        }

        XCTAssertEqual(terminalDestroyCount, 1)
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(normalTeardownCount, 0)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
    }

    func testOuterDetachOwnsClaimAcrossReentrantTerminalDrainCallback()
        throws {
        let profileID = UUID()
        let profile = Profile(id: profileID, name: "Default")
        let tabManager = BrowserManager()
        tabManager.tabRuntimeLifecycle.shutdown()
        let spaceProfiles = makeSpaceProfileHarness(for: tabManager)
        let runtimeAttachment = spaceProfiles.runtimeAttachment
        let space = Space(name: "Current", profileId: nil)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let replacement = TestRuntimePorts.make()
        var model: (any SpaceProfileWebViewReplacementTransaction)?
        var reentrantDetachResult: Bool?
        var reentrantAttachOutcome: TabRuntimePortsAttachmentOwner.Outcome?
        var terminalDrainCallbackCount = 0
        let transitions = TestTabWebViewProfileTransitionParticipant(
            executeTab: { tab, _, intent, _ in
                tab.profileAssignment.commit(intent) ? .committed : .stale
            },
            executeSpace: { _, _, _, received, _ in
                model = received
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
            runtimeAttachment.attach(runtime),
            .attached
        )
        let exactModel = try XCTUnwrap(model)
        XCTAssertTrue(exactModel.validateForStaging())
        try exactModel.stage()
        let availability = spaceProfiles.availability
        let observation = try XCTUnwrap(availability.observeNext(
            after: availability.revision
        ) {
            terminalDrainCallbackCount += 1
            reentrantDetachResult = runtimeAttachment.detach()
            reentrantAttachOutcome = runtimeAttachment.attach(replacement)
        })

        let outerDetachResult = runtimeAttachment.detach()

        XCTAssertTrue(outerDetachResult)
        XCTAssertEqual(terminalDrainCallbackCount, 1)
        XCTAssertEqual(reentrantDetachResult, false)
        XCTAssertEqual(reentrantAttachOutcome, .busy)
        XCTAssertNil(tabManager.runtimePortConnection.current)
        XCTAssertTrue(runtimeAttachment.canAttach)
        observation.cancel()
        XCTAssertEqual(
            runtimeAttachment.attach(replacement),
            .attached
        )
        XCTAssertNotNil(tabManager.runtimePortConnection.current)
        XCTAssertTrue(runtimeAttachment.detach())
    }

    func testReentrantTerminalDrainPreservesExactSameSpaceReplacement()
        throws {
        var fixture: SpaceProfileRetirementFixture!
        var firstIntent: DeferredWebViewSpaceProfileAssignmentIntent?
        var terminalDrainCallbackCount = 0
        var nestedDrainResult: RuntimeDetachDrainResult?
        var replacementOutcome: TabProfileAssignmentExecutionOutcome?
        let transition = DeferredSpaceProfileTransition(
            destroyAfterTerminalDrain: { _, _ in
                terminalDrainCallbackCount += 1
                guard terminalDrainCallbackCount == 1,
                      let firstIntent else { return }
                nestedDrainResult = fixture.spaceProfiles.lifecycle
                    .drainForRuntimeDetach(firstIntent)
                replacementOutcome = fixture.spaceProfiles.service.start(
                        spaceID: fixture.space.id,
                        profileID: fixture.sourceProfile.id
                    )
            }
        )
        fixture = try makeFixture(
            transition: transition,
            retirementCount: 1
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        firstIntent = try XCTUnwrap(transition.intent)
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertTrue(try XCTUnwrap(transition.canSealModel)())
        XCTAssertEqual(try XCTUnwrap(transition.sealModel)(), .sealed)
        let exactFirstIntent = try XCTUnwrap(firstIntent)

        let outerDrainResult = fixture.spaceProfiles.lifecycle
            .drainForRuntimeDetach(exactFirstIntent)

        guard case .drained = outerDrainResult else {
            return XCTFail("Outer drain must retain the exact first intent")
        }
        guard case .drained? = nestedDrainResult else {
            return XCTFail("Nested drain must remove the exact first intent")
        }
        XCTAssertEqual(terminalDrainCallbackCount, 1)
        XCTAssertEqual(replacementOutcome, .deferred)
        let replacementIntent = try XCTUnwrap(transition.intent)
        XCTAssertNotEqual(replacementIntent, exactFirstIntent)
        XCTAssertFalse(
            fixture.spaceProfiles.lifecycle
                .isCurrent(exactFirstIntent)
        )
        XCTAssertTrue(
            fixture.spaceProfiles.lifecycle
                .isCurrent(replacementIntent)
        )
        XCTAssertEqual(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            ),
            fixture.sourceProfile.id
        )
        XCTAssertTrue(try XCTUnwrap(transition.validateModel)())
        fixture.spaceProfiles.lifecycle
            .cancelPending(replacementIntent)
    }

    func testLifecycleCommitRejectionRetainsCleanupUntilTerminalDrain()
        throws {
        var normalDestroyCount = 0
        var terminalDestroyCount = 0
        var unloadCount = 0
        let transition = DeferredSpaceProfileTransition(
            beginCommittedTabRetirement: { _ in false },
            destroyRetiredWebViews: { generations in
                normalDestroyCount += generations.count
            },
            destroyAfterTerminalDrain: { generations, _ in
                terminalDestroyCount += generations.count
            },
            unloadTab: { _ in unloadCount += 1 }
        )
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 1
        )

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertEqual(
            try XCTUnwrap(transition.sealModel)(),
            .terminallyDrained
        )
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(terminalDestroyCount, 0)
        XCTAssertEqual(unloadCount, 0)

        try XCTUnwrap(transition.settleTerminalModel)()

        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(terminalDestroyCount, 1)
        XCTAssertEqual(unloadCount, 0)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
    }

    func testLifecycleRuntimeRevocationUsesTerminalCleanupExactlyOnce()
        throws {
        var expectedWebView: WKWebView?
        var normalDestroyCount = 0
        var terminalDestroyCount = 0
        var normalTeardownCount = 0
        var lifecycleCount = 0
        let transition = DeferredSpaceProfileTransition(
            destroyRetiredWebViews: { generations in
                normalDestroyCount += generations.count
            },
            destroyAfterTerminalDrain: { generations, tabs in
                terminalDestroyCount += generations.count
                XCTAssertEqual(generations.count, 1)
                XCTAssertEqual(tabs.count, 1)
                XCTAssertEqual(generations.first?.tabID, tabs.first?.id)
                XCTAssertIdentical(
                    generations.first?.snapshot.parkedWebView,
                    expectedWebView
                )
            },
            unloadTab: { _ in normalTeardownCount += 1 }
        )
        let fixture = try makeFixture(
            transition: transition,
            retirementCount: 1
        )
        let retiredTab = try XCTUnwrap(fixture.retiredTabs.first)
        expectedWebView = try XCTUnwrap(retiredTab.webViewSession.parkedWebView)
        let lifecycle = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: retiredTab,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                lifecycleCount += 1
                XCTAssertTrue(fixture.runtimeAttachment.detach())
                transition.settlement?(.terminalShutdown)
                transition.settlement?(.terminalShutdown)
            }
        }
        defer { NotificationCenter.default.removeObserver(lifecycle) }

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        XCTAssertTrue(try XCTUnwrap(transition.stagedModelIsExact)())
        XCTAssertTrue(try XCTUnwrap(transition.canSealModel)())
        XCTAssertEqual(try XCTUnwrap(transition.sealModel)(), .sealed)

        try XCTUnwrap(transition.publishCommit)()
        transition.publishCommit?()

        XCTAssertEqual(lifecycleCount, 1)
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(terminalDestroyCount, 1)
        XCTAssertEqual(normalTeardownCount, 0)
        XCTAssertTrue(retiredTab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
    }

    func testRollbackPublishesRestoredModelOnlyAfterWebViewsLeaveQuarantine()
        throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(transition: transition, retirementCount: 1)
        let retiredTab = try XCTUnwrap(fixture.retiredTabs.first)
        let retiredWebView = try XCTUnwrap(
            retiredTab.webViewSession.allKnownWebViews.first
        )
        var outerReplacementWasRestored = false
        var observerRanBeforeOuterRestore = false
        var restoredModelCallbackCount = 0
        var restoredRegistryEventCount = 0
        let cancellable = fixture.tabManager.objectWillChange.sink {
            guard fixture.tabManager.liveShortcutTabs
                .entry(containing: retiredTab) != nil else { return }
            restoredModelCallbackCount += 1
            let innerRetirementIsQuarantined: Bool
            if case .retiring = fixture.repository.residence(
                of: retiredWebView
            ) {
                innerRetirementIsQuarantined = true
            } else {
                innerRetirementIsQuarantined = false
            }
            if outerReplacementWasRestored == false
                || innerRetirementIsQuarantined {
                observerRanBeforeOuterRestore = true
            }
        }
        let registryCancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                guard fixture.tabManager.liveShortcutTabs
                    .entry(containing: retiredTab) != nil else { return }
                restoredRegistryEventCount += 1
                if outerReplacementWasRestored == false
                    || fixture.repository.residence(of: retiredWebView)
                    != .parked(tabID: retiredTab.id) {
                    observerRanBeforeOuterRestore = true
                }
            }

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        guard case .retiring = fixture.repository.residence(of: retiredWebView)
        else { return XCTFail("Staged retirement must quarantine its WebView") }

        try XCTUnwrap(transition.rollbackModel)()
        XCTAssertEqual(restoredModelCallbackCount, 0)
        XCTAssertEqual(restoredRegistryEventCount, 0)
        outerReplacementWasRestored = true
        try XCTUnwrap(transition.rollbackModelPublication)()
        withExtendedLifetime((cancellable, registryCancellable)) {}

        XCTAssertGreaterThan(restoredModelCallbackCount, 0)
        XCTAssertGreaterThan(restoredRegistryEventCount, 0)
        XCTAssertFalse(observerRanBeforeOuterRestore)
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertNotNil(
            fixture.tabManager.liveShortcutTabs.entry(containing: retiredTab)
        )
        XCTAssertEqual(
            fixture.repository.residence(of: retiredWebView),
            .parked(tabID: retiredTab.id)
        )
    }

    func testRuntimeTerminationBeforeFinalBindingRollsBackBothExactLeases()
        throws {
        var runtimeTabs: WebViewRuntimeTabRegistry?
        var committedRetirementCount = 0
        let transition = DeferredSpaceProfileTransition(
            canRetireTabWebViews: { tabs in
                guard let runtimeTabs else { return false }
                return tabs.allSatisfy { runtimeTabs.bind($0).isAccepted }
            },
            beginCommittedTabRetirement: { tabs in
                committedRetirementCount += 1
                guard let runtimeTabs else { return false }
                return tabs.allSatisfy(runtimeTabs.beginRetirement)
            }
        )
        let fixture = try makeFixture(transition: transition, retirementCount: 1)
        let identityRegistry = WebViewRuntimeTabRegistry(
            webViewSessions: fixture.repository
        )
        runtimeTabs = identityRegistry
        let retiredTab = try XCTUnwrap(fixture.retiredTabs.first)
        let previousOuterWebView = try XCTUnwrap(
            fixture.regularTab.webViewSession.parkedWebView
        )
        let innerRetiredWebView = try XCTUnwrap(
            retiredTab.webViewSession.parkedWebView
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )

        let outerSnapshot = fixture.repository.snapshot(
            for: fixture.regularTab.id
        )
        let replacement = WKWebView()
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: fixture.regularTab,
            snapshot: outerSnapshot,
            placement: .detached(webView: replacement, residence: .parked),
            replacements: [replacement],
            trackedReplacements: [],
            bindingReplacements: [replacement],
            targetURL: fixture.regularTab.url,
            semanticRevision: 0,
            profileID: fixture.targetProfile.id,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: nil
        ))
        let destroyer = WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: fixture.repository,
            retireNavigationGeneration: { _, _, _ in },
            destroy: { _, _ in },
            uninstallObservationsIfUntracked: { _ in }
        ))
        let pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: fixture.repository,
            quiesce: { _ in },
            retiredGenerationDestroyer: destroyer,
            restore: { _, _ in }
        ))
        var completion: WebViewReplacementTransactionOutcome?
        let start = pipeline.begin(
            [prepared],
            profileIDs: [fixture.targetProfile.id],
            model: replacementModel(for: transition),
            completion: { completion = $0 }
        )
        guard case .started(let receipt) = start,
              let token = receipt.bindingToken(for: replacement) else {
            return XCTFail("Expected an outer replacement binding lease")
        }
        guard case .retiring = fixture.repository.residence(
            of: previousOuterWebView
        ), case .retiring = fixture.repository.residence(
            of: innerRetiredWebView
        ) else { return XCTFail("Both predecessor generations must be leased") }

        identityRegistry.resetForTerminalShutdown()
        let lifetime = NSObject()
        XCTAssertEqual(
            pipeline.markBound(
                token,
                binding: WebViewReplacementNavigationBinding(
                    webView: replacement,
                    semanticRevision: 0,
                    navigationID: ObjectIdentifier(lifetime),
                    navigationLifetime: lifetime
                )
            ),
            .rolledBack(.commitValidationFailed)
        )

        XCTAssertEqual(completion, .rolledBack(.commitValidationFailed))
        XCTAssertEqual(committedRetirementCount, 0)
        XCTAssertEqual(fixture.space.profileId, fixture.sourceProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertNotNil(
            fixture.tabManager.liveShortcutTabs.entry(containing: retiredTab)
        )
        XCTAssertEqual(
            fixture.repository.residence(of: previousOuterWebView),
            .parked(tabID: fixture.regularTab.id)
        )
        XCTAssertEqual(
            fixture.repository.residence(of: innerRetiredWebView),
            .parked(tabID: retiredTab.id)
        )
        XCTAssertNil(fixture.repository.residence(of: replacement))
    }

    func testStagedSpaceModelDriftBeforeFinalBindingStaysQuarantined()
        throws {
        var committedRetirementCount = 0
        let transition = DeferredSpaceProfileTransition(
            beginCommittedTabRetirement: { _ in
                committedRetirementCount += 1
                return true
            }
        )
        let fixture = try makeFixture(transition: transition, retirementCount: 1)
        let retiredWebView = try XCTUnwrap(
            fixture.retiredTabs.first?.webViewSession.parkedWebView
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        let harness = try makeOuterReplacementHarness(fixture)
        var completion: WebViewReplacementTransactionOutcome?
        let start = harness.pipeline.begin(
            [harness.prepared],
            profileIDs: [fixture.targetProfile.id],
            model: replacementModel(for: transition),
            completion: { completion = $0 }
        )
        guard case .started(let receipt) = start,
              let token = receipt.bindingToken(for: harness.replacement) else {
            return XCTFail("Expected an outer replacement binding lease")
        }
        XCTAssertTrue(fixture.tabManager.spaceStateOwner
            .assignProfileWithoutObservation(
                spaceId: fixture.space.id,
                profileId: fixture.sourceProfile.id
            ))
        XCTAssertFalse(try XCTUnwrap(transition.stagedModelIsExact)())

        let lifetime = NSObject()
        XCTAssertEqual(
            harness.pipeline.markBound(
                token,
                binding: WebViewReplacementNavigationBinding(
                    webView: harness.replacement,
                    semanticRevision: 0,
                    navigationID: ObjectIdentifier(lifetime),
                    navigationLifetime: lifetime
                )
            ),
            .conflicted
        )

        XCTAssertEqual(completion, .conflicted)
        XCTAssertEqual(committedRetirementCount, 0)
        guard case .retiring = fixture.repository.residence(
            of: harness.previous
        ), case .retiring = fixture.repository.residence(
            of: retiredWebView
        ) else { return XCTFail("Model conflict must retain both exact leases") }
        XCTAssertIdentical(
            fixture.repository.parkedWebView(for: fixture.regularTab.id),
            harness.replacement
        )
        harness.pipeline.resetForTerminalShutdown()
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
        _ = fixture.repository.takeAllWebViewsForTerminalShutdown()
    }

    func testReentrantTerminalDrainAfterForwardPublicationCannotCommit()
        throws {
        let transition = DeferredSpaceProfileTransition()
        let fixture = try makeFixture(transition: transition, retirementCount: 1)
        let previousOuterWebView = try XCTUnwrap(
            fixture.regularTab.webViewSession.parkedWebView
        )
        let innerRetiredWebView = try XCTUnwrap(
            fixture.retiredTabs.first?.webViewSession.parkedWebView
        )
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        let outerSnapshot = fixture.repository.snapshot(
            for: fixture.regularTab.id
        )
        let replacement = WKWebView()
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: fixture.regularTab,
            snapshot: outerSnapshot,
            placement: .detached(webView: replacement, residence: .parked),
            replacements: [replacement],
            trackedReplacements: [],
            bindingReplacements: [replacement],
            targetURL: fixture.regularTab.url,
            semanticRevision: 0,
            profileID: fixture.targetProfile.id,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: nil
        ))
        let destroyer = WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: fixture.repository,
            retireNavigationGeneration: { _, _, _ in },
            destroy: { _, _ in },
            uninstallObservationsIfUntracked: { _ in }
        ))
        let pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: fixture.repository,
            quiesce: { _ in },
            retiredGenerationDestroyer: destroyer,
            restore: { _, _ in }
        ))
        var publicationCount = 0
        var publicationSawCompleteOuterPlacement = false
        var drained: [WebViewTerminalCleanupEntry] = []
        let publicationObserver = fixture.tabManager.objectWillChange.sink {
            guard fixture.space.profileId == fixture.targetProfile.id,
                  drained.isEmpty else {
                return
            }
            publicationCount += 1
            let current = fixture.repository.snapshot(
                for: fixture.regularTab.id
            )
            XCTAssertIdentical(current.parkedWebView, replacement)
            guard case .retiring = fixture.repository.residence(
                of: previousOuterWebView
            ) else {
                return XCTFail("Outer predecessor must be quarantined")
            }
            guard case .retiring = fixture.repository.residence(
                of: innerRetiredWebView
            ) else {
                return XCTFail("Inner retirement must already own its WebView")
            }
            publicationSawCompleteOuterPlacement = true
            drained = fixture.repository.takeAllWebViewsForTerminalShutdown()
        }
        var completionWasCalled = false
        let start = pipeline.begin(
            [prepared],
            profileIDs: [fixture.targetProfile.id],
            model: replacementModel(for: transition),
            completion: { _ in
                completionWasCalled = true
            }
        )

        XCTAssertGreaterThan(publicationCount, 0)
        XCTAssertTrue(publicationSawCompleteOuterPlacement)
        guard case .leaseLost = start else {
            return XCTFail("Reentrant terminal drain must reject outer lease")
        }
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            Set(
                [previousOuterWebView, replacement, innerRetiredWebView]
                    .map(ObjectIdentifier.init)
            )
        )
        XCTAssertFalse(completionWasCalled)
        try XCTUnwrap(transition.settlement)(.leaseLost)
        withExtendedLifetime(publicationObserver) {}

        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
        XCTAssertEqual(fixture.space.profileId, fixture.targetProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertNil(
            fixture.tabManager.liveShortcutTabs.entry(
                containing: try XCTUnwrap(fixture.retiredTabs.first)
            )
        )
        XCTAssertTrue(
            fixture.repository.snapshot(for: fixture.regularTab.id)
                .allKnownWebViews.isEmpty
        )
    }

    func testTerminalResetDuringOuterRetirementDrainsSealedInnerGeneration()
        throws {
        var runtimeTabs: WebViewRuntimeTabRegistry!
        var terminalDestroyer: WebViewRetiredGenerationDestroyer!
        var normalInnerDestroyCount = 0
        var normalTeardownCount = 0
        var terminalTabs: [Tab] = []
        let transition = DeferredSpaceProfileTransition(
            canRetireTabWebViews: { tabs in
                tabs.allSatisfy { runtimeTabs.bind($0).isAccepted }
            },
            beginCommittedTabRetirement: { tabs in
                tabs.allSatisfy(runtimeTabs.beginRetirement)
            },
            destroyRetiredWebViews: { _ in normalInnerDestroyCount += 1 },
            destroyAfterTerminalDrain: { generations, tabs in
                terminalTabs = tabs
                XCTAssertEqual(
                    Set(generations.map(\.tabID)),
                    Set(tabs.map(\.id))
                )
                terminalDestroyer.destroy(generations)
            },
            unloadTab: { _ in normalTeardownCount += 1 }
        )
        let fixture = try makeFixture(transition: transition, retirementCount: 1)
        runtimeTabs = WebViewRuntimeTabRegistry(
            webViewSessions: fixture.repository
        )
        let retiredTab = try XCTUnwrap(fixture.retiredTabs.first)
        let innerWebView = try XCTUnwrap(retiredTab.webViewSession.parkedWebView)
        var terminallyDestroyed: [ObjectIdentifier] = []
        terminalDestroyer = WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: fixture.repository,
            retireNavigationGeneration: { _, _, _ in },
            destroy: { _, webView in
                terminallyDestroyed.append(ObjectIdentifier(webView))
            },
            uninstallObservationsIfUntracked: { _ in }
        ))

        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        let outer = try makeOuterReplacementHarness(fixture)
        var pipeline: WebViewReplacementPipeline!
        var didReset = false
        var outerDestroyed: [ObjectIdentifier] = []
        var repositoryDrain: [WebViewTerminalCleanupEntry] = []
        let outerDestroyer = WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: fixture.repository,
            retireNavigationGeneration: { _, _, _ in },
            destroy: { _, webView in
                outerDestroyed.append(ObjectIdentifier(webView))
                guard didReset == false else { return }
                didReset = true
                runtimeTabs.resetForTerminalShutdown()
                repositoryDrain = fixture.repository
                    .takeAllWebViewsForTerminalShutdown()
                pipeline.resetForTerminalShutdown()
            },
            uninstallObservationsIfUntracked: { _ in }
        ))
        pipeline = WebViewReplacementPipeline(runtime: .init(
            webViewSessions: fixture.repository,
            quiesce: { _ in },
            retiredGenerationDestroyer: outerDestroyer,
            restore: { _, _ in }
        ))
        var completions: [WebViewReplacementTransactionOutcome] = []
        let start = pipeline.begin(
            [outer.prepared],
            profileIDs: [fixture.targetProfile.id],
            model: replacementModel(for: transition),
            completion: { outcome in
                completions.append(outcome)
                guard outcome == .abandonedForTerminalShutdown else { return }
                guard let settlement = transition.settlement else {
                    return XCTFail("Space settlement callback was not retained")
                }
                settlement(.terminalShutdown)
            }
        )
        guard case .started(let receipt) = start,
              let token = receipt.bindingToken(for: outer.replacement) else {
            return XCTFail("Expected an outer replacement binding lease")
        }
        var structuralEventsAfterStage = 0
        let structuralObserver = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { _ in
                structuralEventsAfterStage += 1
            }
        let lifetime = NSObject()

        XCTAssertEqual(
            pipeline.markBound(
                token,
                binding: WebViewReplacementNavigationBinding(
                    webView: outer.replacement,
                    semanticRevision: 0,
                    navigationID: ObjectIdentifier(lifetime),
                    navigationLifetime: lifetime
                )
            ),
            .leaseLost
        )
        withExtendedLifetime(structuralObserver) {}

        XCTAssertEqual(completions, [.abandonedForTerminalShutdown])
        XCTAssertEqual(outerDestroyed, [ObjectIdentifier(outer.previous)])
        XCTAssertEqual(terminallyDestroyed, [ObjectIdentifier(innerWebView)])
        XCTAssertEqual(
            repositoryDrain.map { ObjectIdentifier($0.webView) },
            [ObjectIdentifier(outer.replacement)]
        )
        XCTAssertEqual(terminalTabs.count, 1)
        XCTAssertIdentical(terminalTabs.first, retiredTab)
        XCTAssertEqual(normalInnerDestroyCount, 0)
        XCTAssertEqual(normalTeardownCount, 0)
        XCTAssertEqual(structuralEventsAfterStage, 0)
        XCTAssertNil(
            fixture.spaceProfiles.lifecycle.inFlightProfileID(
                for: fixture.space.id
            )
        )
        XCTAssertEqual(fixture.space.profileId, fixture.targetProfile.id)
        XCTAssertFalse(fixture.regularTab.profileAssignment.hasStagedSettlement)
        XCTAssertEqual(runtimeTabs.bind(retiredTab), .runtimeTerminated)
    }

    func stageProfileChange(
        _ fixture: SpaceProfileRetirementFixture,
        transition: DeferredSpaceProfileTransition
    ) throws {
        XCTAssertEqual(
            fixture.spaceProfiles.service.start(
                spaceID: fixture.space.id,
                profileID: fixture.targetProfile.id
            ),
            .deferred
        )
        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
    }

    func makeFixture(
        transition: DeferredSpaceProfileTransition,
        retirementCount: Int
    ) throws -> SpaceProfileRetirementFixture {
        let sourceProfile = Profile(name: "Source")
        let targetProfile = Profile(name: "Target")
        let profiles = [
            sourceProfile.id: sourceProfile,
            targetProfile.id: targetProfile,
        ]
        let repository = WebViewSessionRepository()
        let container = try makeInMemoryStartupDatabase()
        let windowID = UUID()
        let windowState = BrowserWindowState(id: windowID)
        let tabManager = BrowserManager(
            webViewSessions: repository,
            windowRegistry: WindowRegistry(),
            startupPersistence: BrowserManagerStartupPersistence(database: container
            ),
            dataServices: .unavailable()
        )
        tabManager.tabRuntimeLifecycle.shutdown()
        let spaceProfiles = makeSpaceProfileHarness(for: tabManager)
        let runtimeAttachment = spaceProfiles.runtimeAttachment
        XCTAssertEqual(
            runtimeAttachment.attach(TestRuntimePorts.make(
                currentProfileId: { targetProfile.id },
                defaultProfileId: { targetProfile.id },
                profile: { profiles[$0] },
                windowState: { id in
                    id == windowID ? windowState : nil
                },
                windows: { [(windowID, windowState)] },
                windowStates: { [windowState] },
                webViewLifecycle: transition.makeLifecycle()
            )),
            .attached
        )
        let space = Space(name: "Work", profileId: sourceProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let regularTab = tabManager.tabFactory.makeTab(
            spaceId: space.id,
            existingWebView: WKWebView(),
            loadsCachedFaviconOnInit: false
        )
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [regularTab],
        ])
        let tabIDs = [
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        ]
        let pins = tabIDs.prefix(retirementCount).enumerated().map {
            index,
            tabID in
            ShortcutPin(
                id: UUID(),
                role: .essential,
                profileId: sourceProfile.id,
                index: index,
                launchURL: URL(string: "https://retired-\(index).example")!,
                title: "Retired \(index)"
            )
        }
        tabManager.shortcutPinCollectionStateOwner.replacePinnedByProfile([
            sourceProfile.id: pins,
        ])
        var retiredTabs: [Tab] = []
        for (tabID, pin) in zip(tabIDs, pins) {
            let tab = tabManager.tabFactory.makeTab(
                id: tabID,
                url: pin.launchURL,
                existingWebView: WKWebView(),
                loadsCachedFaviconOnInit: false
            )
            tab.profileId = sourceProfile.id
            tab.bindToShortcutPin(pin)
            XCTAssertTrue(tabManager.liveShortcutTabs.register(
                tab,
                for: pin.id,
                in: windowID,
                presentationPage: LiveShortcutPresentationPageReceipt(
                    windowID: windowID,
                    spaceID: space.id,
                    profileID: sourceProfile.id
                )
            ))
            retiredTabs.append(tab)
        }
        return SpaceProfileRetirementFixture(
            repository: repository,
            tabManager: tabManager,
            spaceProfiles: spaceProfiles,
            runtimeAttachment: runtimeAttachment,
            sourceProfile: sourceProfile,
            targetProfile: targetProfile,
            space: space,
            regularTab: regularTab,
            retiredTabs: retiredTabs
        )
    }

    func makeBrowser(
        webViewSessions: WebViewSessionRepository
    ) throws -> BrowserManager {
        BrowserManager(
            webViewSessions: webViewSessions,
            windowRegistry: WindowRegistry(),
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            ),
            dataServices: .unavailable()
        )
    }

    func makeRuntimeTeardown(
        for browser: BrowserManager
    ) -> TabRuntimeTeardownService {
        TabRuntimeTeardownService(
            persistence: browser.structuralPersistence,
            membership: browser.tabCollectionMembershipOwner,
            webViewSessions: browser.webViewSessions
        )
    }

    func makeSpaceProfileHarness(
        for browser: BrowserManager
    ) -> SpaceProfileHarness {
        let runtimeTeardown = makeRuntimeTeardown(for: browser)
        let pendingInheritance = PendingTabProfileInheritance()
        let graph = SpaceProfileTransitionService.compose(
            spaces: browser.spaceStateOwner,
            pins: browser.shortcutPinCollectionStateOwner,
            registry: browser.liveShortcutTabs,
            runtimeConnection: browser.runtimePortConnection,
            runtimeTeardown: runtimeTeardown,
            structuralLookup: browser.structuralLookupCoordinator,
            membership: browser.tabCollectionMembershipOwner,
            persistence: browser.structuralPersistence,
            pendingInheritance: pendingInheritance,
            changes: browser.objectWillChange
        )
        let pendingPins = PendingShortcutPinAdopter(
            pins: browser.shortcutPinCollectionStateOwner,
            structuralMutations: browser.structuralCollectionMutationOwner,
            profileReferenceAdmission: browser.profileReferenceAdmission
        )
        let deferredWork = TabRuntimeAttachmentDeferredWorkOwner(
            connection: browser.runtimePortConnection,
            spaceProfiles: SpaceProfileReconciliationService(
                spaces: browser.spaceStateOwner,
                runtimeConnection: browser.runtimePortConnection,
                spaceTransitions: graph.service,
                transitionLifecycle: graph.lifecycle
            ),
            spaceAvailability: graph.availability,
            pendingPins: pendingPins
        )
        let attachment = TabRuntimePortsAttachmentOwner(
            connection: browser.runtimePortConnection,
            bootstrap: TabRuntimeAttachmentBootstrap(
                connection: browser.runtimePortConnection,
                membership: browser.tabCollectionMembershipOwner,
                runtimePreparation: TabRuntimePreparationOwner(
                    runtimeConnection: browser.runtimePortConnection
                ),
                selection: browser.tabStateStore.selection
            ),
            settlement: TabRuntimeAttachmentSettlement(
                connection: browser.runtimePortConnection,
                spaces: browser.spaceStateOwner,
                deferredWork: deferredWork,
                restoreStarter: nil
            )
        )
        return SpaceProfileHarness(
            service: graph.service,
            lifecycle: graph.lifecycle,
            availability: graph.availability,
            runtimeAttachment: attachment
        )
    }

    func replacementModel(
        for transition: DeferredSpaceProfileTransition
    ) -> WebViewReplacementModelParticipant {
        .transaction(TestWebViewReplacementModelTransaction(
            validate: { transition.validateModel?() == true },
            stage: {
                guard transition.stageModel?() == true else {
                    throw CocoaError(.coderInvalidValue)
                }
            },
            stagedModelIsExact: {
                transition.stagedModelIsExact?() == true
            },
            canClaimTerminalModel: {
                transition.canSealModel?() == true
            },
            claimTerminalModel: {
                transition.sealModel?() ?? .terminallyDrained
            },
            publishCommit: { transition.publishCommit?() },
            rollback: { transition.rollbackModel?() },
            publishRollback: {
                transition.rollbackModelPublication?()
            },
            settleTerminalDrain: {
                transition.settleTerminalModel?()
            }
        ))
    }

    func makeOuterReplacementHarness(
        _ fixture: SpaceProfileRetirementFixture
    ) throws -> OuterReplacementHarness {
        let previous = try XCTUnwrap(
            fixture.regularTab.webViewSession.parkedWebView
        )
        let snapshot = fixture.repository.snapshot(for: fixture.regularTab.id)
        let replacement = WKWebView()
        let prepared = try XCTUnwrap(PreparedWebViewReplacement(
            tab: fixture.regularTab,
            snapshot: snapshot,
            placement: .detached(webView: replacement, residence: .parked),
            replacements: [replacement],
            trackedReplacements: [],
            bindingReplacements: [replacement],
            targetURL: fixture.regularTab.url,
            semanticRevision: 0,
            profileID: fixture.targetProfile.id,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: nil
        ))
        let destroyer = WebViewRetiredGenerationDestroyer(runtime: .init(
            webViewSessions: fixture.repository,
            retireNavigationGeneration: { _, _, _ in },
            destroy: { _, _ in },
            uninstallObservationsIfUntracked: { _ in }
        ))
        return OuterReplacementHarness(
            pipeline: WebViewReplacementPipeline(runtime: .init(
                webViewSessions: fixture.repository,
                quiesce: { _ in },
                retiredGenerationDestroyer: destroyer,
                restore: { _, _ in }
            )),
            prepared: prepared,
            previous: previous,
            replacement: replacement
        )
    }
}

@MainActor
struct SpaceProfileRetirementFixture {
    let repository: WebViewSessionRepository
    let tabManager: BrowserManager
    let spaceProfiles: SpaceProfileHarness
    let runtimeAttachment: TabRuntimePortsAttachmentOwner
    let sourceProfile: Profile
    let targetProfile: Profile
    let space: Space
    let regularTab: Tab
    let retiredTabs: [Tab]
}

@MainActor
struct SpaceProfileHarness {
    let service: SpaceProfileTransitionService
    let lifecycle: SpaceProfileTransitionRepository
    let availability: SpaceProfileTransitionPublication
    let runtimeAttachment: TabRuntimePortsAttachmentOwner
}

@MainActor
struct OuterReplacementHarness {
    let pipeline: WebViewReplacementPipeline
    let prepared: PreparedWebViewReplacement
    let previous: WKWebView
    let replacement: WKWebView
}
