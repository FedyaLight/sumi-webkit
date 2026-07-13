import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeRecoveryTests:
    SafariExtensionWebViewControllerWiringTestCase {
    func testFailedEnableWithUnloadFailurePreservesEnabledLiveBinding()
        async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let controllerA = try XCTUnwrap(
            fixture.manager.profileRuntime.controller(for: fixture.profileA.id)
        )
        let retirementLease = try XCTUnwrap(
            fixture.manager.runtimeMutationRegistry.begin(
                extensionID: fixture.installed.id,
                operation: .disable
            )
        )
        let retirement = fixture.manager.runtimeRetirement.retire(
            extensionID: fixture.installed.id,
            cause: .disabled,
            mutationLease: retirementLease
        )
        XCTAssertTrue(retirement.completed)
        XCTAssertTrue(
            fixture.manager.runtimeMutationRegistry.finish(retirementLease)
        )
        try fixture.manager.installationMetadataStore.setEnabled(
            false,
            for: fixture.entity
        )
        fixture.manager.installedExtensionCollection.upsert(
            fixture.manager.installationMetadataStore.record(
                fixture.installed,
                withEnabledState: false
            )
        )

        fixture.unloadFault.controllerToFail = controllerA
        let recorder = RecoveryFinalizationRecorder(
            invalidatesProfileID: fixture.profileA.id
        )
        fixture.installFinalizationRecorder(recorder)

        do {
            _ = try await fixture.manager.installedExtensionLifecycle.enable(
                fixture.installed.id
            )
            XCTFail("Non-quiescent enable rollback must be reported")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "enabled persistence was preserved"
                ),
                error.localizedDescription
            )
        }

        XCTAssertTrue(fixture.entity.isEnabled)
        XCTAssertEqual(
            fixture.manager.installedExtensionCollection.records.first {
                $0.id == fixture.installed.id
            }?.isEnabled,
            true
        )
        let retainedContext = try XCTUnwrap(
            fixture.manager.profileRuntime.contexts(for: fixture.profileA.id)[
                fixture.installed.id
            ]
        )
        XCTAssertTrue(
            controllerA.extensionContexts.contains(where: {
                $0 === retainedContext
            })
        )
    }

    func testNonQuiescentPackageReplacementPreservesCandidateAndLiveRuntime()
        async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let controllerA = try XCTUnwrap(
            fixture.manager.profileRuntime.controller(for: fixture.profileA.id)
        )
        let replacementName = "RuntimeRecoveryReplacement"
        let replacementVersion = "2.0"
        try writeReplacementManifest(
            to: fixture.sourceURL,
            name: replacementName,
            version: replacementVersion
        )
        let candidateManifest = try Data(
            contentsOf: fixture.sourceURL.appendingPathComponent(
                "manifest.json"
            )
        )
        fixture.manager.testHooks.beforePersistInstalledRecord = { _ in
            fixture.unloadFault.controllerToFail = controllerA
            throw RecoveryError.injectedPersistenceFailure
        }
        defer {
            fixture.manager.testHooks.beforePersistInstalledRecord = nil
        }

        do {
            _ = try await fixture.manager.extensionInstaller.install(
                from: fixture.sourceURL,
                enableOnInstall: true
            )
            XCTFail("Non-quiescent replacement rollback must be reported")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "candidate metadata were preserved"
                ),
                error.localizedDescription
            )
        }

        XCTAssertEqual(
            try Data(
                contentsOf: URL(
                    fileURLWithPath: fixture.installed.packagePath,
                    isDirectory: true
                ).appendingPathComponent("manifest.json")
            ),
            candidateManifest
        )
        let candidateEntity = try XCTUnwrap(
            fixture.manager.installationMetadataStore.extensionEntity(
                for: fixture.installed.id
            )
        )
        XCTAssertEqual(candidateEntity.name, replacementName)
        XCTAssertEqual(candidateEntity.version, replacementVersion)
        XCTAssertTrue(candidateEntity.isEnabled)
        let candidateRecord = try XCTUnwrap(
            fixture.manager.installedExtensionCollection.records.first {
                $0.id == fixture.installed.id
            }
        )
        XCTAssertEqual(candidateRecord.name, replacementName)
        XCTAssertEqual(candidateRecord.version, replacementVersion)
        XCTAssertTrue(candidateRecord.isEnabled)
        let retainedContextA = try XCTUnwrap(
            fixture.manager.profileRuntime.contexts(for: fixture.profileA.id)[
                fixture.installed.id
            ]
        )
        XCTAssertNotIdentical(retainedContextA, fixture.originalContextA)
        XCTAssertTrue(
            controllerA.extensionContexts.contains(where: {
                $0 === retainedContextA
            })
        )
        XCTAssertNil(
            fixture.manager.profileRuntime.contexts(for: fixture.profileB.id)[
                fixture.installed.id
            ]
        )
        XCTAssertFalse(
            fixture.controllerB.extensionContexts.contains(where: {
                $0 === fixture.originalContextB
            })
        )
        let nextLease = try XCTUnwrap(
            fixture.manager.runtimeMutationRegistry.begin(
                extensionID: fixture.installed.id,
                operation: .enable
            )
        )
        XCTAssertTrue(
            fixture.manager.runtimeMutationRegistry.finish(nextLease)
        )
    }

    func testFailedEnabledPackageReplacementRestoresBothRuntimeProfiles()
        async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let originalName = fixture.installed.name
        let originalVersion = fixture.installed.version
        let originalLastUpdateDate = fixture.entity.lastUpdateDate
        let originalPackageManifest = try Data(
            contentsOf: URL(
                fileURLWithPath: fixture.installed.packagePath,
                isDirectory: true
            ).appendingPathComponent("manifest.json")
        )
        let recorder = RecoveryFinalizationRecorder()
        fixture.installFinalizationRecorder(recorder)
        try writeReplacementManifest(
            to: fixture.sourceURL,
            name: "RuntimeRecoveryReplacement",
            version: "2.0"
        )
        fixture.manager.testHooks.beforePersistInstalledRecord = { _ in
            throw RecoveryError.injectedPersistenceFailure
        }
        defer {
            fixture.manager.testHooks.beforePersistInstalledRecord = nil
        }

        do {
            _ = try await fixture.manager.extensionInstaller.install(
                from: fixture.sourceURL,
                enableOnInstall: true
            )
            XCTFail("Replacement must fail at the persistence boundary")
        } catch {
            XCTAssertEqual(
                error as? RecoveryError,
                .injectedPersistenceFailure
            )
        }

        recorder.assertFinalizedExactlyOnce(
            profileIDs: [fixture.profileA.id, fixture.profileB.id]
        )
        XCTAssertEqual(recorder.reconciliationCount, 2)
        let restoredContextA = try XCTUnwrap(
            fixture.manager.profileRuntime.contexts(for: fixture.profileA.id)[
                fixture.installed.id
            ]
        )
        let restoredContextB = try XCTUnwrap(
            fixture.manager.profileRuntime.contexts(for: fixture.profileB.id)[
                fixture.installed.id
            ]
        )
        XCTAssertNotIdentical(
            restoredContextA,
            fixture.originalContextA
        )
        XCTAssertNotIdentical(
            restoredContextB,
            fixture.originalContextB
        )
        XCTAssertEqual(restoredContextA.webExtension.displayName, originalName)
        XCTAssertEqual(restoredContextB.webExtension.displayName, originalName)
        XCTAssertEqual(
            try Data(
                contentsOf: URL(
                    fileURLWithPath: fixture.installed.packagePath,
                    isDirectory: true
                ).appendingPathComponent("manifest.json")
            ),
            originalPackageManifest
        )
        let restoredEntity = try XCTUnwrap(
            fixture.manager.installationMetadataStore.extensionEntity(
                for: fixture.installed.id
            )
        )
        XCTAssertEqual(restoredEntity.name, originalName)
        XCTAssertEqual(restoredEntity.version, originalVersion)
        XCTAssertEqual(
            restoredEntity.lastUpdateDate.timeIntervalSinceReferenceDate,
            originalLastUpdateDate.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
        XCTAssertTrue(restoredEntity.isEnabled)
        let restoredRecord = try XCTUnwrap(
            fixture.manager.installedExtensionCollection.records.first {
                $0.id == fixture.installed.id
            }
        )
        XCTAssertEqual(restoredRecord.name, originalName)
        XCTAssertEqual(restoredRecord.version, originalVersion)
        XCTAssertTrue(restoredRecord.isEnabled)
    }

    func testPartialDisableRecoversMissingAndStillBoundProfiles()
        async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        let originalLastUpdateDate = fixture.entity.lastUpdateDate
        fixture.unloadFault.controllerToFail = fixture.controllerB
        fixture.manager.backgroundRuntimeStateOwner.removeRuntimeState(
            for: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: fixture.installed.id,
                profileId: fixture.profileB.id
            )
        )
        let recorder = RecoveryFinalizationRecorder()
        fixture.installFinalizationRecorder(recorder)

        do {
            try await fixture.manager.installedExtensionLifecycle.disable(
                fixture.installed.id,
                releaseRuntimeIfIdle: false
            )
            XCTFail("A partial retirement must still report disable failure")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    fixture.profileB.id.uuidString
                )
            )
        }

        recorder.assertFinalizedExactlyOnce(
            profileIDs: [fixture.profileA.id, fixture.profileB.id]
        )
        XCTAssertEqual(recorder.reconciliationCount, 2)
        let recoveredA = try XCTUnwrap(
            fixture.manager.profileRuntime.contexts(for: fixture.profileA.id)[
                fixture.installed.id
            ]
        )
        XCTAssertFalse(recoveredA === fixture.originalContextA)
        XCTAssertIdentical(
            fixture.manager.profileRuntime.contexts(for: fixture.profileB.id)[
                fixture.installed.id
            ],
            fixture.originalContextB
        )
        XCTAssertEqual(
            fixture.unloadFault.failureCount,
            1,
            "rollback cleanup must not retire another profile's live context"
        )
        XCTAssertTrue(fixture.entity.isEnabled)
        XCTAssertEqual(
            fixture.entity.lastUpdateDate.timeIntervalSinceReferenceDate,
            originalLastUpdateDate.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            fixture.manager.installedExtensionCollection.records.first {
                $0.id == fixture.installed.id
            }?.isEnabled,
            true
        )
    }

    func testRecoveryFailureIsReturnedByLifecycleInsteadOfBeingSwallowed()
        async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanUp() }
        fixture.unloadFault.controllerToFail = fixture.controllerB
        let recorder = RecoveryFinalizationRecorder(
            invalidatesProfileID: fixture.profileA.id
        )
        fixture.installFinalizationRecorder(recorder)

        do {
            try await fixture.manager.installedExtensionLifecycle.disable(
                fixture.installed.id,
                releaseRuntimeIfIdle: false
            )
            XCTFail("Incomplete recovery must be returned to the caller")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "recovery was incomplete"
                ),
                error.localizedDescription
            )
            XCTAssertTrue(
                error.localizedDescription.contains(
                    "runtime recovery failed"
                ),
                error.localizedDescription
            )
        }

        recorder.assertFinalizedExactlyOnce(
            profileIDs: [fixture.profileA.id, fixture.profileB.id]
        )
        XCTAssertEqual(
            recorder.reconciliationCount,
            1,
            "a failed profile must not prevent later profiles from recovery"
        )
        XCTAssertNil(
            fixture.manager.profileRuntime.contexts(for: fixture.profileA.id)[
                fixture.installed.id
            ]
        )
        XCTAssertIdentical(
            fixture.manager.profileRuntime.contexts(for: fixture.profileB.id)[
                fixture.installed.id
            ],
            fixture.originalContextB
        )
        XCTAssertEqual(
            fixture.unloadFault.failureCount,
            1,
            "failed profile rollback must not touch the surviving profile"
        )
        XCTAssertTrue(fixture.entity.isEnabled)
        XCTAssertEqual(
            fixture.manager.installedExtensionCollection.records.first {
                $0.id == fixture.installed.id
            }?.isEnabled,
            true
        )
    }

    private func makeFixture() async throws -> RecoveryFixture {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Recovery A")
        let profileB = Profile(name: "Recovery B")
        let manager = makeManager(
            context: container.mainContext,
            profile: profileA
        ).manager
        try XCTSkipUnless(manager.isExtensionSupportAvailable)
        let unloadFault = RecoveryUnloadFault()
        installContextRetirementFault(
            unloadFault,
            on: manager
        )

        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: try makeScratchDirectory(),
            name: "RuntimeRecovery-\(UUID().uuidString)"
        )
        let entity = try XCTUnwrap(
            manager.installationMetadataStore.extensionEntity(
                for: installed.id
            )
        )
        try manager.installationMetadataStore.setEnabled(true, for: entity)
        manager.installedExtensionCollection.upsert(
            manager.installationMetadataStore.record(
                installed,
                withEnabledState: true
            )
        )

        let lease = try XCTUnwrap(
            manager.runtimeMutationRegistry.begin(
                extensionID: installed.id,
                operation: .enable
            )
        )
        defer { _ = manager.runtimeMutationRegistry.finish(lease) }
        _ = try await manager.extensionRuntimeLoader.loadEnabled(
            from: entity,
            profileID: profileA.id,
            activation: .background(.enable),
            mutationLease: lease
        )
        _ = try await manager.extensionRuntimeLoader.loadEnabled(
            from: entity,
            profileID: profileB.id,
            activation: .background(.enable),
            mutationLease: lease
        )

        return RecoveryFixture(
            container: container,
            manager: manager,
            profileA: profileA,
            profileB: profileB,
            installed: installed,
            sourceURL: URL(
                fileURLWithPath: installed.sourceBundlePath,
                isDirectory: true
            ),
            entity: entity,
            originalContextA: try XCTUnwrap(
                manager.profileRuntime.contexts(for: profileA.id)[installed.id]
            ),
            originalContextB: try XCTUnwrap(
                manager.profileRuntime.contexts(for: profileB.id)[installed.id]
            ),
            controllerB: try XCTUnwrap(
                manager.profileRuntime.controller(for: profileB.id)
            ),
            originalActionSurfacePublisher: manager.actionSurfacePublisher,
            unloadFault: unloadFault
        )
    }

    private func writeReplacementManifest(
        to sourceURL: URL,
        name: String,
        version: String
    ) throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": version,
            "host_permissions": ["<all_urls>"],
            "action": ["default_popup": "popup.html"],
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(
            to: sourceURL.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
    }

    private func installContextRetirementFault(
        _ fault: RecoveryUnloadFault,
        on manager: ExtensionManager
    ) {
        let retirement = ExtensionContextRetirement(
            profileRuntime: manager.profileRuntime,
            backgroundRuntimeState: manager.backgroundRuntimeStateOwner,
            runtimeSession: manager.runtimeSession,
            errorObservation: manager.contextErrorObservation,
            diagnostics: manager.runtimeDiagnostics,
            unloadContext: { controller, context in
                try fault.unload(context, from: controller)
            }
        )
        manager.contextRetirement = retirement
        manager.scopedRuntimeRetirement = ExtensionScopedRuntimeRetirement(
            profileRuntime: manager.profileRuntime,
            mutationRegistry: manager.runtimeMutationRegistry,
            loadRegistry: manager.contextLoadRegistry,
            contextRetirement: retirement,
            runtimeSession: manager.runtimeSession,
            sourceCache: manager.webExtensionRuntimeSourceCache,
            errorObservation: manager.contextErrorObservation,
            nativeMessagingPorts: manager.nativeMessagingPortRegistry,
            optionsWindows: manager.optionsWindows,
            actionAnchors: manager.actionAnchorStore,
            diagnostics: manager.runtimeDiagnostics
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecoveryFixture {
    let container: ModelContainer
    let manager: ExtensionManager
    let profileA: Profile
    let profileB: Profile
    let installed: InstalledExtension
    let sourceURL: URL
    let entity: ExtensionEntity
    let originalContextA: WKWebExtensionContext
    let originalContextB: WKWebExtensionContext
    let controllerB: WKWebExtensionController
    let originalActionSurfacePublisher: ExtensionActionSurfacePublisher
    let unloadFault: RecoveryUnloadFault

    init(
        container: ModelContainer,
        manager: ExtensionManager,
        profileA: Profile,
        profileB: Profile,
        installed: InstalledExtension,
        sourceURL: URL,
        entity: ExtensionEntity,
        originalContextA: WKWebExtensionContext,
        originalContextB: WKWebExtensionContext,
        controllerB: WKWebExtensionController,
        originalActionSurfacePublisher: ExtensionActionSurfacePublisher,
        unloadFault: RecoveryUnloadFault
    ) {
        self.container = container
        self.manager = manager
        self.profileA = profileA
        self.profileB = profileB
        self.installed = installed
        self.sourceURL = sourceURL
        self.entity = entity
        self.originalContextA = originalContextA
        self.originalContextB = originalContextB
        self.controllerB = controllerB
        self.originalActionSurfacePublisher = originalActionSurfacePublisher
        self.unloadFault = unloadFault
    }

    func installFinalizationRecorder(
        _ recorder: RecoveryFinalizationRecorder
    ) {
        manager.actionSurfacePublisher = ExtensionActionSurfacePublisher(
            authority: manager.loadedContextAuthority,
            extensionIDForContext: { [weak manager] context in
                guard let manager,
                      let identity = manager.profileRuntime
                        .exactContextIdentity(for: context)
                else {
                    return nil
                }
                return identity.extensionId
            },
            setActionSurfaceState: { _, _ in },
            removeActionSurfaceState: { _ in },
            currentExtensionTab: { nil },
            stableAdapter: { _ in nil },
            ensureBackgroundAvailableIfRequired: {
                [weak manager, weak recorder] _, context, _, isCurrent in
                guard let manager,
                      let identity = manager.profileRuntime
                        .exactContextIdentity(for: context)
                else {
                    throw CancellationError()
                }
                recorder?.record(identity.profileId)
                if recorder?.consumeInvalidation(
                    for: identity.profileId
                ) == true {
                    manager.contextLoadRegistry.invalidate(
                        .init(
                            profileId: identity.profileId,
                            extensionId: identity.extensionId
                        )
                    )
                }
                guard isCurrent() else { throw CancellationError() }
            },
            reconcileOpenTabsAfterExtensionContextLoad: { [weak recorder] _ in
                recorder?.recordReconciliation()
            }
        )
    }

    func cleanUp() {
        unloadFault.controllerToFail = nil
        manager.actionSurfacePublisher = originalActionSurfacePublisher
        _ = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeRecoveryTests.cleanup"
        )
        let packageURL = URL(
            fileURLWithPath: installed.packagePath,
            isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: packageURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: packageURL)
        } catch {
            assertionFailure(
                "Could not remove recovery fixture package: \(error)"
            )
        }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecoveryFinalizationRecorder {
    private(set) var finalizedProfileIDs: [UUID] = []
    private(set) var reconciliationCount = 0
    private var invalidatesProfileID: UUID?

    init(invalidatesProfileID: UUID? = nil) {
        self.invalidatesProfileID = invalidatesProfileID
    }

    func record(_ profileID: UUID) {
        finalizedProfileIDs.append(profileID)
    }

    func recordReconciliation() {
        reconciliationCount += 1
    }

    func assertFinalizedExactlyOnce(
        profileIDs: Set<UUID>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            Dictionary(grouping: finalizedProfileIDs, by: { $0 })
                .mapValues(\.count),
            Dictionary(uniqueKeysWithValues: profileIDs.map { ($0, 1) }),
            file: file,
            line: line
        )
    }

    func consumeInvalidation(for profileID: UUID) -> Bool {
        guard invalidatesProfileID == profileID else { return false }
        invalidatesProfileID = nil
        return true
    }
}

@available(macOS 15.5, *)
@MainActor
private final class RecoveryUnloadFault {
    weak var controllerToFail: WKWebExtensionController?
    private(set) var failureCount = 0

    func unload(
        _ context: WKWebExtensionContext,
        from controller: WKWebExtensionController
    ) throws {
        if controller === controllerToFail {
            failureCount += 1
            throw RecoveryError.injectedUnloadFailure
        }
        try controller.unload(context)
    }
}

private enum RecoveryError: Error, Equatable {
    case injectedUnloadFailure
    case injectedPersistenceFailure
}
