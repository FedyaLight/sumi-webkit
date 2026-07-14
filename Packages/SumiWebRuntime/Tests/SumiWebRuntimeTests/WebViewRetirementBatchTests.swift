import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewRetirementBatchTests: XCTestCase {
    func testStaleEntryRejectsWholeBatchBeforeModelTransaction() {
        let repository = WebViewSessionRepository()
        let firstTabID = UUID()
        let secondTabID = UUID()
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()
        repository.noteUntrackedWebView(firstWebView, for: firstTabID)
        repository.noteUntrackedWebView(secondWebView, for: secondTabID)
        let staleGeneration = repository.snapshot(for: secondTabID).generation
        repository.noteParkedWebView(WKWebView(), for: secondTabID)
        var didValidate = false
        var didCommit = false
        let modelTransaction = receipt(
            isCurrent: {
                didValidate = true
                return true
            },
            commit: { didCommit = true }
        )

        let result = repository.beginRetirementBatch(
            [
                entry(firstTabID, in: repository),
                .init(
                    tabID: secondTabID,
                    expectedGeneration: staleGeneration
                ),
            ],
            modelTransaction: modelTransaction
        )

        guard case .stale(let tabID, let currentGeneration) = result else {
            return XCTFail("Expected stale whole-batch rejection")
        }
        XCTAssertEqual(tabID, secondTabID)
        XCTAssertEqual(
            currentGeneration,
            repository.snapshot(for: secondTabID).generation
        )
        XCTAssertFalse(didValidate)
        XCTAssertFalse(didCommit)
        XCTAssertIdentical(repository.untrackedWebView(for: firstTabID), firstWebView)
        XCTAssertIdentical(repository.untrackedWebView(for: secondTabID), secondWebView)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testPendingCleanupConflictRejectsBeforeModelTransaction() throws {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let activeWebView = WKWebView()
        let pendingWebView = WKWebView()
        repository.noteUntrackedWebView(activeWebView, for: tabID)
        let pendingLease = try XCTUnwrap(
            repository.beginPendingCleanup(of: pendingWebView, for: tabID)
        )
        var didValidate = false
        var didCommit = false
        let modelTransaction = receipt(
            isCurrent: {
                didValidate = true
                return true
            },
            commit: { didCommit = true }
        )

        let result = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        )

        guard case .conflict(let conflictTabID) = result else {
            return XCTFail("Expected pending-cleanup conflict")
        }
        XCTAssertEqual(conflictTabID, tabID)
        XCTAssertFalse(didValidate)
        XCTAssertFalse(didCommit)
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), activeWebView)
        XCTAssertEqual(
            repository.residence(of: pendingWebView),
            .pendingCleanup(pendingLease)
        )
        XCTAssertTrue(
            repository.consumePendingCleanup(
                of: pendingWebView,
                lease: pendingLease
            )
        )
    }

    func testRetirementOwnsCurrentSetAndBlocksPlacementMutation() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let parkedWebView = WKWebView()
        let untrackedWebView = WKWebView()
        repository.noteParkedWebView(parkedWebView, for: tabID)
        repository.noteUntrackedWebView(untrackedWebView, for: tabID)
        let modelTransaction = receipt()

        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }

        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        for webView in [parkedWebView, untrackedWebView] {
            guard case .retiring(let retirementLease) = repository.residence(
                of: webView
            ) else {
                return XCTFail("Every current WebView must be retirement-owned")
            }
            XCTAssertEqual(retirementLease.batchID, lease.id)
            XCTAssertEqual(retirementLease.tabID, tabID)
        }

        let rejectedCandidate = WKWebView()
        repository.noteUntrackedWebView(rejectedCandidate, for: tabID)
        XCTAssertNil(repository.residence(of: rejectedCandidate))
        XCTAssertNil(
            repository.beginPendingCleanup(of: rejectedCandidate, for: tabID)
        )
        guard case .rolledBack = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement rollback")
        }
    }

    func testRollbackRunsModelFirstAndRestoresExactTabsWithNewRevision() {
        let repository = WebViewSessionRepository()
        let firstTabID = UUID()
        let secondTabID = UUID()
        let firstParked = WKWebView()
        let firstUntracked = WKWebView()
        let secondUntracked = WKWebView()
        repository.noteParkedWebView(firstParked, for: firstTabID)
        repository.noteUntrackedWebView(firstUntracked, for: firstTabID)
        repository.noteUntrackedWebView(secondUntracked, for: secondTabID)
        let firstOriginal = repository.snapshot(for: firstTabID)
        let secondOriginal = repository.snapshot(for: secondTabID)
        let revisionBeforeBegin = repository.residenceGeneration
        var modelIsRetired = false
        let modelTransaction = receipt(
            commit: { modelIsRetired = true },
            rollback: {
                XCTAssertTrue(modelIsRetired)
                XCTAssertTrue(
                    repository.snapshot(for: firstTabID).allKnownWebViews.isEmpty
                )
                guard case .retiring = repository.residence(of: firstUntracked),
                      case .retiring = repository.residence(of: secondUntracked)
                else {
                    return XCTFail(
                        "Model rollback must run while WebViews are quarantined"
                    )
                }
                modelIsRetired = false
            }
        )

        guard case .began(let lease) = repository.beginRetirementBatch(
            [
                .init(
                    tabID: firstTabID,
                    expectedGeneration: firstOriginal.generation
                ),
                .init(
                    tabID: secondTabID,
                    expectedGeneration: secondOriginal.generation
                ),
            ],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }
        let revisionAfterQuarantine = repository.residenceGeneration
        XCTAssertGreaterThan(revisionAfterQuarantine, revisionBeforeBegin)
        XCTAssertTrue(modelIsRetired)

        guard case .rolledBack = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected exact retirement rollback")
        }

        let firstRestored = repository.snapshot(for: firstTabID)
        let secondRestored = repository.snapshot(for: secondTabID)
        XCTAssertFalse(modelIsRetired)
        XCTAssertGreaterThan(
            repository.residenceGeneration,
            revisionAfterQuarantine
        )
        XCTAssertEqual(firstRestored.generation, firstOriginal.generation)
        XCTAssertEqual(secondRestored.generation, secondOriginal.generation)
        XCTAssertIdentical(firstRestored.parkedWebView, firstParked)
        XCTAssertIdentical(firstRestored.untrackedWebView, firstUntracked)
        XCTAssertIdentical(secondRestored.untrackedWebView, secondUntracked)
        XCTAssertEqual(
            repository.residence(of: firstUntracked),
            .untracked(tabID: firstTabID)
        )
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testCommitReturnsExactSnapshotsAndRejectsForeignOrRepeatedLease() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        let original = repository.snapshot(for: tabID)
        let modelTransaction = receipt()
        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }

        let foreignRepository = WebViewSessionRepository()
        let foreignTabID = UUID()
        foreignRepository.noteUntrackedWebView(WKWebView(), for: foreignTabID)
        let foreignModelTransaction = receipt()
        guard case .began(let foreignLease) = foreignRepository
            .beginRetirementBatch(
                [entry(foreignTabID, in: foreignRepository)],
                modelTransaction: foreignModelTransaction
            ) else {
            return XCTFail("Expected foreign retirement batch")
        }

        guard case .noLongerActive = repository.commitRetirementBatch(
            foreignLease
        ) else {
            return XCTFail("A foreign lease must not settle this repository")
        }
        guard case .committed(let retired) = repository.commitRetirementBatch(
            lease
        ) else {
            return XCTFail("Expected exact retirement commit")
        }
        XCTAssertEqual(retired[tabID]?.generation, original.generation)
        XCTAssertIdentical(retired[tabID]?.untrackedWebView, webView)
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertNil(repository.residence(of: webView))
        XCTAssertFalse(repository.runtimeOwnedTabIDs.contains(tabID))
        guard case .noLongerActive = repository.commitRetirementBatch(lease)
        else {
            return XCTFail("A retirement lease must commit exactly once")
        }
        guard case .noLongerActive = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("A committed lease must not roll back")
        }
        _ = foreignRepository.rollbackRetirementBatch(
            foreignLease,
            modelTransaction: foreignModelTransaction
        )
    }

    func testModelValidationFailureLeavesRuntimeUntouched() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        let original = repository.snapshot(for: tabID)
        var didCommit = false
        let modelTransaction = receipt(
            isCurrent: { false },
            commit: { didCommit = true }
        )

        let result = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        )

        guard case .modelValidationFailed = result else {
            return XCTFail("Expected model validation failure")
        }
        XCTAssertFalse(didCommit)
        XCTAssertEqual(repository.snapshot(for: tabID).generation, original.generation)
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), webView)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testTerminalDrainDuringModelCommitReturnsNoActiveLease() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        var drained: [WebViewTerminalCleanupEntry] = []
        var drainedBatchID: UUID?
        var didRollbackModel = false
        let modelTransaction = receipt(
            commit: {
                guard case .retiring(let lease) = repository.residence(
                    of: webView
                ) else {
                    return XCTFail("Commit must observe quarantined WebView")
                }
                drainedBatchID = lease.batchID
                drained = repository.takeAllWebViewsForTerminalShutdown()
            },
            rollback: { didRollbackModel = true }
        )

        let result = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        )

        guard case .noLongerActive = result else {
            return XCTFail("Terminal commit drain must not publish a live lease")
        }
        XCTAssertEqual(drained.count, 1)
        XCTAssertIdentical(drained.first?.webView, webView)
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
        guard let drainedBatchID else {
            return XCTFail("Drain must preserve the exact batch identity")
        }
        let staleLease = WebViewRetirementBatchLease(id: drainedBatchID)
        guard case .noLongerActive = repository.commitRetirementBatch(
            staleLease
        ) else {
            return XCTFail("Drained commit lease must stay inactive")
        }
        guard case .noLongerActive = repository.rollbackRetirementBatch(
            staleLease,
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Drained commit lease must not resurrect runtime")
        }
        XCTAssertFalse(didRollbackModel)
    }

    func testTerminalDrainDuringModelRollbackDoesNotResurrectWebView() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        var modelIsRetired = false
        var drained: [WebViewTerminalCleanupEntry] = []
        let modelTransaction = receipt(
            commit: { modelIsRetired = true },
            rollback: {
                XCTAssertTrue(modelIsRetired)
                guard case .retiring = repository.residence(of: webView) else {
                    return XCTFail("Rollback must keep WebView quarantined")
                }
                modelIsRetired = false
                drained = repository.takeAllWebViewsForTerminalShutdown()
            }
        )
        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }

        let result = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        )

        guard case .noLongerActive = result else {
            return XCTFail("Terminal rollback drain must own settlement")
        }
        XCTAssertFalse(modelIsRetired)
        XCTAssertEqual(drained.count, 1)
        XCTAssertIdentical(drained.first?.webView, webView)
        XCTAssertTrue(repository.snapshot(for: tabID).allKnownWebViews.isEmpty)
        XCTAssertNil(repository.residence(of: webView))
        guard case .noLongerActive = repository.commitRetirementBatch(lease)
        else {
            return XCTFail("Terminally drained lease must stay inactive")
        }
        guard case .noLongerActive = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Terminally drained rollback must not resurrect")
        }
    }

    func testCommitCannotSettleLeaseDuringModelRollback() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        var leaseForReentry: WebViewRetirementBatchLease?
        var reentrantResult: WebViewRetirementBatchCommitResult?
        var modelRollbackCount = 0
        let modelTransaction = receipt(
            rollback: {
                modelRollbackCount += 1
                guard let leaseForReentry else {
                    return XCTFail("Rollback must have its exact lease")
                }
                reentrantResult = repository.commitRetirementBatch(
                    leaseForReentry
                )
            }
        )
        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }
        leaseForReentry = lease

        let outerResult = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        )

        guard case .rolledBack = outerResult else {
            return XCTFail("Outer rollback must settle exactly once")
        }
        guard case .noLongerActive? = reentrantResult else {
            return XCTFail("Reentrant commit must fail closed")
        }
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), webView)
        XCTAssertEqual(
            repository.residence(of: webView),
            .untracked(tabID: tabID)
        )
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testRollbackCannotRecursivelySettleSameLease() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        let receiptHolder = RetirementReceiptHolder()
        var leaseForReentry: WebViewRetirementBatchLease?
        var recursiveResult: WebViewRetirementBatchRollbackResult?
        var modelRollbackCount = 0
        let modelTransaction = receipt(
            rollback: { [weak receiptHolder] in
                modelRollbackCount += 1
                guard let leaseForReentry,
                      let exactReceipt = receiptHolder?.receipt else {
                    return XCTFail("Recursive call must retain exact evidence")
                }
                recursiveResult = repository.rollbackRetirementBatch(
                    leaseForReentry,
                    modelTransaction: exactReceipt
                )
            }
        )
        receiptHolder.receipt = modelTransaction
        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }
        leaseForReentry = lease

        let outerResult = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: modelTransaction
        )

        guard case .rolledBack = outerResult else {
            return XCTFail("Outer rollback must settle exactly once")
        }
        guard case .noLongerActive? = recursiveResult else {
            return XCTFail("Recursive rollback must fail closed")
        }
        XCTAssertEqual(modelRollbackCount, 1)
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), webView)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    func testRollbackRequiresExactModelTransactionReceipt() {
        let repository = WebViewSessionRepository()
        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        var wrongRollbackCount = 0
        let exactTransaction = receipt()
        let wrongTransaction = receipt(
            rollback: { wrongRollbackCount += 1 }
        )
        guard case .began(let lease) = repository.beginRetirementBatch(
            [entry(tabID, in: repository)],
            modelTransaction: exactTransaction
        ) else {
            return XCTFail("Expected retirement batch")
        }

        guard case .modelTransactionMismatch = repository
            .rollbackRetirementBatch(
                lease,
                modelTransaction: wrongTransaction
            ) else {
            return XCTFail("Wrong model transaction must fail closed")
        }
        XCTAssertEqual(wrongRollbackCount, 0)
        guard case .retiring = repository.residence(of: webView) else {
            return XCTFail("Wrong receipt must leave quarantine intact")
        }
        guard case .rolledBack = repository.rollbackRetirementBatch(
            lease,
            modelTransaction: exactTransaction
        ) else {
            return XCTFail("Exact model transaction must roll back")
        }
    }

    func testEmptyDuplicateAndMissingActiveInputsAreInvalid() {
        let repository = WebViewSessionRepository()
        let modelTransaction = receipt()
        guard case .invalid(tabID: nil) = repository.beginRetirementBatch(
            [],
            modelTransaction: modelTransaction
        ) else {
            return XCTFail("An empty retirement batch must be invalid")
        }

        let missingTabID = UUID()
        guard case .invalid(tabID: missingTabID) = repository
            .beginRetirementBatch(
                [entry(missingTabID, in: repository)],
                modelTransaction: modelTransaction
            ) else {
            return XCTFail("A tab without active WebViews must be invalid")
        }

        let tabID = UUID()
        let webView = WKWebView()
        repository.noteUntrackedWebView(webView, for: tabID)
        let duplicate = entry(tabID, in: repository)
        guard case .invalid(tabID: tabID) = repository
            .beginRetirementBatch(
                [duplicate, duplicate],
                modelTransaction: modelTransaction
            ) else {
            return XCTFail("Duplicate retirement entries must be invalid")
        }
        XCTAssertIdentical(repository.untrackedWebView(for: tabID), webView)
        XCTAssertTrue(repository.queries.ownershipTransitionSnapshot().isEmpty)
    }

    private func entry(
        _ tabID: UUID,
        in repository: WebViewSessionRepository
    ) -> WebViewRetirementBatchEntry {
        .init(
            tabID: tabID,
            expectedGeneration: repository.snapshot(for: tabID).generation
        )
    }

    private func receipt(
        isCurrent: @escaping @MainActor () -> Bool = { true },
        commit: @escaping @MainActor () -> Void = {},
        rollback: @escaping @MainActor () -> Void = {}
    ) -> WebViewRetirementModelTransactionReceipt {
        .init(
            isCurrent: isCurrent,
            commit: commit,
            rollback: rollback
        )
    }
}

@MainActor
private final class RetirementReceiptHolder {
    var receipt: WebViewRetirementModelTransactionReceipt?
}
