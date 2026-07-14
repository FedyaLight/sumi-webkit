import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewReplacementSettlementServiceTests: XCTestCase {
    func testPartialBindingDoesNotCommitUntilEveryExactReplacementIsSubmitted() async {
        let fixture = makeTwoWindowFixture()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner()
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacementPrimary, semanticRevision: 7),
                .init(webView: fixture.replacementClone, semanticRevision: 7),
            ]
        )
        let primaryToken = try! XCTUnwrap(
            receipt.bindingToken(for: fixture.replacementPrimary)
        )
        let cloneToken = try! XCTUnwrap(
            receipt.bindingToken(for: fixture.replacementClone)
        )

        XCTAssertEqual(
            owner.markBound(
                primaryToken,
                binding: binding(for: fixture.replacementPrimary, revision: 7)
            ),
            .accepted
        )
        XCTAssertEqual(owner.activeTransactionCount, 1)
        XCTAssertTrue(recorder.retiredCommits.isEmpty)
        guard case .retiring = fixture.repository.residence(of: fixture.oldPrimary) else {
            return XCTFail("Old generation retired before every binding")
        }

        XCTAssertEqual(
            owner.markBound(
                cloneToken,
                binding: binding(for: fixture.replacementClone, revision: 7)
            ),
            .committed
        )

        XCTAssertEqual(owner.activeTransactionCount, 0)
        XCTAssertEqual(recorder.commitCallCount, 1)
        XCTAssertEqual(recorder.retiredCommits.count, 1)
        XCTAssertNil(fixture.repository.residence(of: fixture.oldPrimary))
        XCTAssertNil(fixture.repository.residence(of: fixture.oldClone))
        let outcome = await receipt.waitForSettlement()
        XCTAssertEqual(outcome, .committed)
    }

    func testForeignStaleAndLateBindingProofsAreIgnored() async {
        let fixture = makeOneWindowFixture()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner()
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 41),
            ]
        )
        let token = try! XCTUnwrap(receipt.bindingToken(for: fixture.replacement))

        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: WKWebView(), revision: 41)
            ),
            .ignored
        )
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 42)
            ),
            .ignored
        )
        let falseLifetime = NSObject()
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: .init(
                    webView: fixture.replacement,
                    semanticRevision: 41,
                    navigationID: ObjectIdentifier(NSObject()),
                    navigationLifetime: falseLifetime
                )
            ),
            .ignored
        )
        XCTAssertEqual(owner.activeTransactionCount, 1)

        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 41)
            ),
            .committed
        )
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 41)
            ),
            .ignored
        )
        XCTAssertEqual(recorder.commitCallCount, 1)
        let outcome = await receipt.waitForSettlement()
        XCTAssertEqual(outcome, .committed)
    }

    func testTimeoutRollsBackRepositoryModelAndPhysicalStateExactlyOnce() async {
        let fixture = makeOneWindowFixture()
        let timeoutGate = RetirementTestGate()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner(waitForTimeout: {
            await timeoutGate.wait()
        })
        var modelRollbackCount = 0
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 5),
            ],
            modelRollback: { modelRollbackCount += 1 }
        )
        let token = try! XCTUnwrap(receipt.bindingToken(for: fixture.replacement))
        await waitUntil { timeoutGate.hasWaiter }

        timeoutGate.open()
        let outcome = await receipt.waitForSettlement()

        XCTAssertEqual(
            outcome,
            .rolledBack(.bindingFailure(.timedOut))
        )
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertEqual(recorder.rollbackCallCount, 1)
        XCTAssertEqual(recorder.restorations.count, 1)
        XCTAssertIdentical(
            fixture.repository.webView(
                for: fixture.tabID,
                in: fixture.windowID
            ),
            fixture.oldWebView
        )
        XCTAssertNil(fixture.repository.residence(of: fixture.replacement))
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 5)
            ),
            .ignored
        )
        XCTAssertEqual(
            owner.fail(token, reason: .submissionFailed),
            .ignored
        )
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertEqual(recorder.restorations.count, 1)
    }

    func testFailedCommitValidationRollsBackBeforeRepositoryCommit() async {
        let fixture = makeOneWindowFixture()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner()
        var modelRollbackCount = 0
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 17),
            ],
            modelRollback: { modelRollbackCount += 1 }
        )
        let token = try! XCTUnwrap(
            receipt.bindingToken(for: fixture.replacement)
        )
        recorder.commitIsValid = false

        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 17)
            ),
            .rolledBack(.commitValidationFailed)
        )

        XCTAssertEqual(recorder.commitCallCount, 0)
        XCTAssertEqual(recorder.rollbackCallCount, 1)
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertTrue(recorder.retiredCommits.isEmpty)
        XCTAssertEqual(
            recorder.restorations.map(\.reason),
            [.commitValidationFailed]
        )
        XCTAssertIdentical(
            fixture.repository.webView(
                for: fixture.tabID,
                in: fixture.windowID
            ),
            fixture.oldWebView
        )
        XCTAssertNil(fixture.repository.residence(of: fixture.replacement))
        let outcome = await receipt.waitForSettlement()
        XCTAssertEqual(outcome, .rolledBack(.commitValidationFailed))
    }

    func testProfileAbortRollsBackOnlyIntersectingTransaction() async {
        let first = makeOneWindowFixture()
        let second = makeOneWindowFixture(repository: first.repository)
        let firstProfileID = UUID()
        let secondProfileID = UUID()
        let recorder = RetirementRuntimeRecorder(repository: first.repository)
        let owner = recorder.makeOwner()
        let firstReceipt = start(
            owner,
            lease: first.lease,
            tabIDs: [first.tabID],
            profileIDs: [firstProfileID],
            retired: [first.tabID: first.retired],
            requirements: [
                .init(webView: first.replacement, semanticRevision: 1),
            ]
        )
        let secondReceipt = start(
            owner,
            lease: second.lease,
            tabIDs: [second.tabID],
            profileIDs: [secondProfileID],
            retired: [second.tabID: second.retired],
            requirements: [
                .init(webView: second.replacement, semanticRevision: 2),
            ]
        )

        XCTAssertEqual(
            owner.abortForProfiles(
                [firstProfileID],
                reason: .destructiveDataCleanup
            ),
            1
        )
        XCTAssertEqual(owner.activeTransactionCount, 1)
        let firstOutcome = await firstReceipt.waitForSettlement()
        XCTAssertEqual(
            firstOutcome,
            .rolledBack(.abort(.destructiveDataCleanup))
        )
        XCTAssertIdentical(
            first.repository.webView(for: first.tabID, in: first.windowID),
            first.oldWebView
        )
        guard case .retiring = second.repository.residence(of: second.oldWebView) else {
            return XCTFail("Unrelated profile transaction was aborted")
        }

        let secondToken = try! XCTUnwrap(
            secondReceipt.bindingToken(for: second.replacement)
        )
        XCTAssertEqual(
            owner.markBound(
                secondToken,
                binding: binding(for: second.replacement, revision: 2)
            ),
            .committed
        )
        let secondOutcome = await secondReceipt.waitForSettlement()
        XCTAssertEqual(secondOutcome, .committed)
    }

    func testTabAbortRollsBackOnlyIntersectingTransaction() async {
        let first = makeOneWindowFixture()
        let second = makeOneWindowFixture(repository: first.repository)
        let recorder = RetirementRuntimeRecorder(repository: first.repository)
        let owner = recorder.makeOwner()
        let firstReceipt = start(
            owner,
            lease: first.lease,
            tabIDs: [first.tabID],
            retired: [first.tabID: first.retired],
            requirements: [
                .init(webView: first.replacement, semanticRevision: 1),
            ]
        )
        let secondReceipt = start(
            owner,
            lease: second.lease,
            tabIDs: [second.tabID],
            retired: [second.tabID: second.retired],
            requirements: [
                .init(webView: second.replacement, semanticRevision: 2),
            ]
        )

        XCTAssertEqual(
            owner.abortForTabs([first.tabID], reason: .tabDeparture),
            1
        )
        XCTAssertEqual(owner.activeTransactionCount, 1)
        let firstOutcome = await firstReceipt.waitForSettlement()
        XCTAssertEqual(
            firstOutcome,
            .rolledBack(.abort(.tabDeparture))
        )
        XCTAssertIdentical(
            first.repository.webView(for: first.tabID, in: first.windowID),
            first.oldWebView
        )
        guard case .retiring = second.repository.residence(
            of: second.oldWebView
        ) else {
            return XCTFail("Unrelated tab transaction was aborted")
        }

        let secondToken = try! XCTUnwrap(
            secondReceipt.bindingToken(for: second.replacement)
        )
        XCTAssertEqual(
            owner.markBound(
                secondToken,
                binding: binding(for: second.replacement, revision: 2)
            ),
            .committed
        )
        let secondOutcome = await secondReceipt.waitForSettlement()
        XCTAssertEqual(secondOutcome, .committed)
    }

    func testRollbackCASConflictIsFailClosedUntilTerminalReset() async {
        let fixture = makeOneWindowFixture()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        recorder.rollbackOverride = .conflict(
            tabID: fixture.tabID,
            currentGeneration: fixture.repository.queries.generation(
                for: fixture.tabID
            )
        )
        let owner = recorder.makeOwner()
        var completionOutcomes: [WebViewReplacementTransactionOutcome] = []
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 9),
            ],
            completion: { completionOutcomes.append($0) }
        )
        let token = try! XCTUnwrap(receipt.bindingToken(for: fixture.replacement))

        XCTAssertEqual(
            owner.fail(token, reason: .submissionFailed),
            .conflicted
        )

        XCTAssertEqual(owner.activeTransactionCount, 1)
        XCTAssertTrue(recorder.restorations.isEmpty)
        XCTAssertTrue(recorder.retiredCommits.isEmpty)
        let outcome = await receipt.waitForSettlement()
        XCTAssertEqual(outcome, .conflicted)
        XCTAssertEqual(completionOutcomes, [.conflicted])
        XCTAssertEqual(
            owner.fail(token, reason: .submissionFailed),
            .ignored
        )

        owner.resetForTerminalShutdown()
        XCTAssertEqual(owner.activeTransactionCount, 0)
        XCTAssertEqual(completionOutcomes, [.conflicted])
        XCTAssertTrue(recorder.restorations.isEmpty)
        XCTAssertTrue(recorder.retiredCommits.isEmpty)
    }

    func testCancelledSettlementWaitDoesNotAbandonTransaction() async {
        let fixture = makeOneWindowFixture()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner()
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 3),
            ]
        )
        let token = try! XCTUnwrap(receipt.bindingToken(for: fixture.replacement))
        let cancelledWait = Task { @MainActor in
            await receipt.waitForSettlement()
        }
        await Task.yield()
        cancelledWait.cancel()

        let cancelledOutcome = await cancelledWait.value
        XCTAssertNil(cancelledOutcome)
        XCTAssertEqual(owner.activeTransactionCount, 1)
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 3)
            ),
            .committed
        )
        let committedOutcome = await receipt.waitForSettlement()
        XCTAssertEqual(committedOutcome, .committed)
    }

    func testTerminalResetLeavesBothGenerationsForRepositoryDrain() async {
        let fixture = makeOneWindowFixture()
        let timeoutGate = RetirementTestGate()
        let recorder = RetirementRuntimeRecorder(repository: fixture.repository)
        let owner = recorder.makeOwner(waitForTimeout: {
            await timeoutGate.wait()
        })
        let receipt = start(
            owner,
            lease: fixture.lease,
            tabIDs: [fixture.tabID],
            retired: [fixture.tabID: fixture.retired],
            requirements: [
                .init(webView: fixture.replacement, semanticRevision: 13),
            ]
        )
        let token = try! XCTUnwrap(receipt.bindingToken(for: fixture.replacement))
        await waitUntil { timeoutGate.hasWaiter }

        owner.resetForTerminalShutdown()
        timeoutGate.open()
        await Task.yield()

        let outcome = await receipt.waitForSettlement()
        XCTAssertEqual(outcome, .abandonedForTerminalShutdown)
        XCTAssertEqual(owner.activeTransactionCount, 0)
        XCTAssertEqual(recorder.commitCallCount, 0)
        XCTAssertEqual(recorder.rollbackCallCount, 0)
        XCTAssertTrue(recorder.retiredCommits.isEmpty)
        XCTAssertTrue(recorder.restorations.isEmpty)
        XCTAssertEqual(
            owner.markBound(
                token,
                binding: binding(for: fixture.replacement, revision: 13)
            ),
            .ignored
        )

        let drained = fixture.repository.takeAllWebViewsForTerminalShutdown()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(
            Set(drained.map { ObjectIdentifier($0.webView) }),
            [ObjectIdentifier(fixture.oldWebView), ObjectIdentifier(fixture.replacement)]
        )
    }

    private func start(
        _ service: WebViewReplacementSettlementService,
        lease: WebViewReplacementBatchLease,
        tabIDs: Set<UUID>,
        profileIDs: Set<UUID> = [],
        retired: [UUID: WebViewSessionSnapshot],
        requirements: [WebViewReplacementBindingRequirement],
        modelRollback: @escaping WebViewReplacementModelRollback = {},
        completion: @escaping @MainActor (
            WebViewReplacementTransactionOutcome
        ) -> Void = { _ in }
    ) -> WebViewReplacementSettlementReceipt {
        let result = service.start(
            lease: lease,
            tabIDs: tabIDs,
            profileIDs: profileIDs,
            retired: retired,
            requiredBindings: requirements,
            modelRollback: modelRollback,
            completion: completion
        )
        guard case .started(let receipt) = result else {
            preconditionFailure("Expected asynchronous retirement start, got \(result)")
        }
        return receipt
    }

    private func binding(
        for webView: WKWebView,
        revision: UInt64
    ) -> WebViewReplacementNavigationBinding {
        let lifetime = NSObject()
        return WebViewReplacementNavigationBinding(
            webView: webView,
            semanticRevision: revision,
            navigationID: ObjectIdentifier(lifetime),
            navigationLifetime: lifetime
        )
    }

    private func makeOneWindowFixture(
        repository suppliedRepository: WebViewSessionRepository? = nil
    ) -> OneWindowFixture {
        let repository = suppliedRepository ?? WebViewSessionRepository()
        let tabID = UUID()
        let windowID = UUID()
        let oldWebView = WKWebView()
        let replacement = WKWebView()
        register(
            oldWebView,
            tabID: tabID,
            windowID: windowID,
            in: repository
        )
        let retired = repository.snapshot(for: tabID)
        let begin = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: retired.generation,
            webViewsByWindowID: [windowID: replacement],
            primaryWindowID: windowID
        )
        guard case .began(let lease) = begin else {
            preconditionFailure("Expected repository replacement begin")
        }
        return OneWindowFixture(
            repository: repository,
            tabID: tabID,
            windowID: windowID,
            oldWebView: oldWebView,
            replacement: replacement,
            retired: retired,
            lease: lease
        )
    }

    private func makeTwoWindowFixture() -> TwoWindowFixture {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let primaryWindowID = UUID()
        let cloneWindowID = UUID()
        let oldPrimary = WKWebView()
        let oldClone = WKWebView()
        let replacementPrimary = WKWebView()
        let replacementClone = WKWebView()
        register(
            oldPrimary,
            tabID: tabID,
            windowID: primaryWindowID,
            in: repository
        )
        register(
            oldClone,
            tabID: tabID,
            windowID: cloneWindowID,
            in: repository
        )
        let retired = repository.snapshot(for: tabID)
        let begin = repository.beginWindowSetReplacement(
            for: tabID,
            expectedGeneration: retired.generation,
            webViewsByWindowID: [
                primaryWindowID: replacementPrimary,
                cloneWindowID: replacementClone,
            ],
            primaryWindowID: primaryWindowID
        )
        guard case .began(let lease) = begin else {
            preconditionFailure("Expected repository replacement begin")
        }
        return TwoWindowFixture(
            repository: repository,
            tabID: tabID,
            primaryWindowID: primaryWindowID,
            cloneWindowID: cloneWindowID,
            oldPrimary: oldPrimary,
            oldClone: oldClone,
            replacementPrimary: replacementPrimary,
            replacementClone: replacementClone,
            retired: retired,
            lease: lease
        )
    }

    private func register(
        _ webView: WKWebView,
        tabID: UUID,
        windowID: UUID,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: .init(tabID: tabID, windowID: windowID),
            in: repository,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while predicate() == false, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private final class RetirementRuntimeRecorder {
    struct Restoration {
        let discarded: [UUID: WebViewSessionSnapshot]
        let retired: [UUID: WebViewSessionSnapshot]
        let reason: WebViewReplacementRollbackReason
    }

    let repository: WebViewSessionRepository
    var commitCallCount = 0
    var rollbackCallCount = 0
    var quiesced: [[UUID: WebViewSessionSnapshot]] = []
    var retiredCommits: [[UUID: WebViewSessionSnapshot]] = []
    var restorations: [Restoration] = []
    var settlements: [WebViewReplacementSettlementEvent] = []
    var commitOverride: WebViewReplacementBatchCommitResult?
    var rollbackOverride: WebViewReplacementBatchRollbackResult?
    var commitIsValid = true

    init(repository: WebViewSessionRepository) {
        self.repository = repository
    }

    func makeOwner(
        waitForTimeout: (@MainActor () async -> Void)? = nil
    ) -> WebViewReplacementSettlementService {
        WebViewReplacementSettlementService(
            timeout: .seconds(5),
            waitForTimeout: waitForTimeout,
            runtime: .init(
                validateCommitLease: { [weak self] _ in
                    self?.commitIsValid == true
                },
                commitLease: { [weak self] lease in
                    guard let self else { return .noLongerActive }
                    commitCallCount += 1
                    return commitOverride
                        ?? repository.commitReplacementBatch(lease)
                },
                rollbackLease: { [weak self] lease, modelRollback in
                    guard let self else { return .noLongerActive }
                    rollbackCallCount += 1
                    return rollbackOverride
                        ?? repository.rollbackReplacementBatch(
                            lease,
                            modelRollback: modelRollback
                        )
                },
                quiesceRetired: { [weak self] in self?.quiesced.append($0) },
                retireCommitted: { [weak self] in self?.retiredCommits.append($0) },
                restoreAfterRollback: { [weak self] discarded, retired, reason in
                    self?.restorations.append(.init(
                        discarded: discarded,
                        retired: retired,
                        reason: reason
                    ))
                },
                observeSettlement: { [weak self] in self?.settlements.append($0) }
            )
        )
    }
}

@MainActor
private final class RetirementTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isOpen = false

    var hasWaiter: Bool { continuation != nil }

    func wait() async {
        guard isOpen == false else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        guard isOpen == false else { return }
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private struct OneWindowFixture {
    let repository: WebViewSessionRepository
    let tabID: UUID
    let windowID: UUID
    let oldWebView: WKWebView
    let replacement: WKWebView
    let retired: WebViewSessionSnapshot
    let lease: WebViewReplacementBatchLease
}

private struct TwoWindowFixture {
    let repository: WebViewSessionRepository
    let tabID: UUID
    let primaryWindowID: UUID
    let cloneWindowID: UUID
    let oldPrimary: WKWebView
    let oldClone: WKWebView
    let replacementPrimary: WKWebView
    let replacementClone: WKWebView
    let retired: WebViewSessionSnapshot
    let lease: WebViewReplacementBatchLease
}
