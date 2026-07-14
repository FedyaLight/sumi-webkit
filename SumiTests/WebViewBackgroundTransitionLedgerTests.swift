import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WebViewBackgroundTransitionLedgerTests: XCTestCase {
    func testNewWindowLeaseInvalidatesOldOwnerForSameWebView() {
        let ledger = WebViewBackgroundTransitionLedger()
        let webView = WKWebView()
        let oldWindowLease = ledger.begin(for: webView)
        let newWindowLease = ledger.begin(for: webView)

        XCTAssertFalse(ledger.isCurrent(oldWindowLease))
        XCTAssertFalse(ledger.finish(matching: oldWindowLease))
        XCTAssertTrue(ledger.isCurrent(newWindowLease))
        XCTAssertTrue(ledger.finish(matching: newWindowLease))
    }

    func testOldRestoreDeadlineCannotConsumeNewWindowLease() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let ledger = WebViewBackgroundTransitionLedger(
            delayedActions: delayedActions.scheduler
        )
        let webView = WKWebView()
        let oldWindowLease = ledger.begin(for: webView)
        ledger.scheduleRestore(
            matching: oldWindowLease,
            delay: 0.001,
            isStillValid: { true }
        )

        let newWindowLease = ledger.begin(for: webView)
        XCTAssertEqual(delayedActions.scheduledDelays, [0.001])
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertFalse(ledger.isCurrent(oldWindowLease))
        XCTAssertTrue(ledger.isCurrent(newWindowLease))
        XCTAssertTrue(ledger.finish(matching: newWindowLease))
    }

    func testScheduledRestoreCompletesCurrentLeaseWhenDriven() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let ledger = WebViewBackgroundTransitionLedger(
            delayedActions: delayedActions.scheduler
        )
        let webView = WKWebView()
        let lease = ledger.begin(for: webView)

        ledger.scheduleRestore(matching: lease, isStillValid: { true })

        XCTAssertEqual(delayedActions.scheduledDelays, [0.15])
        XCTAssertTrue(ledger.isCurrent(lease))
        delayedActions.runNext()
        XCTAssertFalse(ledger.isCurrent(lease))
    }
}
