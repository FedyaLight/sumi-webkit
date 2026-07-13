import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ControllerDelegateReadinessTests: XCTestCase {
    func testImmediateReadinessBindsInstalledController() {
        let profileID = UUID()
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        var bindings: [ExtensionControllerBindingSnapshot] = []
        let readiness = ExtensionControllerDelegateReadiness(
            profileRuntime: runtime,
            bind: { bindings.append($0) }
        )
        let receipt = runtime.setController(controller, for: profileID)

        readiness.controllerInstalled(receipt)

        XCTAssertTrue(readiness.controllerDidBecomeReady(receipt))
        XCTAssertEqual(bindings.count, 1)
        XCTAssertIdentical(bindings.first?.controller, controller)
    }

    func testDelayedReadinessDoesNotBindBeforeReadyEvent() {
        let profileID = UUID()
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        var bindings: [ExtensionControllerBindingSnapshot] = []
        let readiness = ExtensionControllerDelegateReadiness(
            profileRuntime: runtime,
            bind: { bindings.append($0) }
        )
        let receipt = runtime.setController(controller, for: profileID)

        readiness.controllerInstalled(receipt)

        XCTAssertTrue(bindings.isEmpty)
        XCTAssertTrue(readiness.controllerDidBecomeReady(receipt))
        XCTAssertIdentical(bindings.first?.controller, controller)
    }

    func testCancellationRejectsPendingReadiness() {
        let profileID = UUID()
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        var bindings: [ExtensionControllerBindingSnapshot] = []
        let readiness = ExtensionControllerDelegateReadiness(
            profileRuntime: runtime,
            bind: { bindings.append($0) }
        )
        let receipt = runtime.setController(controller, for: profileID)
        readiness.controllerInstalled(receipt)

        readiness.cancelAll()

        XCTAssertFalse(readiness.controllerDidBecomeReady(receipt))
        XCTAssertTrue(bindings.isEmpty)
    }

    func testNewControllerSupersedesPendingControllerForProfile() {
        let profileID = UUID()
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let firstController = makeController()
        let replacementController = makeController()
        var bindings: [ExtensionControllerBindingSnapshot] = []
        let readiness = ExtensionControllerDelegateReadiness(
            profileRuntime: runtime,
            bind: { bindings.append($0) }
        )
        let firstReceipt = runtime.setController(
            firstController,
            for: profileID
        )
        readiness.controllerInstalled(firstReceipt)
        let replacementReceipt = runtime.setController(
            replacementController,
            for: profileID
        )

        readiness.controllerInstalled(replacementReceipt)

        XCTAssertFalse(readiness.controllerDidBecomeReady(firstReceipt))
        XCTAssertTrue(readiness.controllerDidBecomeReady(replacementReceipt))
        XCTAssertEqual(bindings.count, 1)
        XCTAssertIdentical(bindings.first?.controller, replacementController)
    }

    func testControllerIdentityMismatchCannotCompletePendingReadiness() {
        let profileID = UUID()
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = makeController()
        let otherController = makeController()
        var bindings: [ExtensionControllerBindingSnapshot] = []
        let readiness = ExtensionControllerDelegateReadiness(
            profileRuntime: runtime,
            bind: { bindings.append($0) }
        )
        let receipt = runtime.setController(controller, for: profileID)
        readiness.controllerInstalled(receipt)
        let mismatchedReceipt = ExtensionControllerBindingSnapshot(
            profileID: profileID,
            controller: otherController,
            revision: receipt.revision
        )

        XCTAssertFalse(
            readiness.controllerDidBecomeReady(mismatchedReceipt)
        )
        XCTAssertTrue(readiness.controllerDidBecomeReady(receipt))
        XCTAssertEqual(bindings.count, 1)
        XCTAssertIdentical(bindings.first?.controller, controller)
    }

    private func makeController() -> WKWebExtensionController {
        WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
    }
}
