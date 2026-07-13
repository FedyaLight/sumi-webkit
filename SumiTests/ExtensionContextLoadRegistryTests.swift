import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextLoadRegistryTests: XCTestCase {
    func testNewClaimSupersedesPriorClaimForSameScopedKey() {
        let key = scopedKey(profileID: UUID(), extensionID: "extension")
        let registry = ExtensionContextLoadRegistry()

        let first = registry.begin(for: key)
        let second = registry.begin(for: key)

        XCTAssertFalse(registry.isCurrent(first))
        XCTAssertTrue(registry.isCurrent(second))
    }

    func testBeginIfIdleDoesNotSupersedeCurrentClaim() {
        let key = scopedKey(profileID: UUID(), extensionID: "extension")
        let registry = ExtensionContextLoadRegistry()
        let claim = registry.begin(for: key)

        XCTAssertNil(registry.beginIfIdle(for: key))
        XCTAssertTrue(registry.isCurrent(claim))
    }

    func testExtensionGlobalRollbackRejectsConcurrentOtherProfileClaim() {
        let registry = ExtensionContextLoadRegistry()
        let rollbackClaim = registry.begin(
            for: scopedKey(profileID: UUID(), extensionID: "extension")
        )
        let concurrentClaim = registry.begin(
            for: scopedKey(profileID: UUID(), extensionID: "extension")
        )

        XCTAssertFalse(
            registry.admitsExtensionGlobalRollback(rollbackClaim)
        )

        XCTAssertTrue(registry.finishIfCurrent(concurrentClaim))
        XCTAssertTrue(
            registry.admitsExtensionGlobalRollback(rollbackClaim)
        )
    }

    func testExtensionGlobalRollbackIgnoresOtherExtensionClaim() {
        let registry = ExtensionContextLoadRegistry()
        let rollbackClaim = registry.begin(
            for: scopedKey(profileID: UUID(), extensionID: "extension-a")
        )
        _ = registry.begin(
            for: scopedKey(profileID: UUID(), extensionID: "extension-b")
        )

        XCTAssertTrue(
            registry.admitsExtensionGlobalRollback(rollbackClaim)
        )
    }

    func testFinishingRequiresAndConsumesExactCurrentClaim() {
        let key = scopedKey(profileID: UUID(), extensionID: "extension")
        let registry = ExtensionContextLoadRegistry()
        let stale = registry.begin(for: key)
        let current = registry.begin(for: key)

        XCTAssertFalse(registry.finishIfCurrent(stale))
        XCTAssertTrue(registry.finishIfCurrent(current))
        XCTAssertFalse(registry.isCurrent(current))
    }

    func testScopedInvalidationDoesNotRevokeUnrelatedClaims() {
        let profileA = UUID()
        let profileB = UUID()
        let registry = ExtensionContextLoadRegistry()
        let extensionA = registry.begin(
            for: scopedKey(profileID: profileA, extensionID: "a")
        )
        let extensionAInOtherProfile = registry.begin(
            for: scopedKey(profileID: profileB, extensionID: "a")
        )
        let extensionB = registry.begin(
            for: scopedKey(profileID: profileA, extensionID: "b")
        )

        registry.invalidate(extensionId: "a")

        XCTAssertFalse(registry.isCurrent(extensionA))
        XCTAssertFalse(registry.isCurrent(extensionAInOtherProfile))
        XCTAssertTrue(registry.isCurrent(extensionB))

        registry.invalidate(profileIDs: [profileA])
        XCTAssertFalse(registry.isCurrent(extensionB))
    }

    func testExactKeyInvalidationPreservesSameExtensionInOtherProfile() {
        let profileA = UUID()
        let profileB = UUID()
        let registry = ExtensionContextLoadRegistry()
        let keyA = scopedKey(profileID: profileA, extensionID: "shared")
        let claimA = registry.begin(for: keyA)
        let claimB = registry.begin(
            for: scopedKey(profileID: profileB, extensionID: "shared")
        )

        registry.invalidate(keyA)

        XCTAssertFalse(registry.isCurrent(claimA))
        XCTAssertTrue(registry.isCurrent(claimB))
    }

    func testInvalidatingSelectedProfilesPreservesOtherProfiles() {
        let profileA = UUID()
        let profileB = UUID()
        let profileC = UUID()
        let registry = ExtensionContextLoadRegistry()
        let claimA = registry.begin(
            for: scopedKey(profileID: profileA, extensionID: "a")
        )
        let claimB = registry.begin(
            for: scopedKey(profileID: profileB, extensionID: "b")
        )
        let claimC = registry.begin(
            for: scopedKey(profileID: profileC, extensionID: "c")
        )

        registry.invalidate(profileIDs: [profileA, profileB])

        XCTAssertFalse(registry.isCurrent(claimA))
        XCTAssertFalse(registry.isCurrent(claimB))
        XCTAssertTrue(registry.isCurrent(claimC))

        registry.invalidateAll()
        XCTAssertFalse(registry.isCurrent(claimC))
    }

    func testExactBindingReceiptRemovesOnlyCapturedContext() async throws {
        let context = try await makeExtensionContext()
        let profileID = UUID()
        let extensionID = "bound-extension"
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let receipt = try XCTUnwrap(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )

        let removal = try XCTUnwrap(runtime.removeContext(ifCurrent: receipt))

        XCTAssertIdentical(removal.context, context)
        XCTAssertEqual(removal.generation, 2)
        XCTAssertNil(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )
        XCTAssertFalse(runtime.isCurrent(receipt))
    }

    func testReplacementRejectsStaleBindingReceiptWithoutRemovingReplacement()
        async throws {
        let context = try await makeExtensionContext()
        let replacement = WKWebExtensionContext(for: context.webExtension)
        let profileID = UUID()
        let extensionID = "bound-extension"
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let receipt = try XCTUnwrap(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )
        _ = runtime.setContext(
            replacement,
            extensionId: extensionID,
            profileId: profileID
        )

        XCTAssertNil(runtime.removeContext(ifCurrent: receipt))
        XCTAssertIdentical(
            runtime.contexts(for: profileID)[extensionID],
            replacement
        )
    }

    func testSameObjectRebindingAndABARejectOldBindingReceipt() async throws {
        let context = try await makeExtensionContext()
        let replacement = WKWebExtensionContext(for: context.webExtension)
        let profileID = UUID()
        let extensionID = "bound-extension"
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let firstReceipt = try XCTUnwrap(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )

        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        XCTAssertNil(runtime.removeContext(ifCurrent: firstReceipt))

        let reboundReceipt = try XCTUnwrap(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )
        _ = runtime.setContext(
            replacement,
            extensionId: extensionID,
            profileId: profileID
        )
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )

        XCTAssertNil(runtime.removeContext(ifCurrent: reboundReceipt))
        XCTAssertIdentical(
            runtime.contexts(for: profileID)[extensionID],
            context
        )
    }

    func testControllerReplacementAndABARejectOldBindingReceipt() async throws {
        let context = try await makeExtensionContext()
        let profileID = UUID()
        let extensionID = "controller-bound-extension"
        let runtime = ExtensionProfileRuntime(initialProfileId: profileID)
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let replacement = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        runtime.setController(controller, for: profileID)
        _ = runtime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let receipt = try XCTUnwrap(
            runtime.contextBindingReceipt(
                extensionId: extensionID,
                profileId: profileID
            )
        )

        runtime.setController(replacement, for: profileID)
        runtime.setController(controller, for: profileID)

        XCTAssertFalse(runtime.isCurrent(receipt))
        XCTAssertNil(runtime.context(ifCurrent: receipt))
        XCTAssertNil(runtime.controller(ifCurrent: receipt))
        XCTAssertNil(runtime.removeContext(ifCurrent: receipt))
        XCTAssertIdentical(
            runtime.contexts(for: profileID)[extensionID],
            context
        )
    }

    private func scopedKey(
        profileID: UUID,
        extensionID: String
    ) -> ExtensionRuntimeResidencyState.ScopedKey {
        .init(profileId: profileID, extensionId: extensionID)
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
            try FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Context Load Authority",
            "version": "1.0",
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let extensionRuntime = try await WKWebExtension(
            resourceBaseURL: directory
        )
        return WKWebExtensionContext(for: extensionRuntime)
    }
}
