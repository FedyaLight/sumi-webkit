import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class PreparedProfileAssignmentBatchModelTransactionTests: XCTestCase {
    func testBindingClaimsBeforeProfileIntentsAreSealed() throws {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tabs = [
            makeTab(profileID: sourceProfileID),
            makeTab(profileID: sourceProfileID),
        ]
        var terminalDrainCount = 0
        let binding = TestWebViewReplacementModelTransaction(
            exactBindingTabs: tabs,
            claimTerminalModel: {
                XCTAssertTrue(tabs.allSatisfy {
                    $0.profileAssignment.hasStagedSettlement
                })
                return .terminallyDrained
            },
            settleTerminalDrain: { terminalDrainCount += 1 }
        )
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: tabs.map { tab in
                makeAssignment(
                    tab: tab,
                    sourceProfileID: sourceProfileID,
                    targetProfile: targetProfile
                )
            },
            binding: binding
        )

        try transaction.stage()
        XCTAssertEqual(transaction.claimTerminalModel(), .terminallyDrained)

        XCTAssertEqual(terminalDrainCount, 1)
        for tab in tabs {
            XCTAssertEqual(tab.profileId, targetProfile.id)
            XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
        }
    }

    func testSealedBindingClaimsAndPublishesProfilesExactlyOnce() throws {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tabs = [
            makeTab(profileID: sourceProfileID),
            makeTab(profileID: sourceProfileID),
        ]
        var bindingClaimCount = 0
        var bindingPublishCount = 0
        let binding = TestWebViewReplacementModelTransaction(
            exactBindingTabs: tabs,
            claimTerminalModel: {
                XCTAssertTrue(tabs.allSatisfy {
                    $0.profileAssignment.hasStagedSettlement
                })
                bindingClaimCount += 1
                return .sealed
            },
            publishCommit: { bindingPublishCount += 1 }
        )
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: tabs.map { tab in
                makeAssignment(
                    tab: tab,
                    sourceProfileID: sourceProfileID,
                    targetProfile: targetProfile
                )
            },
            binding: binding
        )

        try transaction.stage()
        XCTAssertEqual(transaction.claimTerminalModel(), .sealed)
        XCTAssertEqual(bindingClaimCount, 1)
        XCTAssertTrue(tabs.allSatisfy {
            $0.profileId == targetProfile.id
                && $0.profileAssignment.hasUnsettledAssignment == false
        })

        transaction.publishCommit()
        XCTAssertEqual(bindingPublishCount, 1)
    }

    func testReentrantTerminalDrainDuringBindingClaimTombstonesBatch() throws {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tab = makeTab(profileID: sourceProfileID)
        var transaction: PreparedProfileAssignmentBatchModelTransaction!
        var bindingPublishCount = 0
        let binding = TestWebViewReplacementModelTransaction(
            exactBindingTabs: [tab],
            claimTerminalModel: {
                XCTAssertTrue(transaction.settleTerminalDrain())
                return .sealed
            },
            publishCommit: { bindingPublishCount += 1 }
        )
        transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: [makeAssignment(
                tab: tab,
                sourceProfileID: sourceProfileID,
                targetProfile: targetProfile
            )],
            binding: binding
        )

        try transaction.stage()
        XCTAssertEqual(transaction.claimTerminalModel(), .terminallyDrained)

        XCTAssertEqual(bindingPublishCount, 0)
        XCTAssertEqual(tab.profileId, targetProfile.id)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
        XCTAssertTrue(transaction.settleTerminalDrain())
    }

    func testFailedClaimPreflightHasNoClaimSideEffects() throws {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tab = makeTab(profileID: sourceProfileID)
        var bindingClaimCount = 0
        let binding = TestWebViewReplacementModelTransaction(
            exactBindingTabs: [tab],
            canClaimTerminalModel: { false },
            claimTerminalModel: {
                bindingClaimCount += 1
                return .sealed
            }
        )
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: [makeAssignment(
                tab: tab,
                sourceProfileID: sourceProfileID,
                targetProfile: targetProfile
            )],
            binding: binding
        )

        try transaction.stage()
        XCTAssertFalse(transaction.canClaimTerminalModel())
        XCTAssertEqual(transaction.claimTerminalModel(), .terminallyDrained)
        XCTAssertEqual(bindingClaimCount, 0)
        XCTAssertTrue(tab.profileAssignment.hasStagedSettlement)

        try transaction.rollback()
        XCTAssertEqual(tab.profileId, sourceProfileID)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testBindingAndProfileCoverageMustBeExactAndUnique() {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let first = makeTab(profileID: sourceProfileID)
        let second = makeTab(profileID: sourceProfileID)
        let assignment = makeAssignment(
            tab: first,
            sourceProfileID: sourceProfileID,
            targetProfile: targetProfile
        )
        let cases: [([PreparedTabProfileAssignment], [Tab])] = [
            ([assignment], []),
            ([assignment], [first, second]),
            ([assignment], [first, first]),
            ([assignment, assignment], [first]),
        ]

        for (assignments, bindingTabs) in cases {
            var bindingStageCount = 0
            let transaction = PreparedProfileAssignmentBatchModelTransaction(
                assignments: assignments,
                binding: TestWebViewReplacementModelTransaction(
                    exactBindingTabs: bindingTabs,
                    stage: { bindingStageCount += 1 }
                )
            )

            XCTAssertFalse(transaction.validateForStaging())
            XCTAssertThrowsError(try transaction.stage())
            XCTAssertEqual(bindingStageCount, 0)
            XCTAssertFalse(first.profileAssignment.hasUnsettledAssignment)
            XCTAssertFalse(second.profileAssignment.hasUnsettledAssignment)
        }
    }

    func testBindingRollbackFailureStillRestoresEveryProfile() throws {
        enum ExpectedFailure: Error { case bindingRollback }

        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tabs = [
            makeTab(profileID: sourceProfileID),
            makeTab(profileID: sourceProfileID),
        ]
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: tabs.map { tab in
                makeAssignment(
                    tab: tab,
                    sourceProfileID: sourceProfileID,
                    targetProfile: targetProfile
                )
            },
            binding: TestWebViewReplacementModelTransaction(
                exactBindingTabs: tabs,
                rollback: { throw ExpectedFailure.bindingRollback }
            )
        )

        try transaction.stage()
        XCTAssertThrowsError(try transaction.rollback())
        XCTAssertTrue(transaction.retainsModelAfterFailedStage())

        for tab in tabs {
            XCTAssertEqual(tab.profileId, sourceProfileID)
            XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
        }
    }

    func testBindingStageFailureRollsBackEveryStagedProfile() {
        enum ExpectedFailure: Error { case bindingStage }

        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let first = makeTab(profileID: sourceProfileID)
        let second = makeTab(profileID: sourceProfileID)
        let assignments = [first, second].map { tab in
            makeAssignment(
                tab: tab,
                sourceProfileID: sourceProfileID,
                targetProfile: targetProfile
            )
        }
        let binding = TestWebViewReplacementModelTransaction(
            exactBindingTabs: [first, second],
            stage: { throw ExpectedFailure.bindingStage }
        )
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: assignments,
            binding: binding
        )

        XCTAssertTrue(transaction.validateForStaging())
        XCTAssertThrowsError(try transaction.stage())

        XCTAssertEqual(first.profileId, sourceProfileID)
        XCTAssertEqual(second.profileId, sourceProfileID)
        XCTAssertFalse(first.profileAssignment.hasUnsettledAssignment)
        XCTAssertFalse(second.profileAssignment.hasUnsettledAssignment)
    }

    func testRejectedAssembledTargetDoesNotAdvanceRebuildEpoch() {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tab = makeTab(profileID: sourceProfileID)
        let sourceEpoch = tab.webViewRebuildEpoch.current
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: [makeAssignment(
                tab: tab,
                sourceProfileID: sourceProfileID,
                targetProfile: targetProfile
            )],
            binding: TestWebViewReplacementModelTransaction(
                exactBindingTabs: [tab],
                stagedModelIsExact: { false }
            )
        )

        XCTAssertThrowsError(try transaction.stage())

        XCTAssertEqual(tab.webViewRebuildEpoch.current, sourceEpoch)
        XCTAssertEqual(tab.profileId, sourceProfileID)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    func testAdmittedAttemptKeepsAdvancedEpochAfterRollback() throws {
        let sourceProfileID = UUID()
        let targetProfile = Profile(name: "Target")
        let tab = makeTab(profileID: sourceProfileID)
        let sourceEpoch = tab.webViewRebuildEpoch.current
        let transaction = PreparedProfileAssignmentBatchModelTransaction(
            assignments: [makeAssignment(
                tab: tab,
                sourceProfileID: sourceProfileID,
                targetProfile: targetProfile
            )],
            binding: TestWebViewReplacementModelTransaction(
                exactBindingTabs: [tab]
            )
        )

        try transaction.stage()
        let admittedEpoch = tab.webViewRebuildEpoch.current
        XCTAssertNotEqual(admittedEpoch, sourceEpoch)

        try transaction.rollback()
        XCTAssertEqual(tab.webViewRebuildEpoch.current, admittedEpoch)
        XCTAssertEqual(tab.profileId, sourceProfileID)
        XCTAssertFalse(tab.profileAssignment.hasUnsettledAssignment)
    }

    private func makeTab(profileID: UUID) -> Tab {
        let tab = Tab(loadsCachedFaviconOnInit: false)
        tab.profileId = profileID
        return tab
    }

    private func makeAssignment(
        tab: Tab,
        sourceProfileID: UUID,
        targetProfile: Profile
    ) -> PreparedTabProfileAssignment {
        let sourceProfile = Profile(id: sourceProfileID)
        var runtime = TabBrowserRuntime.inactive
        runtime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profileID in
                if profileID == sourceProfile.id { return sourceProfile }
                if profileID == targetProfile.id { return targetProfile }
                return nil
            },
            spaceProfile: { _ in nil },
            currentProfile: { sourceProfile },
            firstProfile: { sourceProfile }
        )
        tab.attachBrowserRuntime(runtime)
        let runtimePorts = TestRuntimePorts.make(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profileID in
                if profileID == sourceProfile.id { return sourceProfile }
                if profileID == targetProfile.id { return targetProfile }
                return nil
            }
        )
        let lease = TabRuntimePortConnection(runtimePorts).captureLease()
        guard let profileWitness = lease.captureProfileAssignmentWitness(
            sourceProfile: sourceProfile,
            targetProfile: targetProfile
        ) else {
            preconditionFailure("Test profile witness must be current")
        }
        return PreparedTabProfileAssignment(
            tab: tab,
            sourceProfileID: sourceProfileID,
            profileWitness: profileWitness,
            sourceRevision: tab.profileAssignment.changeRevision,
            desiredProfileID: targetProfile.id,
            runtimeFallback: nil,
            navigationIntent: tab.mainFrameLoads.currentIntent,
            sourceWebView: nil,
            sourceSessionGeneration: tab.webViewSession.generation,
            sourceSessionWebViews: tab.webViewSession.allKnownWebViews,
            targetURL: tab.url
        )
    }
}

