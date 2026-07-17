import Combine
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserWebViewCycleBoundaryTests: XCTestCase {
    func testWindowCommandChannelDeliversSelectAndRefreshCommandsSynchronously() {
        let channel = BrowserWebViewWindowCommandChannel()
        let tabID = UUID()
        let windowID = UUID()
        var received: [BrowserWebViewWindowCommand] = []
        let subscription = channel.publisher.sink { received.append($0) }
        defer { subscription.cancel() }

        channel.selectTab(tabID, in: windowID)
        channel.refreshCompositor(in: windowID)

        XCTAssertEqual(received.count, 2)
        guard case .selectTab(let receivedTabID, let receivedWindowID) = received[0]
        else {
            return XCTFail("Expected a select-tab command")
        }
        XCTAssertEqual(receivedTabID, tabID)
        XCTAssertEqual(receivedWindowID, windowID)
        guard case .refreshCompositor(let refreshedWindowID) = received[1] else {
            return XCTFail("Expected a compositor-refresh command")
        }
        XCTAssertEqual(refreshedWindowID, windowID)
    }

    func testWindowCommandChannelDoesNotReplayCommandsSentWithoutSubscriber() {
        let channel = BrowserWebViewWindowCommandChannel()
        channel.selectTab(UUID(), in: UUID())
        var receivedCount = 0

        let subscription = channel.publisher.sink { _ in receivedCount += 1 }
        defer { subscription.cancel() }

        XCTAssertEqual(receivedCount, 0)
        channel.refreshCompositor(in: UUID())
        XCTAssertEqual(receivedCount, 1)
    }

    func testCloseRequestFailsClosedWithoutSubscriberAndDoesNotReplay() {
        let broker = BrowserWebViewCloseRequestBroker()

        XCTAssertFalse(broker.requestClose(WKWebView()))

        var deliveryCount = 0
        let subscription = broker.publisher.sink { request in
            deliveryCount += 1
            broker.resolve(request, handled: false)
        }
        defer { subscription.cancel() }

        XCTAssertEqual(deliveryCount, 0)
        XCTAssertFalse(broker.requestClose(WKWebView()))
        XCTAssertEqual(deliveryCount, 1)
    }

    func testCloseRequestReturnsSynchronousHandledResolution() {
        let broker = BrowserWebViewCloseRequestBroker()
        let webView = WKWebView()
        var deliveredWebView: WKWebView?
        let subscription = broker.publisher.sink { request in
            deliveredWebView = request.webView
            broker.resolve(request, handled: true)
        }
        defer { subscription.cancel() }

        XCTAssertTrue(broker.requestClose(webView))
        XCTAssertIdentical(deliveredWebView, webView)
    }

    func testCloseRequestReturnsSynchronousUnhandledResolution() {
        let broker = BrowserWebViewCloseRequestBroker()
        let subscription = broker.publisher.sink { request in
            broker.resolve(request, handled: false)
        }
        defer { subscription.cancel() }

        XCTAssertFalse(broker.requestClose(WKWebView()))
    }

    func testCloseRequestDoesNotReplayOrReuseAStaleResolution() {
        let broker = BrowserWebViewCloseRequestBroker()
        var deliveredRequest: BrowserWebViewCloseRequest?
        var deliveryCount = 0
        var subscription: AnyCancellable? = broker.publisher.sink { request in
            deliveryCount += 1
            deliveredRequest = request
            broker.resolve(request, handled: false)
        }

        XCTAssertFalse(broker.requestClose(WKWebView()))
        XCTAssertEqual(deliveryCount, 1)
        subscription?.cancel()
        subscription = nil

        if let deliveredRequest {
            broker.resolve(deliveredRequest, handled: true)
        } else {
            XCTFail("Expected the first request to be delivered")
        }

        XCTAssertFalse(broker.requestClose(WKWebView()))
        XCTAssertEqual(deliveryCount, 1)
    }
}
