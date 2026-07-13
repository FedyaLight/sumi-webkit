import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextRetirementTests: XCTestCase {
    private enum TestError: Error {
        case unloadFailed
    }

    func testSuccessfulUnloadRemovesExactBinding() async throws {
        let fixture = try await makeFixture()
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        var unloadedContext: WKWebExtensionContext?
        let retirement = fixture.retirement { _, context in
            unloadedContext = context
        }

        XCTAssertEqual(retirement.retire(receipt), .retired)
        XCTAssertIdentical(unloadedContext, fixture.context)
        XCTAssertNil(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ]
        )
    }

    func testBoundContextNotYetLoadedRetiresWithoutCallingUnload()
        async throws {
        let fixture = try await makeFixture(loadIntoController: false)
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let retirement = fixture.retirement { _, _ in
            XCTFail("WebKit unload must not run for a staged context")
        }

        XCTAssertEqual(retirement.retire(receipt), .retired)
        XCTAssertNil(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ]
        )
    }

    func testUnloadFailurePreservesAuthoritativeBinding() async throws {
        let fixture = try await makeFixture()
        let wakeKey = ExtensionRuntimeResidencyState.scopedKey(
            extensionId: fixture.extensionID,
            profileId: fixture.profileID
        )
        _ = try await fixture.backgroundState
            .ensureBackgroundAvailableIfRequired(
                wakeKey: wakeKey,
                hasBackgroundContent: true,
                reason: .enable,
                trace: { _ in },
                loadBackgroundContent: {},
                recordWakeMetric: { _, _, _ in }
            )
        XCTAssertEqual(fixture.backgroundState.state(for: wakeKey), .loaded)
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let retirement = fixture.retirement { _, _ in
            throw TestError.unloadFailed
        }

        XCTAssertEqual(retirement.retire(receipt), .unloadFailed)
        XCTAssertTrue(fixture.profileRuntime.isCurrent(receipt))
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ],
            fixture.context
        )
        XCTAssertEqual(
            fixture.backgroundState.state(for: wakeKey),
            .loaded,
            "failed unload must preserve readiness for the still-bound context"
        )
    }

    func testNotBoundAndUnavailableControllerAreDistinctOutcomes()
        async throws {
        let fixture = try await makeFixture()
        let retirement = fixture.retirement { _, _ in
            XCTFail("unload must not run without an exact controller binding")
        }

        XCTAssertEqual(
            retirement.retireCurrent(
                extensionId: "missing",
                profileId: fixture.profileID
            ),
            .notBound
        )
        fixture.profileRuntime.replaceControllers([:])
        XCTAssertEqual(
            retirement.retireCurrent(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            ),
            .controllerUnavailable
        )
    }

    func testRollbackUnloadsExactOldContextWithoutRemovingReplacement()
        async throws {
        let fixture = try await makeFixture()
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let controller = try XCTUnwrap(
            fixture.profileRuntime.controller(for: fixture.profileID)
        )
        let replacement = WKWebExtensionContext(
            for: fixture.context.webExtension
        )
        _ = fixture.profileRuntime.setContext(
            replacement,
            extensionId: fixture.extensionID,
            profileId: fixture.profileID
        )
        var unloadedContext: WKWebExtensionContext?
        let retirement = fixture.retirement { _, context in
            unloadedContext = context
        }

        XCTAssertEqual(
            retirement.rollbackLoad(
                context: fixture.context,
                controller: controller,
                receipt: receipt
            ),
            .superseded
        )
        XCTAssertIdentical(unloadedContext, fixture.context)
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ],
            replacement
        )
    }

    func testExactRollbackReportsReplacementSeparatelyFromUnloadFailure()
        async throws {
        let fixture = try await makeFixture()
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let controller = try XCTUnwrap(
            fixture.profileRuntime.controller(for: fixture.profileID)
        )
        let replacement = WKWebExtensionContext(
            for: fixture.context.webExtension
        )
        _ = fixture.profileRuntime.setContext(
            replacement,
            extensionId: fixture.extensionID,
            profileId: fixture.profileID
        )
        let authority = ExtensionLoadedContextAuthority(
            profileRuntime: fixture.profileRuntime,
            mutationRegistry: ExtensionRuntimeMutationRegistry(),
            loadRegistry: ExtensionContextLoadRegistry(),
            contextRetirement: fixture.retirement { controller, context in
                try controller.unload(context)
            }
        )

        let result = authority.rollback(
            context: fixture.context,
            controller: controller,
            receipt: receipt
        )

        XCTAssertEqual(result.outcome, .superseded)
        XCTAssertEqual(result.exactDisposition, .replacementPresent)
        XCTAssertTrue(result.exactRollbackCompleted)
        XCTAssertEqual(result.sharedCleanupDisposition, .notAttempted)
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveForReplacement
        )
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ],
            replacement
        )
    }

    func testExactRollbackReportsContextStillLoadedAfterUnloadFailure()
        async throws {
        let fixture = try await makeFixture()
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let controller = try XCTUnwrap(
            fixture.profileRuntime.controller(for: fixture.profileID)
        )
        let authority = ExtensionLoadedContextAuthority(
            profileRuntime: fixture.profileRuntime,
            mutationRegistry: ExtensionRuntimeMutationRegistry(),
            loadRegistry: ExtensionContextLoadRegistry(),
            contextRetirement: fixture.retirement { _, _ in
                throw TestError.unloadFailed
            }
        )

        let result = authority.rollback(
            context: fixture.context,
            controller: controller,
            receipt: receipt
        )

        XCTAssertEqual(result.outcome, .unloadFailed)
        XCTAssertEqual(result.exactDisposition, .exactContextStillLoaded)
        XCTAssertFalse(result.exactRollbackCompleted)
        XCTAssertEqual(result.sharedCleanupDisposition, .notAttempted)
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveForExactRuntime
        )
    }

    func testExactRetirementRequiresSharedCleanupBeforeExternalRollback()
        async throws {
        let fixture = try await makeFixture(loadIntoController: false)
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let controller = try XCTUnwrap(
            fixture.profileRuntime.controller(for: fixture.profileID)
        )
        let authority = ExtensionLoadedContextAuthority(
            profileRuntime: fixture.profileRuntime,
            mutationRegistry: ExtensionRuntimeMutationRegistry(),
            loadRegistry: ExtensionContextLoadRegistry(),
            contextRetirement: fixture.retirement { _, _ in }
        )

        let result = authority.rollback(
            context: fixture.context,
            controller: controller,
            receipt: receipt
        )

        XCTAssertEqual(result.exactDisposition, .retired)
        XCTAssertEqual(result.sharedCleanupDisposition, .notAttempted)
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveUntilSharedCleanup
        )
    }

    func testReentrantRetirementDoesNotUnloadSameBindingTwice()
        async throws {
        let fixture = try await makeFixture()
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        var retirement: ExtensionContextRetirement!
        var nestedOutcome: ExtensionContextRetirement.Outcome?
        var unloadCount = 0
        retirement = fixture.retirement { _, _ in
            unloadCount += 1
            nestedOutcome = retirement.retire(receipt)
        }

        XCTAssertEqual(retirement.retire(receipt), .retired)
        XCTAssertEqual(nestedOutcome, .retirementInProgress)
        XCTAssertEqual(unloadCount, 1)
    }

    func testReentrantReplacementDuringUnloadSurvivesOldRetirement()
        async throws {
        let fixture = try await makeFixture()
        let replacement = WKWebExtensionContext(
            for: fixture.context.webExtension
        )
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        )
        let retirement = fixture.retirement { _, _ in
            _ = fixture.profileRuntime.setContext(
                replacement,
                extensionId: fixture.extensionID,
                profileId: fixture.profileID
            )
        }

        XCTAssertEqual(retirement.retire(receipt), .superseded)
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: fixture.profileID)[
                fixture.extensionID
            ],
            replacement
        )
    }

    private func makeFixture(
        loadIntoController: Bool = true
    ) async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Context Retirement",
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let webExtension = try await WKWebExtension(
            resourceBaseURL: directory
        )
        let context = WKWebExtensionContext(for: webExtension)
        let profileID = UUID()
        let extensionID = "retirement-extension"
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        profileRuntime.setController(controller, for: profileID)
        _ = profileRuntime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        if loadIntoController {
            try controller.load(context)
        }
        return Fixture(
            profileID: profileID,
            extensionID: extensionID,
            context: context,
            profileRuntime: profileRuntime,
            backgroundState: ExtensionBackgroundRuntimeStateOwner(),
            runtimeResidency: ExtensionRuntimeResidencyAuthority(),
            errorObservation: ExtensionContextErrorObservation(
                recordErrorUpdateDuration: { _, _ in },
                trace: { _ in }
            ),
            diagnostics: ExtensionRuntimeDiagnostics()
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private struct Fixture {
    let profileID: UUID
    let extensionID: String
    let context: WKWebExtensionContext
    let profileRuntime: ExtensionProfileRuntime
    let backgroundState: ExtensionBackgroundRuntimeStateOwner
    let runtimeResidency: ExtensionRuntimeResidencyAuthority
    let errorObservation: ExtensionContextErrorObservation
    let diagnostics: ExtensionRuntimeDiagnostics

    func retirement(
        unload: @escaping @MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) throws -> Void
    ) -> ExtensionContextRetirement {
        ExtensionContextRetirement(
            profileRuntime: profileRuntime,
            backgroundRuntimeState: backgroundState,
            runtimeResidency: runtimeResidency,
            errorObservation: errorObservation,
            diagnostics: diagnostics,
            unloadContext: unload
        )
    }
}
