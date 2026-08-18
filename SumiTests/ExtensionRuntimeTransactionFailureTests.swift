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

    func testSuccessfulWebKitLoadConsumesDelegateReceiptOnce()
        async throws {
        let fixture = try await makeLoadFixture(name: "DelegateReadiness")
        defer { fixture.cleanUp() }
        let controller = try XCTUnwrap(
            fixture.inspection.contextState.profiles.controller(for: fixture.profile.id)
        )
        let controllerBinding = try XCTUnwrap(
            fixture.inspection.contextState.profiles.controllerBindingSnapshot(
                for: fixture.profile.id
            )
        )

        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(
            fixture.inspection.contextState.profiles.contexts(
                for: fixture.profile.id
            ).isEmpty
        )
        XCTAssertIdentical(
            controller.delegate,
            fixture.inspection.controller.delegateBridge
        )

        var reachedControllerLoadBoundary = false
        controller.delegate = nil
        fixture.manager.testHooks.beforeControllerLoad = { _ in
            reachedControllerLoadBoundary = true
            XCTAssertNil(controller.delegate)
            XCTAssertTrue(controller.extensionContexts.isEmpty)
        }

        _ = try await fixture.inspection.contextCoordination.loader.loadEnabled(
            from: fixture.entity
        )

        XCTAssertTrue(reachedControllerLoadBoundary)
        let context = try XCTUnwrap(
            fixture.inspection.contextState.profiles.contexts(
                for: fixture.profile.id
            )[fixture.installed.id]
        )
        XCTAssertTrue(
            controller.extensionContexts.contains { $0 === context }
        )
        XCTAssertIdentical(context.webExtensionController, controller)
        XCTAssertIdentical(
            controller.delegate,
            fixture.inspection.controller.delegateBridge
        )

        controller.delegate = nil
        XCTAssertFalse(
            fixture.inspection.controller.delegateReadiness
                .controllerDidBecomeReady(controllerBinding)
        )
        XCTAssertNil(controller.delegate)
    }

    func testRolledBackWebKitLoadPreservesDelegateReceiptWithoutBinding()
        async throws {
        let fixture = try await makeLoadFixture(name: "DelegateRollback")
        let holder = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        var heldContext: WKWebExtensionContext?
        defer {
            if let heldContext,
               holder.extensionContexts.contains(where: { $0 === heldContext }) {
                try? holder.unload(heldContext)
            }
            fixture.cleanUp()
        }
        let controller = try XCTUnwrap(
            fixture.inspection.contextState.profiles.controller(for: fixture.profile.id)
        )
        let controllerBinding = try XCTUnwrap(
            fixture.inspection.contextState.profiles.controllerBindingSnapshot(
                for: fixture.profile.id
            )
        )
        controller.delegate = nil
        fixture.manager.testHooks.beforeControllerLoad = { extensionID in
            let context = try XCTUnwrap(
                fixture.inspection.contextState.profiles.contexts(
                    for: fixture.profile.id
                )[extensionID]
            )
            try holder.load(context)
            heldContext = context
        }

        do {
            _ = try await fixture.inspection.contextCoordination.loader.loadEnabled(
                from: fixture.entity
            )
            XCTFail("A context already loaded by another controller must fail")
        } catch {
            let webKitError = error as NSError
            XCTAssertEqual(
                webKitError.domain,
                WKWebExtensionContext.errorDomain
            )
            XCTAssertEqual(
                webKitError.code,
                WKWebExtensionContext.Error.alreadyLoaded.rawValue
            )
        }

        let context = try XCTUnwrap(heldContext)
        XCTAssertTrue(holder.extensionContexts.contains { $0 === context })
        XCTAssertFalse(
            controller.extensionContexts.contains { $0 === context }
        )
        XCTAssertNil(
            fixture.inspection.contextState.profiles.contexts(
                for: fixture.profile.id
            )[fixture.installed.id]
        )
        XCTAssertNil(controller.delegate)

        XCTAssertTrue(
            fixture.inspection.controller.delegateReadiness
                .controllerDidBecomeReady(controllerBinding)
        )
        XCTAssertIdentical(
            controller.delegate,
            fixture.inspection.controller.delegateBridge
        )
    }

    func testReentrantPolicyPublicationStopsBeforeStorageMutation()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Policy Reentrancy")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
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
        let claim = inspection.contextCoordination.loads.begin(for: key)
        let preparation = ExtensionContextPreparation(
            siteAccessPolicyStore: inspection.actionPolicy.store,
            installedExtensions:
                inspection.actionSurfaces.installedExtensions,
            permissionDecisions: inspection.actionPolicy.permissionDecisions,
            siteAccessPolicyDidPersist: {
                inspection.contextCoordination.loads.invalidate(key)
            }
        )
        let transaction = ExtensionContextControllerTransaction(
            authority: inspection.contextState.loadedContexts,
            profileRuntime: inspection.contextState.profiles,
            rollback: inspection.retirement.rollback,
            errorObservation: inspection.contextState.errors,
            runtimeMetrics: inspection.runtimeAuthorities.metrics,
            diagnostics: inspection.contextCoordination.diagnostics,
            expectedControllerDelegate: inspection.controller.delegateBridge,
            controllerDelegateReadiness:
                inspection.controller.delegateReadiness
        )
        transaction.installDebugBeforeControllerLoad { nil }
        let loader = ExtensionContextLoader(
            authority: inspection.contextState.loadedContexts,
            profileRuntime: inspection.contextState.profiles,
            controllerProvisioning: inspection.controller.provisioning,
            waitForWebsiteDataMutationAdmission: { _ in true },
            sourceCache: inspection.contextState.sourceCache,
            contextPreparation: preparation,
            runtimeMetrics: inspection.runtimeAuthorities.metrics,
            diagnostics: inspection.contextCoordination.diagnostics,
            expectedControllerDelegate: inspection.controller.delegateBridge,
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
                    activationCause: .installation,
                    claim: claim,
                    mutationLease: nil
                )
            )
            XCTFail("Reentrant policy publication must revoke the stale load")
        } catch {
            XCTAssertTrue(error is CancellationError, String(describing: error))
        }

        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controller(for: profile.id)
        )
        let runtimeIdentifier = ExtensionContextPreparation.runtimeIdentifier(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: directory.path
        )
        let storage = WebExtensionStorageCleanupStore(
            controllerStorageId: controller.configuration.identifier,
            storageDirectoryNameResolver: { _ in runtimeIdentifier }
        )
        XCTAssertFalse(storage.snapshot(for: extensionID).directoryExists)
        XCTAssertNil(
            inspection.contextState.profiles.contexts(for: profile.id)[
                extensionID
            ]
        )
    }

    func testReplacementBindingPropagatesExternalPreservationAuthority()
        async throws {
        let fixture = try await makeLoadFixture(name: "ReplacementAuthority")
        defer { fixture.cleanUp() }
        var replacement: WKWebExtensionContext?
        fixture.manager.testHooks.beforeControllerLoad = { extensionID in
            let current = try XCTUnwrap(
                fixture.inspection.contextState.profiles.contexts(
                    for: fixture.profile.id
                )[extensionID]
            )
            let context = WKWebExtensionContext(for: current.webExtension)
            replacement = context
            _ = fixture.inspection.contextState.profiles.setContext(
                context,
                extensionId: extensionID,
                profileId: fixture.profile.id
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.inspection.contextCoordination.loader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForReplacement
        )
        XCTAssertIdentical(
            fixture.inspection.contextState.profiles.contexts(for: fixture.profile.id)[
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
        _ = fixture.inspection.controller.provisioning.ensureExtensionController(for: siblingProfileID)
        var sibling: WKWebExtensionContext?
        fixture.manager.testHooks.beforeControllerLoad = { extensionID in
            let current = try XCTUnwrap(
                fixture.inspection.contextState.profiles.contexts(
                    for: fixture.profile.id
                )[extensionID]
            )
            let context = WKWebExtensionContext(for: current.webExtension)
            sibling = context
            _ = fixture.inspection.contextState.profiles.setContext(
                context,
                extensionId: extensionID,
                profileId: siblingProfileID
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.inspection.contextCoordination.loader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForActiveBinding
        )
        XCTAssertIdentical(
            fixture.inspection.contextState.profiles.contexts(for: siblingProfileID)[
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
        fixture.manager.testHooks.beforeControllerLoad = { extensionID in
            competingLease = try XCTUnwrap(
                fixture.inspection.contextCoordination.mutations.begin(
                    extensionID: extensionID,
                    operation: .install
                )
            )
            throw InjectedFailure.beforeControllerLoad
        }

        let failure = try await captureTransactionFailure {
            _ = try await fixture.inspection.contextCoordination.loader.loadEnabled(
                from: fixture.entity
            )
        }

        XCTAssertEqual(
            failure.rollback.externalStateDisposition,
            .preserveForCompetingTransaction
        )
        XCTAssertTrue(
            fixture.inspection.contextCoordination.mutations.finish(
                try XCTUnwrap(competingLease)
            )
        )
        competingLease = nil
    }

    private func makeLoadFixture(name: String) async throws -> LoadFixture {
        let container = try makeTestContainer()
        let profile = Profile(name: name)
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: try makeScratchDirectory(),
            name: name
        )
        let entity = try XCTUnwrap(
            try inspection.installation.metadata.extensionMetadata(
                for: installed.id
            )
        )
        try inspection.installation.metadata.setEnabled(true, for: entity)
        inspection.actionSurfaces.installedExtensions.upsert(
            inspection.installation.metadata.record(
                installed,
                withEnabledState: true
            )
        )
        _ = inspection.controller.provisioning.ensureExtensionController(
            for: profile.id
        )
        return LoadFixture(
            container: container,
            manager: manager,
            inspection: inspection,
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
    let container: SumiDatabase
    let manager: ExtensionManager
    let inspection: ExtensionManagerTestInspection
    let profile: Profile
    let installed: InstalledExtension
    let entity: InstalledExtensionMetadata

    func cleanUp() {
        manager.testHooks.beforeControllerLoad = nil
        manager.clearDebugState()
        _ = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeTransactionFailureTests"
        )
        _ = container
    }
}
