import XCTest

@testable import Sumi

@MainActor
final class SumiGeolocationProviderTests: XCTestCase {
    func testProviderStateTransitionsActivePausedActiveRevoked() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)

        XCTAssertEqual(provider.pause(), .paused)
        XCTAssertEqual(provider.resume(), .active)
        XCTAssertEqual(provider.revoke(), .revoked)

        XCTAssertEqual(provider.pauseCallCount, 1)
        XCTAssertEqual(provider.resumeCallCount, 1)
        XCTAssertEqual(provider.revokeCallCount, 1)
    }

    func testStopAndRevokeAreIdempotent() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        provider.registerAllowedRequest(pageId: "page-a", tabId: "tab-a")

        XCTAssertEqual(provider.stop(), .inactive)
        XCTAssertEqual(provider.stop(), .inactive)
        XCTAssertEqual(provider.revoke(), .revoked)
        XCTAssertEqual(provider.revoke(), .revoked)

        XCTAssertEqual(provider.stopCallCount, 2)
        XCTAssertEqual(provider.revokeCallCount, 2)
        XCTAssertTrue(provider.registeredRequests.isEmpty)
    }

    func testPauseWhileInactiveIsNoOpState() {
        let provider = FakeSumiGeolocationProvider(currentState: .inactive)

        XCTAssertEqual(provider.pause(), .inactive)
        XCTAssertEqual(provider.currentState, .inactive)
    }

    func testRegisterAndCancelAllowedRequestsDoNotPersistSiteDecisions() {
        let provider = FakeSumiGeolocationProvider(currentState: .inactive)

        provider.registerAllowedRequest(pageId: "page-a", tabId: "tab-a")
        provider.registerAllowedRequest(pageId: "page-b", tabId: "tab-a")
        provider.cancelAllowedRequest(pageId: "page-a")

        XCTAssertEqual(provider.registeredRequests.map(\.pageId), ["page-b"])
        XCTAssertEqual(provider.cancelledPageIds, ["page-a"])

        provider.cancelAllowedRequests(tabId: "tab-a")
        XCTAssertTrue(provider.registeredRequests.isEmpty)
        XCTAssertEqual(provider.currentState, .inactive)
    }

    func testStateObservationEmitsInitialAndChangedStatesUntilCancelled() {
        let provider = FakeSumiGeolocationProvider(currentState: .inactive)
        var observedStates: [SumiGeolocationProviderState] = []

        let observation = provider.observeState { state in
            observedStates.append(state)
        }
        provider.currentState = .active
        observation.cancel()
        provider.currentState = .paused

        XCTAssertEqual(observedStates, [.inactive, .active])
    }

    func testUnavailableProviderReportsUnavailable() {
        let provider = FakeSumiGeolocationProvider(currentState: .unavailable)

        XCTAssertFalse(provider.isAvailable)
        XCTAssertEqual(provider.pause(), .unavailable)
        XCTAssertEqual(provider.resume(), .unavailable)
    }

    func testApplicationLifecycleControllerPausesActiveGeolocationWhileApplicationInactive() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        let browserManager = BrowserManager(geolocationProvider: provider)
        let controller = BrowserApplicationLifecycleController(
            dependencies: .live(browserManager: browserManager)
        )

        controller.handleApplicationWillResignActive()
        XCTAssertEqual(provider.currentState, .paused)
        XCTAssertEqual(provider.pauseCallCount, 1)

        controller.handleApplicationDidBecomeActive()
        XCTAssertEqual(provider.currentState, .active)
        XCTAssertEqual(provider.resumeCallCount, 1)
    }

    func testApplicationLifecycleControllerDoesNotResumeUserPausedGeolocationOnActivation() {
        let provider = FakeSumiGeolocationProvider(currentState: .paused)
        let browserManager = BrowserManager(geolocationProvider: provider)
        let controller = BrowserApplicationLifecycleController(
            dependencies: .live(browserManager: browserManager)
        )

        controller.handleApplicationWillResignActive()
        controller.handleApplicationDidBecomeActive()

        XCTAssertEqual(provider.currentState, .paused)
        XCTAssertEqual(provider.pauseCallCount, 0)
        XCTAssertEqual(provider.resumeCallCount, 0)
    }
}
