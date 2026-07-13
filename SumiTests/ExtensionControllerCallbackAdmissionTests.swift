import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerCallbackAdmissionTests: XCTestCase {
    func testCaptureProducesCurrentExactEvidence() async throws {
        let harness = try await makeHarness()

        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        XCTAssertIdentical(evidence.context, harness.context)
        XCTAssertIdentical(evidence.controller, harness.controller)
        XCTAssertEqual(evidence.profileID, harness.profileID)
        XCTAssertEqual(evidence.extensionID, harness.extensionID)
        XCTAssertEqual(evidence.controllerBindingRevision, 1)
        XCTAssertEqual(evidence.contextBindingRevision, 1)
        XCTAssertEqual(
            evidence.extensionLoadRevision,
            harness.extensionLoadRevisions.issue()
        )
        XCTAssertTrue(harness.admission.isCurrent(evidence))
    }

    func testContextReplacementRejectsCapturedEvidenceAndOldContext()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        let replacement = WKWebExtensionContext(
            for: harness.context.webExtension
        )

        _ = harness.profileRuntime.setContext(
            replacement,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        XCTAssertNil(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        XCTAssertNotNil(
            harness.admission.capture(
                context: replacement,
                controller: harness.controller
            )
        )
    }

    func testSameContextRebindingInvalidatesCapturedGeneration()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        _ = harness.profileRuntime.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        let rebound = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        XCTAssertEqual(rebound.contextBindingRevision, 2)
        XCTAssertTrue(harness.admission.isCurrent(rebound))
    }

    func testUnrelatedExtensionRebindingDoesNotInvalidateEvidence()
        async throws {
        let harness = try await makeHarness()
        let priorProfileGeneration = harness.profileRuntime
            .contextBindingGeneration(for: harness.profileID)
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        let unrelated = WKWebExtensionContext(
            for: harness.context.webExtension
        )

        _ = harness.profileRuntime.setContext(
            unrelated,
            extensionId: "unrelated-extension",
            profileId: harness.profileID
        )
        _ = harness.profileRuntime.setContext(
            unrelated,
            extensionId: "unrelated-extension",
            profileId: harness.profileID
        )

        XCTAssertGreaterThan(
            harness.profileRuntime.contextBindingGeneration(
                for: harness.profileID
            ),
            priorProfileGeneration
        )
        XCTAssertEqual(
            harness.profileRuntime.contextBindingRevision(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ),
            1
        )
        XCTAssertTrue(harness.admission.isCurrent(evidence))
    }

    func testRemoveAndReaddSameContextCannotRecreateOldEvidence()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        XCTAssertNotNil(
            harness.profileRuntime.removeContext(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            )
        )
        XCTAssertFalse(harness.admission.isCurrent(evidence))
        _ = harness.profileRuntime.setContext(
            harness.context,
            extensionId: harness.extensionID,
            profileId: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        let rebound = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        XCTAssertEqual(rebound.contextBindingRevision, 3)
        XCTAssertTrue(harness.admission.isCurrent(rebound))
    }

    func testBulkContextClearInvalidatesEvidenceWithoutRuntimeEpochChange()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        harness.profileRuntime.replaceContexts([:])

        XCTAssertEqual(
            harness.extensionLoadRevisions.issue(),
            evidence.extensionLoadRevision
        )
        XCTAssertFalse(harness.admission.isCurrent(evidence))
        XCTAssertEqual(
            harness.profileRuntime.contextBindingRevision(
                extensionId: harness.extensionID,
                profileId: harness.profileID
            ),
            2
        )
    }

    func testControllerReplacementRejectsOldControllerEvidence()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        let replacement = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        harness.profileRuntime.setController(
            replacement,
            for: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        XCTAssertNil(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        XCTAssertNotNil(
            harness.admission.capture(
                context: harness.context,
                controller: replacement
            )
        )
    }

    func testControllerABAReplacementCannotReviveOldEvidence() async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        let replacement = WKWebExtensionController(
            configuration: .nonPersistent()
        )

        harness.profileRuntime.setController(
            replacement,
            for: harness.profileID
        )
        harness.profileRuntime.setController(
            harness.controller,
            for: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        let rebound = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
        XCTAssertEqual(rebound.controllerBindingRevision, 3)
        XCTAssertTrue(harness.admission.isCurrent(rebound))
    }

    func testSameControllerRebindingInvalidatesEvidence() async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        harness.profileRuntime.setController(
            harness.controller,
            for: harness.profileID
        )

        XCTAssertFalse(harness.admission.isCurrent(evidence))
    }

    func testBulkControllerClearAndReaddCannotReviveEvidence() async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        harness.profileRuntime.replaceControllers([:])
        harness.profileRuntime.replaceControllers([
            harness.profileID: harness.controller,
        ])

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        XCTAssertEqual(
            harness.profileRuntime.controllerBindingRevision(
                for: harness.profileID
            ),
            3
        )
    }

    func testAmbiguousContextBindingIsRejected() async throws {
        let harness = try await makeHarness()
        _ = harness.profileRuntime.setContext(
            harness.context,
            extensionId: "duplicate-binding",
            profileId: harness.profileID
        )

        XCTAssertNil(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )
    }

    func testExtensionLoadGenerationChangeRejectsCapturedEvidence()
        async throws {
        let harness = try await makeHarness()
        let evidence = try XCTUnwrap(
            harness.admission.capture(
                context: harness.context,
                controller: harness.controller
            )
        )

        harness.extensionLoadRevisions.advance()

        XCTAssertFalse(harness.admission.isCurrent(evidence))
        XCTAssertTrue(
            harness.admission.isCurrent(
                try XCTUnwrap(
                    harness.admission.capture(
                        context: harness.context,
                        controller: harness.controller
                    )
                )
            )
        )
    }

    private struct Harness {
        let profileRuntime: ExtensionProfileRuntime
        let extensionLoadRevisions: ExtensionLoadRevisionAuthority
        let admission: ExtensionControllerCallbackAdmission
        let profileID: UUID
        let extensionID: String
        let context: WKWebExtensionContext
        let controller: WKWebExtensionController
    }

    private func makeHarness() async throws -> Harness {
        let profileID = UUID()
        let extensionID = "callback-admission"
        let context = try await makeExtensionContext()
        let controller = WKWebExtensionController(
            configuration: .nonPersistent()
        )
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        profileRuntime.setController(controller, for: profileID)
        _ = profileRuntime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let extensionLoadRevisions = ExtensionLoadRevisionAuthority()
        return Harness(
            profileRuntime: profileRuntime,
            extensionLoadRevisions: extensionLoadRevisions,
            admission: ExtensionControllerCallbackAdmission(
                profileRuntime: profileRuntime,
                extensionLoadRevisions: extensionLoadRevisions
            ),
            profileID: profileID,
            extensionID: extensionID,
            context: context,
            controller: controller
        )
    }

    private func makeExtensionContext() async throws
        -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Callback Admission",
            "version": "1.0",
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let webExtension = try await WKWebExtension(
            resourceBaseURL: directory
        )
        return WKWebExtensionContext(for: webExtension)
    }
}