@MainActor
final class ShortcutTabProfileAssignmentBatchTests: XCTestCase {
    func testDetachedRuntimeLeaseRejectsModelOnlyBatch() {
        let connection = TabRuntimePortConnection()
        let model = RejectableBindingAggregate()
        var settlements: [ProfileTransitionSettlement] = []

        let outcome = ShortcutTabProfileAssignmentBatch(
            connection: connection,
            lease: connection.captureLease(),
            admissions: []
        ).execute(
            bindingModel: model,
            settlement: { settlements.append($0) }
        )

        XCTAssertEqual(outcome, .rejectedUnstaged(.stale))
        XCTAssertEqual(model.cancelCount, 1)
        XCTAssertEqual(model.stageCount, 0)
        XCTAssertEqual(settlements, [.rejected(.stale)])
    }

    func testDetachedRejectionReportsConflictWhenPreparedCancelFails() {
        let connection = TabRuntimePortConnection()
        let model = RejectableBindingAggregate(cancelResult: false)
        var settlements: [ProfileTransitionSettlement] = []

        let outcome = ShortcutTabProfileAssignmentBatch(
            connection: connection,
            lease: connection.captureLease(),
            admissions: []
        ).execute(
            bindingModel: model,
            settlement: { settlements.append($0) }
        )

        XCTAssertEqual(outcome, .conflicted)
        XCTAssertEqual(model.cancelCount, 1)
        XCTAssertEqual(settlements, [.conflicted])
    }

