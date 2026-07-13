import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupBindingRecoveryTests: XCTestCase {
    func testSuccessfulRecoveryRequiresFreshPhysicalContextBinding() async throws {
        let fixture = try await makeFixture()
        let freshContext = WKWebExtensionContext(
            for: fixture.oldContext.webExtension
        )
        addTeardownBlock {
            if fixture.controller.extensionContexts.contains(where: {
                $0 === freshContext
            }) {
                try fixture.controller.unload(freshContext)
            }
        }
        let retirement = RetirementStub(outcome: .retired)
        let loader = ContextLoaderStub(
            profileRuntime: fixture.profileRuntime,
            controller: fixture.controller,
            context: freshContext
        )
        let recovery = ExtensionActionPopupBindingRecovery(
            contextRetirement: retirement,
            contextLoading: loader,
            profileRuntime: fixture.profileRuntime
        )

        let didRecover = await recovery.recover(fixture.oldReceipt)

        XCTAssertTrue(didRecover)
        XCTAssertEqual(retirement.receipts, [fixture.oldReceipt])
        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ],
            freshContext
        )
        XCTAssertIdentical(freshContext.webExtensionController, fixture.controller)
        XCTAssertTrue(
            fixture.controller.extensionContexts.contains(where: {
                $0 === freshContext
            })
        )
    }

    func testUnloadFailureKeepsRecoveryFailClosed() async throws {
        let fixture = try await makeFixture()
        let retirement = RetirementStub(outcome: .unloadFailed)
        let loader = ContextLoaderStub(
            profileRuntime: fixture.profileRuntime,
            controller: fixture.controller,
            context: WKWebExtensionContext(
                for: fixture.oldContext.webExtension
            ),
            loadIntoController: false
        )
        let recovery = ExtensionActionPopupBindingRecovery(
            contextRetirement: retirement,
            contextLoading: loader,
            profileRuntime: fixture.profileRuntime
        )

        let didRecover = await recovery.recover(fixture.oldReceipt)

        XCTAssertFalse(didRecover)
        XCTAssertEqual(loader.loadCount, 0)
        XCTAssertTrue(fixture.profileRuntime.isCurrent(fixture.oldReceipt))
    }

    func testFreshRuntimeReceiptWithoutPhysicalControllerLoadFailsClosed()
        async throws {
        let fixture = try await makeFixture()
        let freshContext = WKWebExtensionContext(
            for: fixture.oldContext.webExtension
        )
        let recovery = ExtensionActionPopupBindingRecovery(
            contextRetirement: RetirementStub(outcome: .retired),
            contextLoading: ContextLoaderStub(
                profileRuntime: fixture.profileRuntime,
                controller: fixture.controller,
                context: freshContext,
                loadIntoController: false
            ),
            profileRuntime: fixture.profileRuntime
        )

        let didRecover = await recovery.recover(fixture.oldReceipt)

        XCTAssertFalse(didRecover)
        XCTAssertNil(freshContext.webExtensionController)
        XCTAssertFalse(
            fixture.controller.extensionContexts.contains(where: {
                $0 === freshContext
            })
        )
    }

    func testSamePhysicalContextRebindIsNotFreshRecovery() async throws {
        let fixture = try await makeFixture()
        addTeardownBlock {
            if fixture.controller.extensionContexts.contains(where: {
                $0 === fixture.oldContext
            }) {
                try fixture.controller.unload(fixture.oldContext)
            }
        }
        let retirement = RetirementStub(outcome: .superseded)
        let loader = ContextLoaderStub(
            profileRuntime: fixture.profileRuntime,
            controller: fixture.controller,
            context: fixture.oldContext
        )
        let recovery = ExtensionActionPopupBindingRecovery(
            contextRetirement: retirement,
            contextLoading: loader,
            profileRuntime: fixture.profileRuntime
        )

        let didRecover = await recovery.recover(fixture.oldReceipt)

        XCTAssertFalse(didRecover)
        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertFalse(fixture.profileRuntime.isCurrent(fixture.oldReceipt))
    }

    private struct Fixture {
        let profileRuntime: ExtensionProfileRuntime
        let controller: WKWebExtensionController
        let profileID: UUID
        let extensionID: String
        let oldContext: WKWebExtensionContext
        let oldReceipt: ExtensionContextBindingReceipt
    }

    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "PopupRecovery",
            "version": "1.0",
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: directory.appendingPathComponent("manifest.json"))
        try Data("<!doctype html>".utf8)
            .write(to: directory.appendingPathComponent("popup.html"))

        let webExtension = try await WKWebExtension(
            resourceBaseURL: directory
        )
        let oldContext = WKWebExtensionContext(for: webExtension)
        let profileID = UUID()
        let extensionID = "popup-recovery"
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        let controller = WKWebExtensionController(configuration: .nonPersistent())
        profileRuntime.setController(controller, for: profileID)
        let receipt = profileRuntime.setContext(
            oldContext,
            extensionId: extensionID,
            profileId: profileID
        )
        return Fixture(
            profileRuntime: profileRuntime,
            controller: controller,
            profileID: profileID,
            extensionID: extensionID,
            oldContext: oldContext,
            oldReceipt: receipt
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RetirementStub: ExtensionExactContextRetiring {
    let outcome: ExtensionContextRetirement.Outcome
    private(set) var receipts: [ExtensionContextBindingReceipt] = []

    init(outcome: ExtensionContextRetirement.Outcome) {
        self.outcome = outcome
    }

    func retire(
        _ receipt: ExtensionContextBindingReceipt
    ) -> ExtensionContextRetirement.Outcome {
        receipts.append(receipt)
        return outcome
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ContextLoaderStub: ExtensionActionPopupContextLoading {
    private let profileRuntime: ExtensionProfileRuntime
    private let controller: WKWebExtensionController
    private let context: WKWebExtensionContext
    private let loadIntoController: Bool
    private(set) var loadCount = 0

    init(
        profileRuntime: ExtensionProfileRuntime,
        controller: WKWebExtensionController,
        context: WKWebExtensionContext,
        loadIntoController: Bool = true
    ) {
        self.profileRuntime = profileRuntime
        self.controller = controller
        self.context = context
        self.loadIntoController = loadIntoController
    }

    func ensureExtensionLoaded(
        extensionId: String,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        loadCount += 1
        if loadIntoController {
            try controller.load(context)
        }
        _ = profileRuntime.setContext(
            context,
            extensionId: extensionId,
            profileId: profileId
        )
        return context
    }
}
