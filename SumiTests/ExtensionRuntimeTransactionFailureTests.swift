import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeTransactionFailureTests:
    SafariExtensionWebViewControllerWiringTestCase {
    private enum InjectedFailure: Error {
        case beforeControllerLoad
    }

    func testReentrantPolicyPublicationStopsBeforeStorageMutation()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Policy Reentrancy")
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        defer {
            manager.clearDebugState()
            _ = manager.shutDownExtensionRuntime(
                reason: "ExtensionRuntimeTransactionFailureTests"
            )
        }
        let extensionID = "policy-reentrant-\(UUID().uuidString)"
        let directory = try makeScratchDirectory()
            .appendingPathComponent(extensionID, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Policy Reentrancy",
            "version": "1.0",
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profile.id,
            extensionId: extensionID
        )
        let claim = manager.contextLoadRegistry.begin(for: key)
        let preparation = ExtensionContextPreparation(
            siteAccessPolicyStore: manager.siteAccessPolicyStore,
            capabilities: manager.installCapabilityOwner,
            installedExtensions: manager.installedExtensionCollection,
            permissionDecisions: manager.permissionDecisionStore,
            siteAccessPolicyDidPersist: {
                manager.contextLoadRegistry.invalidate(key)
            }
        )
        let transaction = ExtensionContextControllerTransaction(
            authority: manager.loadedContextAuthority,
            profileRuntime: manager.profileRuntime,
            rollback: manager.runtimeRollback,
            errorObservation: manager.contextErrorObservation,
            runtimeSession: manager.runtimeSession,
            diagnostics: manager.runtimeDiagnostics,
            expectedControllerDelegate: manager.controllerDelegateBridge,
            debugBeforeControllerLoad: { nil }
        )
        let loader = ExtensionContextLoader(
            authority: manager.loadedContextAuthority,
            profileRuntime: manager.profileRuntime,
            controllerProvisioning: manager.controllerProvisioningOwner,
            waitForWebsiteDataMutationAdmission: { _ in true },
            sourceCache: manager.webExtensionRuntimeSourceCache,
            contextPreparation: preparation,
            storagePlanner: manager.webExtensionStorageCleanupPlanner,
            runtimeSession: manager.runtimeSession,
            diagnostics: manager.runtimeDiagnostics,
            expectedControllerDelegate: manager.controllerDelegateBridge,
            controllerTransaction: transaction
        )

        do {
            _ = try await loader.load(
                .init(
                    extensionId: extensionID,
                    profileId: profile.id,
                    sourceKind: .directory,
                    sourceBundlePath: directory.path,
                    packageRoot: directory,
                    manifest: manifest,
                    operation: .install,
                    claim: claim,
                    mutationLease: nil
                )
            )
            XCTFail("Reentrant policy publication must revoke the stale load")
        } catch {
            XCTAssertTrue(error is CancellationError, String(describing: error))
        }

        let controller = try XCTUnwrap(
            manager.profileRuntime.controller(for: profile.id)
        )
        let runtimeIdentifier = ExtensionContextPreparation.runtimeIdentifier(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: directory.path
        )
        let storage = WebExtensionStorageCleanupStore(
            controllerStorageId: controller.configuration.identifier,
            planner: manager.webExtensionStorageCleanupPlanner,
            storageDirectoryNameResolver: { _ in runtimeIdentifier }
        )
        XCTAssertFalse(storage.snapshot(for: extensionID).directoryExists)
        XCTAssertNil(
            manager.profileRuntime.contexts(for: profile.id)[extensionID]
        )
    }

    func testReplacementBindingPropagatesExternalPreservationAuthority()
        async throws {
        let fixture = try await makeLoadFixture(name: "ReplacementAuthority")
        defer { fixture.cleanUp() }
        var replacement: WKWebExtensionContext?
        fixture.manager.testHooks.beforeControllerLoad = { extensionID, _ in
            let current = try XCTUnwrap(
                fixture.manager.profileRuntime.contexts(
                    for: fixture.profile.id
                )[extensionID]
            )
            let context = WKWebExtensionContext(for: current.webExtension)
            replacement = context
            _ = fixture.manager.setExtensionContext(
                context,
                extensionId: extensionID,
                profileId: fixture.profile.id
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.manager.extensionRuntimeLoader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForReplacement
        )
        XCTAssertIdentical(
            fixture.manager.profileRuntime.contexts(for: fixture.profile.id)[
                fixture.installed.id
            ],
            replacement
        )
    }

    func testSiblingBindingPropagatesActiveBindingPreservationAuthority()
        async throws {
        let fixture = try await makeLoadFixture(name: "SiblingAuthority")
        defer { fixture.cleanUp() }
        let siblingProfileID = UUID()
        _ = fixture.manager.ensureExtensionController(for: siblingProfileID)
        var sibling: WKWebExtensionContext?
        fixture.manager.testHooks.beforeControllerLoad = { extensionID, _ in
            let current = try XCTUnwrap(
                fixture.manager.profileRuntime.contexts(
                    for: fixture.profile.id
                )[extensionID]
            )
            let context = WKWebExtensionContext(for: current.webExtension)
            sibling = context
            _ = fixture.manager.setExtensionContext(
                context,
                extensionId: extensionID,
                profileId: siblingProfileID
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.manager.extensionRuntimeLoader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForActiveBinding
        )
        XCTAssertIdentical(
            fixture.manager.profileRuntime.contexts(for: siblingProfileID)[
                fixture.installed.id
            ],
            sibling
        )
    }

    func testCompetingMutationPropagatesTransactionPreservationAuthority()
        async throws {
        let fixture = try await makeLoadFixture(name: "CompetingAuthority")
        defer { fixture.cleanUp() }
        var competingLease: ExtensionRuntimeMutationLease?
        fixture.manager.testHooks.beforeControllerLoad = { extensionID, _ in
            competingLease = try XCTUnwrap(
                fixture.manager.runtimeMutationRegistry.begin(
                    extensionID: extensionID,
                    operation: .install
                )
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.manager.extensionRuntimeLoader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForCompetingTransaction
        )
        XCTAssertTrue(
            fixture.manager.runtimeMutationRegistry.finish(
                try XCTUnwrap(competingLease)
            )
        )
        competingLease = nil
    }

    private func makeLoadFixture(name: String) async throws -> LoadFixture {
        let container = try makeTestContainer()
        let profile = Profile(name: name)
        let manager = makeManager(
            context: container.mainContext,
            profile: profile
        ).manager
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: try makeScratchDirectory(),
            name: name
        )
        let entity = try XCTUnwrap(
            try manager.extensionEntity(for: installed.id)
        )
        entity.isEnabled = true
        try container.mainContext.save()
        _ = manager.ensureExtensionController(for: profile.id)
        return LoadFixture(
            container: container,
            manager: manager,
            profile: profile,
            installed: installed,
            entity: entity
        )
    }

    private func captureTransactionFailure(
        _ operation: () async throws -> Void
    ) async throws -> ExtensionRuntimeTransactionFailure {
        do {
            try await operation()
            XCTFail("The superseded runtime transaction must fail")
            throw InjectedFailure.beforeControllerLoad
        } catch let failure as ExtensionRuntimeTransactionFailure {
            return failure
        } catch {
            XCTFail("Expected typed runtime transaction failure, got \(error)")
            throw error
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private struct LoadFixture {
    let container: ModelContainer
    let manager: ExtensionManager
    let profile: Profile
    let installed: InstalledExtension
    let entity: ExtensionEntity

    func cleanUp() {
        manager.testHooks.beforeControllerLoad = nil
        manager.clearDebugState()
        _ = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeTransactionFailureTests"
        )
        _ = container
    }
}
