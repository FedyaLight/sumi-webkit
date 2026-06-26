import XCTest

@testable import Sumi

final class ExtensionRuntimeReadinessContextTests: XCTestCase {
    func testProfileReadinessTracksMissingEnabledContexts() {
        let readiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["beta", "alpha"],
            loadedExtensionStatesByID: ["alpha": true],
            controllerExists: true,
            globalRuntimeReady: false
        )

        XCTAssertEqual(readiness.missingEnabledExtensionIDs, ["beta"])
        XCTAssertFalse(readiness.isProfileReady)
        XCTAssertFalse(readiness.canUseExistingRuntime(extensionID: nil))
    }

    func testProfileReadinessCountsCreatedContextBeforeExtensionLoaded() {
        let readiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["alpha"],
            loadedExtensionStatesByID: ["alpha": false],
            controllerExists: true,
            globalRuntimeReady: false
        )

        XCTAssertTrue(readiness.isProfileReady)
        XCTAssertTrue(readiness.canUseExistingRuntime(extensionID: nil))
        XCTAssertFalse(readiness.isExtensionReady(extensionID: "alpha"))
        XCTAssertFalse(readiness.canUseExistingRuntime(extensionID: "alpha"))
    }

    func testPostRequestReadinessAndFallbackStayProfileScoped() {
        let loadingReadiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["alpha"],
            loadedExtensionStatesByID: [:],
            controllerExists: true,
            globalRuntimeReady: false
        )
        let readyReadiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["alpha"],
            loadedExtensionStatesByID: [:],
            controllerExists: true,
            globalRuntimeReady: true
        )

        XCTAssertFalse(loadingReadiness.isReadyAfterRuntimeRequest(extensionID: nil))
        XCTAssertFalse(loadingReadiness.allowsReadyControllerFallback(extensionID: nil))
        XCTAssertTrue(readyReadiness.allowsReadyControllerFallback(extensionID: nil))
        XCTAssertFalse(readyReadiness.allowsReadyControllerFallback(extensionID: "alpha"))
    }

    func testMissingDiagnosticsSurviveWhenNoRuntimeDemandExists() {
        let readiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: false,
            enabledExtensionIDs: ["persisted-only"],
            loadedExtensionStatesByID: [:],
            controllerExists: false,
            globalRuntimeReady: false
        )

        XCTAssertEqual(readiness.missingEnabledExtensionIDs, ["persisted-only"])
        XCTAssertTrue(readiness.isProfileReady)
        XCTAssertFalse(readiness.canUseExistingRuntime(extensionID: nil))
    }
}
