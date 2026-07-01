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

    func testProfileReadinessRequiresCreatedContextToFinishLoading() {
        let readiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["alpha"],
            loadedExtensionStatesByID: ["alpha": false],
            controllerExists: true,
            globalRuntimeReady: false
        )

        XCTAssertTrue(readiness.missingEnabledExtensionIDs.isEmpty)
        XCTAssertEqual(readiness.unloadedEnabledExtensionIDs, ["alpha"])
        XCTAssertFalse(readiness.isProfileReady)
        XCTAssertFalse(readiness.canUseExistingRuntime(extensionID: nil))
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
        XCTAssertFalse(readyReadiness.allowsReadyControllerFallback(extensionID: nil))
        XCTAssertFalse(readyReadiness.allowsReadyControllerFallback(extensionID: "alpha"))
    }

    func testReadyControllerFallbackRequiresLoadedProfileContexts() {
        let readiness = ExtensionRuntimeReadinessContext(
            hasEnabledExtensionDemand: true,
            enabledExtensionIDs: ["alpha"],
            loadedExtensionStatesByID: ["alpha": true],
            controllerExists: true,
            globalRuntimeReady: true
        )

        XCTAssertTrue(readiness.isProfileReady)
        XCTAssertTrue(readiness.allowsReadyControllerFallback(extensionID: nil))
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
