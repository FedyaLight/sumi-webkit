import WebKit
import XCTest

@testable import SumiWebRuntime

@MainActor
final class WebViewMediaProtectionWaiterTests: XCTestCase {
    func testWaitUntilUnprotectedDoesNotPassAnActiveExactLease() async {
        let owner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let lease = owner.beginVisualHandoffProtection(for: webView)
        var didResume = false

        let waiter = Task { @MainActor in
            let result = await owner.waitUntilUnprotected(webView)
            didResume = true
            return result
        }
        await Task.yield()

        XCTAssertFalse(didResume)
        XCTAssertEqual(owner.finishVisualHandoffProtection(lease), ObjectIdentifier(webView))
        let didPassProtection = await waiter.value
        XCTAssertTrue(didPassProtection)
        XCTAssertTrue(didResume)
    }

    func testOlderVisualLeaseReleaseCannotPassNewerProtection() async {
        let owner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        let olderLease = owner.beginVisualHandoffProtection(for: webView)
        let newerLease = owner.beginVisualHandoffProtection(for: webView)
        var didResume = false

        let waiter = Task { @MainActor in
            let result = await owner.waitUntilUnprotected(webView)
            didResume = true
            return result
        }
        await Task.yield()

        XCTAssertEqual(
            owner.finishVisualHandoffProtection(olderLease),
            ObjectIdentifier(webView)
        )
        await Task.yield()
        XCTAssertFalse(didResume)

        XCTAssertEqual(owner.finishVisualHandoffProtection(newerLease), ObjectIdentifier(webView))
        let didPassProtection = await waiter.value
        XCTAssertTrue(didPassProtection)
    }

    func testTerminalResetFailsOutstandingProtectionWait() async {
        let owner = WebViewMediaProtectionOwner()
        let webView = WKWebView()
        _ = owner.beginVisualHandoffProtection(for: webView)
        let waiter = Task { @MainActor in
            await owner.waitUntilUnprotected(webView)
        }
        await Task.yield()

        owner.resetForTerminalShutdown()

        let didPassProtection = await waiter.value
        XCTAssertFalse(didPassProtection)
    }
}
