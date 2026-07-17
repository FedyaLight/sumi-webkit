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
        provider.registerAllowedRequest(
            pageId: "page-a",
            tabId: "tab-a",
            profilePartitionId: "profile-a"
        )

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

        provider.registerAllowedRequest(
            pageId: "page-a",
            tabId: "tab-a",
            profilePartitionId: "profile-a"
        )
        provider.registerAllowedRequest(
            pageId: "page-b",
            tabId: "tab-a",
            profilePartitionId: "profile-a"
        )
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

    func testLazyProviderDoesNotCreateUnderlyingProviderForInactiveRuntimeReads() {
        var creationCount = 0
        let lazyProvider = SumiLazyGeolocationProvider {
            creationCount += 1
            return FakeSumiGeolocationProvider(currentState: .active)
        }
        var observedStates: [SumiGeolocationProviderState] = []

        XCTAssertEqual(lazyProvider.currentState, .inactive)
        XCTAssertEqual(lazyProvider.pause(), .inactive)
        let observation = lazyProvider.observeState { state in
            observedStates.append(state)
        }

        XCTAssertEqual(creationCount, 0)
        XCTAssertEqual(observedStates, [.inactive])

        XCTAssertTrue(lazyProvider.isAvailable)
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(observedStates, [.inactive, .active])

        observation.cancel()
    }

    func testLazyProviderKeepsRetiredProfileFailClosedWithoutEagerCreation() {
        var creationCount = 0
        var underlyingProvider: FakeSumiGeolocationProvider?
        let lazyProvider = SumiLazyGeolocationProvider {
            creationCount += 1
            let provider = FakeSumiGeolocationProvider()
            underlyingProvider = provider
            return provider
        }

        lazyProvider.retireProfile(profilePartitionId: " Profile-A ")
        lazyProvider.registerAllowedRequest(
            pageId: "retired-page",
            tabId: "retired-tab",
            profilePartitionId: "PROFILE-A"
        )

        XCTAssertEqual(creationCount, 0)

        lazyProvider.registerAllowedRequest(
            pageId: "retained-page",
            tabId: "retained-tab",
            profilePartitionId: "profile-b"
        )

        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(
            underlyingProvider?.registeredRequests.map(\.pageId),
            ["retained-page"]
        )

        lazyProvider.retireProfile(profilePartitionId: "PROFILE-B")
        lazyProvider.registerAllowedRequest(
            pageId: "late-page",
            tabId: "late-tab",
            profilePartitionId: "profile-b"
        )

        XCTAssertEqual(
            underlyingProvider?.cancelledProfilePartitionIds,
            ["profile-b"]
        )
        XCTAssertTrue(underlyingProvider?.registeredRequests.isEmpty == true)
    }

    func testApplicationLifecycleControllerPausesActiveGeolocationWhileApplicationInactive() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        let browserManager = BrowserManager(geolocationProvider: provider)
        let controller = BrowserApplicationLifecycleController(
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            }
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
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(reason: reason)
            },
            pauseGeolocationOnAppBackgroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.pauseGeolocationOnAppBackgroundIfNeeded()
            },
            resumeGeolocationOnAppForegroundIfNeeded: { [weak browserManager] in
                browserManager?.permissionRuntime.resumeGeolocationOnAppForegroundIfNeeded()
            }
        )

        controller.handleApplicationWillResignActive()
        controller.handleApplicationDidBecomeActive()

        XCTAssertEqual(provider.currentState, .paused)
        XCTAssertEqual(provider.pauseCallCount, 0)
        XCTAssertEqual(provider.resumeCallCount, 0)
    }
}
