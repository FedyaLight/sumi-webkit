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

    func testOldRestoreDeadlineCannotConsumeNewWindowLease() async {
        let ledger = WebViewBackgroundTransitionLedger()
        let webView = WKWebView()
        let oldWindowLease = ledger.begin(for: webView)
        ledger.scheduleRestore(
            matching: oldWindowLease,
            delay: .milliseconds(1),
            isStillValid: { true }
        )

        let newWindowLease = ledger.begin(for: webView)
        do {
            try await Task.sleep(for: .milliseconds(10))
        } catch {
            XCTFail("Background transition test wait was cancelled")
            return
        }

        XCTAssertFalse(ledger.isCurrent(oldWindowLease))
        XCTAssertTrue(ledger.isCurrent(newWindowLease))
        XCTAssertTrue(ledger.finish(matching: newWindowLease))
    }
}