    func testInnerUnstagedRejectionIsReplacedByOneConflict() {
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            executePreparedProfileAssignments: { _, _, _ in
                .rejectedUnstaged(.failed)
            }
        )
        let connection = TabRuntimePortConnection(
            TestRuntimePorts.make(webViewLifecycle: lifecycle)
        )
        let model = RejectableBindingAggregate(cancelResult: false)
        var settlements: [ProfileTransitionSettlement] = []

        let outcome = ShortcutTabProfileAssignmentBatch(
            connection: connection,
            lease: connection.captureLease(),
            admissions: []
        ).execute(
            bindingModel: model,
            settlement: { settlements.append($0) }
        )

        XCTAssertEqual(outcome, .conflicted)
        XCTAssertEqual(model.cancelCount, 1)
        XCTAssertEqual(settlements, [.conflicted])
    }

    func testDriftedPreparedModelStillReceivesCancellationAttempt() {
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting
        )
        let connection = TabRuntimePortConnection(
            TestRuntimePorts.make(webViewLifecycle: lifecycle)
        )
        let model = RejectableBindingAggregate(validateResult: false)
        var settlements: [ProfileTransitionSettlement] = []

        let outcome = ShortcutTabProfileAssignmentBatch(
            connection: connection,
            lease: connection.captureLease(),
            admissions: []
        ).execute(
            bindingModel: model,
            settlement: { settlements.append($0) }
        )

        XCTAssertEqual(outcome, .rejectedUnstaged(.stale))
        XCTAssertEqual(model.cancelCount, 1)
        XCTAssertEqual(model.stageCount, 0)
        XCTAssertEqual(settlements, [.rejected(.stale)])
    }

    func testValidEmptyBatchCommitsThroughTheModelTransaction() {
        let lifecycle = TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting
        )
        let connection = TabRuntimePortConnection(
            TestRuntimePorts.make(webViewLifecycle: lifecycle)
        )
        let model = RejectableBindingAggregate()
        var settlements: [ProfileTransitionSettlement] = []

        let outcome = ShortcutTabProfileAssignmentBatch(
            connection: connection,
            lease: connection.captureLease(),
            admissions: []
        ).execute(
            bindingModel: model,
            settlement: { settlements.append($0) }
        )

        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(model.cancelCount, 0)
        XCTAssertEqual(model.stageCount, 1)
        XCTAssertEqual(model.publishCommitCount, 1)
        XCTAssertEqual(settlements, [.committed])
    }
}

@MainActor
private final class RejectableBindingAggregate:
    ShortcutTabBindingAggregateTransaction {
    private let cancelResult: Bool
    private let validateResult: Bool
    private var didClaim = false
    private(set) var cancelCount = 0
    private(set) var stageCount = 0
    private(set) var publishCommitCount = 0

    init(cancelResult: Bool = true, validateResult: Bool = true) {
        self.cancelResult = cancelResult
        self.validateResult = validateResult
    }

    var exactBindingTabs: [Tab] { [] }

    func cancelPrepared() -> Bool {
        cancelCount += 1
        return cancelResult
    }

    func validateForStaging() -> Bool { validateResult }
    func stage() throws { stageCount += 1 }
    func retainsModelAfterFailedStage() -> Bool { false }
    func stagedModelIsExact() -> Bool { true }
    func canClaimTerminalModel() -> Bool { true }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        didClaim = true
        return .sealed
    }
    func claimedModelIsExact() -> Bool { didClaim }
    func publishCommit() { publishCommitCount += 1 }
    func rollback() throws {}
    func publishRollback() {}
    func canSettleTerminalDrain() -> Bool { true }
    func settleTerminalDrain() -> Bool { true }
}
