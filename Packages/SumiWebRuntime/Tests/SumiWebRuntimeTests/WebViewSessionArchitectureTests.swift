import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewSessionArchitectureTests: XCTestCase {
    func testCancellingOnePendingCleanupWaiterDoesNotSettleOrCancelPeers()
        async throws {
        let repository = WebViewSessionRepository()
        let webView = WKWebView()
        let lease = try XCTUnwrap(
            repository.beginPendingCleanup(of: webView, for: UUID())
        )
        let cancelledWaiter = Task { @MainActor in
            await repository.queries.waitUntilPendingCleanupIsEmpty()
        }
        let survivingWaiter = Task { @MainActor in
            await repository.queries.waitUntilPendingCleanupIsEmpty()
        }
        await Task.yield()

        cancelledWaiter.cancel()

        let cancelledResult = await cancelledWaiter.value
        XCTAssertFalse(cancelledResult)
        XCTAssertFalse(repository.queries.pendingCleanupSnapshot().isEmpty)
        XCTAssertTrue(
            repository.consumePendingCleanup(of: webView, lease: lease)
        )
        let survivingResult = await survivingWaiter.value
        XCTAssertTrue(survivingResult)
        XCTAssertTrue(repository.queries.pendingCleanupSnapshot().isEmpty)
    }

    func testCancellingUnifiedWaiterLeavesOpenTransitionAndPeersIntact()
        async {
        let ledger = WebViewOwnershipTransitionLedger()
        let batchID = UUID()
        ledger.openTransactionBatch(batchID)
        let cancelledWaiter = Task { @MainActor in
            await ledger.waitUntilSettled()
        }
        let survivingWaiter = Task { @MainActor in
            await ledger.waitUntilSettled()
        }
        await Task.yield()

        cancelledWaiter.cancel()

        let cancelledResult = await cancelledWaiter.value
        XCTAssertFalse(cancelledResult)
        XCTAssertTrue(ledger.hasTransitions)
        XCTAssertEqual(ledger.openBatchIDs, [batchID])
        ledger.finishTransactionBatch(batchID)
        let survivingResult = await survivingWaiter.value
        XCTAssertTrue(survivingResult)
        XCTAssertFalse(ledger.hasTransitions)
    }

    func testRetirementLedgerTransfersPreviousGenerationOutOfItsStorage()
        throws {
        let ledger = WebViewOwnershipTransitionLedger()
        let batchID = UUID()
        let tabID = UUID()
        let windowID = UUID()
        let lease = WebViewRetirementLease(batchID: batchID, tabID: tabID)
        var webView: WKWebView? = WKWebView()
        let webViewID = ObjectIdentifier(try XCTUnwrap(webView))
        var snapshot: WebViewSessionSnapshot? = WebViewSessionSnapshot(
            generation: 1,
            parkedWebView: nil,
            untrackedWebView: nil,
            primaryWindowID: windowID,
            windowWebViews: [windowID: try XCTUnwrap(webView)]
        )
        ledger.openTransactionBatch(batchID)
        ledger.retainRetirement(try XCTUnwrap(snapshot), lease: lease)

        snapshot = nil
        webView = nil

        XCTAssertNotNil(ledger.webView(with: webViewID))
        XCTAssertTrue(containsWebView(in: ledger))
        let retired = ledger.takeRetirement(lease)
        XCTAssertEqual(
            retired?.windowWebViews[windowID].map(ObjectIdentifier.init),
            webViewID
        )
        XCTAssertNil(ledger.webView(with: webViewID))
        XCTAssertFalse(containsWebView(in: ledger))
        ledger.finishTransactionBatch(batchID)
    }

    func testReplacementTransactionStoreRetainsFingerprintNotWebView() throws {
        let transactionStore = WebViewSessionTransitionTransactionStore()
        let tabID = UUID()
        let windowID = UUID()
        let batchLease = WebViewReplacementBatchLease(id: UUID())
        let retirementLease = WebViewRetirementLease(
            batchID: batchLease.id,
            tabID: tabID
        )
        var webView: WKWebView? = WKWebView()
        var snapshot: WebViewSessionSnapshot? = WebViewSessionSnapshot(
            generation: 2,
            parkedWebView: nil,
            untrackedWebView: nil,
            primaryWindowID: windowID,
            windowWebViews: [windowID: try XCTUnwrap(webView)]
        )
        let fingerprint = WebViewPlacementFingerprint(try XCTUnwrap(snapshot))
        transactionStore.install(.init(
            lease: .replacement(batchLease),
            entriesByTabID: [
                tabID: .init(
                    retirementLease: retirementLease,
                    installed: fingerprint
                ),
            ],
            modelTransactionID: nil
        ))

        snapshot = nil
        webView = nil

        let storedBatch = try XCTUnwrap(transactionStore.batch(for: batchLease))
        XCTAssertFalse(containsWebView(in: storedBatch))
        XCTAssertEqual(storedBatch.entriesByTabID[tabID]?.installed, fingerprint)
    }

    func testCommitAndRollbackRejectFingerprintConflictWithoutSettlingBatch() {
        let placements = WebViewSessionPlacementStore()
        let transitions = WebViewOwnershipTransitionLedger()
        let transactions = WebViewSessionTransitionTransactionStore()
        let validator = WebViewSessionConsistencyValidator(
            placements: placements,
            transitions: transitions,
            transactions: transactions
        )
        let coordinator = WebViewSessionTransitionCoordinator(
            placements: placements,
            transitions: transitions,
            transactions: transactions,
            validator: validator
        )
        let tabID = UUID()
        let previous = WKWebView()
        let replacement = WKWebView()
        placements.noteUntrackedWebView(previous, for: tabID)

        let begin = coordinator.begin(
            [
                .init(
                    tabID: tabID,
                    expectedGeneration: placements.generation(for: tabID),
                    placement: .detached(
                        webView: replacement,
                        residence: .untracked
                    )
                ),
            ],
            validateModel: { true },
            modelCommit: { () }
        )
        guard case .began(let lease) = begin else {
            return XCTFail("Expected replacement batch")
        }

        placements.noteParkedWebView(WKWebView(), for: tabID)

        guard case .conflict(let commitTabID, _) = coordinator.commit(lease)
        else {
            return XCTFail("Commit must detect changed placement fingerprint")
        }
        XCTAssertEqual(commitTabID, tabID)
        guard case .conflict(let rollbackTabID, _) = coordinator.rollback(
            lease,
            modelRollback: { () }
        ) else {
            return XCTFail("Rollback must detect changed placement fingerprint")
        }
        XCTAssertEqual(rollbackTabID, tabID)
        XCTAssertNotNil(transactions.batch(for: lease))
        XCTAssertTrue(transitions.hasTransitions)
    }

    private func containsWebView(in value: Any) -> Bool {
        if value is WKWebView { return true }
        return Mirror(reflecting: value).children.contains {
            containsWebView(in: $0.value)
        }
    }
}
