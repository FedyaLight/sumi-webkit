import WebKit
import XCTest

@testable import Sumi

@MainActor
final class WindowMediaTouchBarRecoveryControllerTests: XCTestCase {
    func testRecoveryDoesNotScheduleDuplicateImmediateRetry() async {
        let windowID = UUID()
        let tabID = UUID()
        let webView = WKWebView()
        var recoveryCount = 0
        let controller = WindowMediaTouchBarRecoveryController(
            windowID: windowID,
            recover: { receivedTabID, receivedWebView in
                XCTAssertEqual(receivedTabID, tabID)
                XCTAssertIdentical(receivedWebView, webView)
                recoveryCount += 1
            }
        )

        controller.start()
        NotificationCenter.default.post(
            name: .sumiWebViewNeedsMediaTouchBarRecovery,
            object: webView,
            userInfo: [
                SumiMediaTouchBarRecoveryNotificationKey.windowID: windowID,
                SumiMediaTouchBarRecoveryNotificationKey.tabID: tabID,
            ]
        )

        await drainMainQueue()

        XCTAssertEqual(recoveryCount, 1)
        controller.stop()
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }
}
