import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionScopedRuntimeRetirementTests: XCTestCase {
    private enum TestError: Error {
        case unloadFailed
    }

    func testRetirementRejectsWrongAndStaleMutationOrTerminalAdmission()
        async throws {
        let fixture = try await makeFixture(extensionID: "admission")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let context = try XCTUnwrap(fixture.contextsByProfile[profileID])
        fixture.seedNativeMessagingWake(profileID: profileID)
        let loopGuardKey = fixture.seedNativeMessagingLoopGuard(
            profileID: profileID
        )
        var unloadCount = 0
        let retirement = fixture.retirement { _, _ in
            unloadCount += 1
        }

        let otherLease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: "other-extension",
                operation: .disable
            )
        )
        let wrongMutation = retirement.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(otherLease),
            resources: fixture.resources
        )
        XCTAssertEqual(wrongMutation.completionStatus, .rejected)
        XCTAssertEqual(wrongMutation.initialProfileIDs, [profileID])
        XCTAssertTrue(wrongMutation.contextOutcomes.isEmpty)
        XCTAssertEqual(wrongMutation.remainingProfileIDs, [profileID])
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: profileID)[
                fixture.extensionID
            ],
            context
        )

        XCTAssertTrue(fixture.mutationRegistry.finish(otherLease))
        let staleMutationLease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(staleMutationLease))
        let staleMutation = retirement.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(staleMutationLease),
            resources: fixture.resources
        )
        XCTAssertEqual(staleMutation.completionStatus, .rejected)
        XCTAssertEqual(staleMutation.initialProfileIDs, [profileID])
        XCTAssertTrue(staleMutation.contextOutcomes.isEmpty)
        XCTAssertEqual(staleMutation.remainingProfileIDs, [profileID])

        let staleTerminalLease = try XCTUnwrap(
            fixture.mutationRegistry.beginTerminal()
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(staleTerminalLease))
        let staleTerminal = retirement.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .terminal(staleTerminalLease),
            resources: fixture.resources
        )
        XCTAssertEqual(staleTerminal.completionStatus, .rejected)
        XCTAssertEqual(staleTerminal.initialProfileIDs, [profileID])
        XCTAssertTrue(staleTerminal.contextOutcomes.isEmpty)
        XCTAssertEqual(staleTerminal.remainingProfileIDs, [profileID])
        XCTAssertEqual(unloadCount, 0)
        XCTAssertTrue(fixture.auxiliaryWindows.closedExtensionIDs.isEmpty)
        XCTAssertEqual(
            fixture.nativeMessagingWakes.runtimeTasksForDrain().count,
            1
        )
        XCTAssertEqual(
            fixture.nativeMessagingLoopGuard.evaluate(
                key: loopGuardKey,
                hostBundleIdentifier: "com.example.unsupported"
            ).retryCountBucket,
            .first
        )
        fixture.nativeMessagingWakes.cancelAllWakeTasks()
    }

    func testRollbackRejectsConcurrentOtherProfileLoadBeforeSharedCleanup()
        async throws {
        let fixture = try await makeFixture(
            extensionID: "concurrent-profile-load"
        )
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: profileID
            )
        )
        XCTAssertNotNil(fixture.profileRuntime.removeContext(ifCurrent: receipt))
        let rollbackClaim = fixture.loadRegistry.begin(for: receipt.key)
        _ = fixture.loadRegistry.begin(
            for: ExtensionRuntimeResidencyState.ScopedKey(
                profileId: UUID(),
                extensionId: fixture.extensionID
            )
        )
        let anchor = NSView()
        fixture.actionAnchors.setAnchor(
            for: fixture.extensionID,
            anchorView: anchor
        )
        _ = try await fixture.seedRuntimeBookkeeping()

        let result = fixture.retirement { _, _ in
            XCTFail("Rollback cleanup must not retire a concurrent load")
        }.retire(
            extensionID: fixture.extensionID,
            cause: .runtimeRollback,
            admission: .rollback(rollbackClaim, nil),
            resources: fixture.resources
        )

        XCTAssertEqual(result.completionStatus, .rejected)
        XCTAssertIdentical(
            fixture.sourceCache.entry(for: fixture.extensionID)?
                .resolution.webExtension,
            fixture.webExtension
        )
        XCTAssertNotNil(
            fixture.runtimeCatalog.manifest(for: fixture.extensionID)
        )
        XCTAssertEqual(
            fixture.actionAnchors.anchorCount(for: fixture.extensionID),
            1
        )
        withExtendedLifetime(anchor) {}
    }

    func testExactRollbackSucceedsWhileSiblingProfilePreservesSharedState()
        async throws {
        let fixture = try await makeFixture(
            extensionID: "sibling-profile",
            profileCount: 2
        )
        let failedProfileID = fixture.profileIDs[0]
        let siblingProfileID = fixture.profileIDs[1]
        let failedContext = try XCTUnwrap(
            fixture.contextsByProfile[failedProfileID]
        )
        let failedController = try XCTUnwrap(
            fixture.controllersByProfile[failedProfileID]
        )
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: failedProfileID
            )
        )
        let claim = fixture.loadRegistry.begin(for: receipt.key)
        let contextRetirement = ExtensionContextRetirement(
            profileRuntime: fixture.profileRuntime,
            backgroundRuntimeState: fixture.backgroundRuntimeState,
            runtimeResidency: fixture.runtimeResidency,
            errorObservation: fixture.errorObservation,
            diagnostics: ExtensionRuntimeDiagnostics(),
            unloadContext: { _, _ in },
            isLoadedContext: { _, _ in false }
        )
        let authority = ExtensionLoadedContextAuthority(
            profileRuntime: fixture.profileRuntime,
            mutationRegistry: fixture.mutationRegistry,
            loadRegistry: fixture.loadRegistry,
            contextRetirement: contextRetirement
        )
        let retirement = ExtensionRuntimeRetirement(
            scopedRetirement: fixture.retirement { _, _ in },
            actionSurfaces: { nil },
            resources: { fixture.resources }
        )
        let rollback = ExtensionRuntimeRollback(
            authority: authority,
            retirement: retirement
        )
        let loadedContext = ExtensionLoadedContext(
            context: failedContext,
            controller: failedController,
            bindingReceipt: receipt,
            loadClaim: claim,
            mutationLease: nil
        )

        let result = rollback.rollBack(loadedContext)

        XCTAssertEqual(result.exactDisposition, .retired)
        XCTAssertTrue(result.exactRollbackCompleted)
        XCTAssertEqual(
            result.sharedCleanupDisposition,
            .preservedForActiveBindings
        )
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveForActiveBinding
        )
        XCTAssertNotNil(
            fixture.profileRuntime.contexts(for: siblingProfileID)[
                fixture.extensionID
            ]
        )
    }

    func testTerminalSupersessionWithoutCandidateAuthorityPermitsExternalRollback()
        async throws {
        let fixture = try await makeFixture(extensionID: "terminal-rollback")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let mutationLease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .install
            )
        )
        let transaction = try makeRollbackTransaction(
            fixture: fixture,
            profileID: profileID,
            mutationLease: mutationLease
        )
        let terminalLease = try XCTUnwrap(
            fixture.mutationRegistry.beginTerminal()
        )

        let result = transaction.rollback.rollBack(transaction.loadedContext)

        XCTAssertTrue(result.exactRollbackCompleted)
        XCTAssertEqual(
            result.sharedCleanupDisposition,
            .supersededWithoutCompetingAuthority
        )
        XCTAssertEqual(result.externalStateDisposition, .rollbackAllowed)
        XCTAssertTrue(fixture.mutationRegistry.finish(terminalLease))
    }

    func testCompetingMutationWithoutBindingBlocksExternalRollback()
        async throws {
        let fixture = try await makeFixture(extensionID: "mutation-rollback")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let mutationLease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .install
            )
        )
        let transaction = try makeRollbackTransaction(
            fixture: fixture,
            profileID: profileID,
            mutationLease: mutationLease
        )
        let terminalLease = try XCTUnwrap(
            fixture.mutationRegistry.beginTerminal()
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(terminalLease))
        let replacementMutation = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .install
            )
        )

        let result = transaction.rollback.rollBack(transaction.loadedContext)

        XCTAssertTrue(result.exactRollbackCompleted)
        XCTAssertEqual(
            result.sharedCleanupDisposition,
            .preservedForCompetingTransaction
        )
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveForCompetingTransaction
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(replacementMutation))
    }

    func testCompetingLoadWithoutBindingBlocksExternalRollback()
        async throws {
        let fixture = try await makeFixture(extensionID: "load-rollback")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let mutationLease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .install
            )
        )
        let transaction = try makeRollbackTransaction(
            fixture: fixture,
            profileID: profileID,
            mutationLease: mutationLease
        )
        _ = fixture.loadRegistry.begin(
            for: .init(
                profileId: UUID(),
                extensionId: fixture.extensionID
            )
        )

        let result = transaction.rollback.rollBack(transaction.loadedContext)

        XCTAssertEqual(result.exactDisposition, .retired)
        XCTAssertEqual(
            result.sharedCleanupDisposition,
            .preservedForCompetingTransaction
        )
        XCTAssertEqual(
            result.externalStateDisposition,
            .preserveForCompetingTransaction
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(mutationLease))
    }

    func testDisableClearsActionAnchorsButPackageReplacementPreservesThem()
        async throws {
        let disabled = try await makeFixture(extensionID: "disabled")
        let disabledAnchor = NSView()
        disabled.actionAnchors.setAnchor(
            for: disabled.extensionID,
            anchorView: disabledAnchor
        )
        let disableLease = try XCTUnwrap(
            disabled.mutationRegistry.begin(
                extensionID: disabled.extensionID,
                operation: .disable
            )
        )

        let disabledResult = disabled.retirement { _, _ in }.retire(
            extensionID: disabled.extensionID,
            cause: .disabled,
            admission: .mutation(disableLease),
            resources: disabled.resources
        )

        XCTAssertTrue(disabledResult.isQuiescent)
        XCTAssertEqual(
            disabled.actionAnchors.anchorCount(for: disabled.extensionID),
            0
        )

        let replacement = try await makeFixture(
            extensionID: "package-replacement"
        )
        let replacementAnchor = NSView()
        replacement.actionAnchors.setAnchor(
            for: replacement.extensionID,
            anchorView: replacementAnchor
        )
        let replacementLease = try XCTUnwrap(
            replacement.mutationRegistry.begin(
                extensionID: replacement.extensionID,
                operation: .install
            )
        )

        let replacementResult = replacement.retirement { _, _ in }.retire(
            extensionID: replacement.extensionID,
            cause: .packageReplacement,
            admission: .mutation(replacementLease),
            resources: replacement.resources
        )

        XCTAssertTrue(replacementResult.isQuiescent)
        XCTAssertEqual(
            replacement.actionAnchors.anchorCount(
                for: replacement.extensionID
            ),
            1
        )
        withExtendedLifetime((disabledAnchor, replacementAnchor)) {}
    }

    func testUnloadFailureLeavesUISessionsPortsCachesAndManifestUntouched()
        async throws {
        let fixture = try await makeFixture(extensionID: "unload-failure")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let context = try XCTUnwrap(fixture.contextsByProfile[profileID])
        fixture.seedNativeMessagingWake(profileID: profileID)
        let loopGuardKey = fixture.seedNativeMessagingLoopGuard(
            profileID: profileID
        )
        let anchor = NSView()
        fixture.actionAnchors.setAnchor(
            for: fixture.extensionID,
            anchorView: anchor
        )
        let optionsWindow = NSWindow()
        fixture.optionsWindows.trackPresentedWindow(
            optionsWindow,
            delegate: nil,
            for: fixture.extensionID,
            profileID: profileID
        )
        let port = ScopedRetirementMockPort()
        let portSession = makePortSession(
            port: port,
            extensionID: fixture.extensionID,
            profileID: profileID
        )
        XCTAssertNotNil(
            fixture.nativeMessagingPorts.register(
                handler: portSession,
                port: port,
                extensionId: fixture.extensionID,
                profileId: profileID
            )
        )
        let sourceKey = try await fixture.seedRuntimeBookkeeping()
        fixture.errorObservation.seedLoggedErrorFingerprintForTesting(
            "fingerprint",
            extensionId: fixture.extensionID,
            profileId: profileID
        )
        let lease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )

        let result = fixture.retirement { _, _ in
            throw TestError.unloadFailed
        }.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(lease),
            resources: fixture.resources
        )

        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: fixture.extensionID
        )
        XCTAssertEqual(result.contextOutcomes[key], .unloadFailed)
        XCTAssertEqual(result.remainingProfileIDs, [profileID])
        XCTAssertFalse(result.isQuiescent)
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: profileID)[
                fixture.extensionID
            ],
            context
        )
        XCTAssertIdentical(
            fixture.sourceCache.entry(for: fixture.extensionID)?
                .resolution.webExtension,
            fixture.webExtension
        )
        XCTAssertEqual(
            fixture.sourceCache.entry(for: fixture.extensionID)?.key,
            sourceKey
        )
        XCTAssertEqual(
            fixture.runtimeCatalog.manifest(
                for: fixture.extensionID
            )?["manifest_version"] as? Int,
            3
        )
        XCTAssertNotNil(
            fixture.runtimeCatalog.loadError(
                extensionID: fixture.extensionID,
                profileID: profileID
            )
        )
        XCTAssertTrue(
            fixture.runtimeResidency.liveContextKeys.contains(key)
        )
        XCTAssertTrue(fixture.errorObservation.hasLoggedErrorFingerprints)
        XCTAssertIdentical(
            fixture.optionsWindows.windows[fixture.extensionID],
            optionsWindow
        )
        XCTAssertEqual(
            fixture.actionAnchors.anchorCount(for: fixture.extensionID),
            1
        )
        XCTAssertEqual(fixture.nativeMessagingPorts.count, 1)
        XCTAssertFalse(port.isDisconnected)
        XCTAssertTrue(fixture.auxiliaryWindows.closedExtensionIDs.isEmpty)
        XCTAssertTrue(
            fixture.nativeMessagingWakes.runtimeTasksForDrain().isEmpty
        )
        XCTAssertEqual(
            fixture.nativeMessagingLoopGuard.evaluate(
                key: loopGuardKey,
                hostBundleIdentifier: "com.example.unsupported"
            ).retryCountBucket,
            .first
        )
        withExtendedLifetime((anchor, portSession)) {}
    }

    func testSuccessfulMultiProfileRetirementUnloadsExactBindingsThenCleansUp()
        async throws {
        let fixture = try await makeFixture(
            extensionID: "multi-profile",
            profileCount: 2
        )
        fixture.seedNativeMessagingWake(profileID: fixture.profileIDs[0])
        let loopGuardKey = fixture.seedNativeMessagingLoopGuard(
            profileID: fixture.profileIDs[1]
        )
        let anchor = NSView()
        fixture.actionAnchors.setAnchor(
            for: fixture.extensionID,
            anchorView: anchor
        )
        let optionsWindow = NSWindow()
        fixture.optionsWindows.trackPresentedWindow(
            optionsWindow,
            delegate: nil,
            for: fixture.extensionID,
            profileID: fixture.profileIDs[0]
        )
        let port = ScopedRetirementMockPort()
        let portSession = makePortSession(
            port: port,
            extensionID: fixture.extensionID,
            profileID: fixture.profileIDs[1]
        )
        XCTAssertNotNil(
            fixture.nativeMessagingPorts.register(
                handler: portSession,
                port: port,
                extensionId: fixture.extensionID,
                profileId: fixture.profileIDs[1]
            )
        )
        _ = try await fixture.seedRuntimeBookkeeping()
        fixture.runtimeCatalog.recordManifest(
            ["manifest_version": 3],
            for: "unrelated"
        )
        let expectedBindings = Dictionary(
            uniqueKeysWithValues: fixture.profileIDs.map { profileID in
                (
                    ObjectIdentifier(fixture.controllersByProfile[profileID]!),
                    ObjectIdentifier(fixture.contextsByProfile[profileID]!)
                )
            }
        )
        var unloadedBindings: [ObjectIdentifier: ObjectIdentifier] = [:]
        let lease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )

        let result = fixture.retirement { controller, context in
            unloadedBindings[ObjectIdentifier(controller)] =
                ObjectIdentifier(context)
        }.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(lease),
            resources: fixture.resources
        )

        XCTAssertTrue(result.isQuiescent)
        XCTAssertEqual(result.contextOutcomes.count, 2)
        XCTAssertTrue(result.contextOutcomes.values.allSatisfy { $0 == .retired })
        XCTAssertEqual(unloadedBindings, expectedBindings)
        for profileID in fixture.profileIDs {
            XCTAssertNil(
                fixture.profileRuntime.contexts(for: profileID)[
                    fixture.extensionID
                ]
            )
        }
        XCTAssertEqual(
            fixture.auxiliaryWindows.closedExtensionIDs,
            [fixture.extensionID]
        )
        XCTAssertEqual(
            fixture.auxiliaryWindows.closeReasons.map(\.rawValue),
            [AuxiliaryWindowCloseReason.extensionDisable.rawValue]
        )
        XCTAssertTrue(
            fixture.nativeMessagingWakes.runtimeTasksForDrain().isEmpty
        )
        XCTAssertEqual(
            fixture.nativeMessagingLoopGuard.evaluate(
                key: loopGuardKey,
                hostBundleIdentifier: "com.example.unsupported"
            ).retryCountBucket,
            .none
        )
        XCTAssertNil(fixture.optionsWindows.windows[fixture.extensionID])
        XCTAssertEqual(fixture.nativeMessagingPorts.count, 0)
        XCTAssertTrue(port.isDisconnected)
        XCTAssertEqual(
            fixture.actionAnchors.anchorCount(for: fixture.extensionID),
            0
        )
        XCTAssertNil(fixture.sourceCache.entry(for: fixture.extensionID))
        XCTAssertNil(
            fixture.runtimeCatalog.manifest(for: fixture.extensionID)
        )
        XCTAssertNotNil(
            fixture.runtimeCatalog.manifest(for: "unrelated")
        )
        XCTAssertFalse(
            fixture.runtimeCatalog.hasLoadErrors(for: fixture.extensionID)
        )
        XCTAssertTrue(
            fixture.runtimeResidency.liveContextKeys.allSatisfy {
                    $0.extensionId != fixture.extensionID
                }
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(lease))
        withExtendedLifetime((anchor, optionsWindow, portSession)) {}
    }

    func testPartialMultiProfileRetirementReportsContextsRemainingWithoutSharedCleanup()
        async throws {
        let fixture = try await makeFixture(
            extensionID: "partial-multi-profile",
            profileCount: 2
        )
        let successfulProfileID = fixture.profileIDs[0]
        let failingProfileID = fixture.profileIDs[1]
        let successfulContext = try XCTUnwrap(
            fixture.contextsByProfile[successfulProfileID]
        )
        let failingContext = try XCTUnwrap(
            fixture.contextsByProfile[failingProfileID]
        )
        let anchor = NSView()
        fixture.actionAnchors.setAnchor(
            for: fixture.extensionID,
            anchorView: anchor
        )
        let optionsWindow = NSWindow()
        fixture.optionsWindows.trackPresentedWindow(
            optionsWindow,
            delegate: nil,
            for: fixture.extensionID,
            profileID: failingProfileID
        )
        let port = ScopedRetirementMockPort()
        let portSession = makePortSession(
            port: port,
            extensionID: fixture.extensionID,
            profileID: failingProfileID
        )
        XCTAssertNotNil(
            fixture.nativeMessagingPorts.register(
                handler: portSession,
                port: port,
                extensionId: fixture.extensionID,
                profileId: failingProfileID
            )
        )
        let sourceKey = try await fixture.seedRuntimeBookkeeping()
        fixture.seedNativeMessagingWake(profileID: successfulProfileID)
        let loopGuardKey = fixture.seedNativeMessagingLoopGuard(
            profileID: failingProfileID
        )
        let lease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )
        var unloadCountByContext: [ObjectIdentifier: Int] = [:]

        let result = fixture.retirement { _, context in
            unloadCountByContext[ObjectIdentifier(context), default: 0] += 1
            if context === failingContext {
                throw TestError.unloadFailed
            }
        }.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(lease),
            resources: fixture.resources
        )

        let successfulKey = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: successfulProfileID,
            extensionId: fixture.extensionID
        )
        let failingKey = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: failingProfileID,
            extensionId: fixture.extensionID
        )
        XCTAssertEqual(result.completionStatus, .contextsRemaining)
        XCTAssertFalse(result.completed)
        XCTAssertEqual(result.initialProfileIDs, Set(fixture.profileIDs))
        XCTAssertEqual(result.remainingProfileIDs, [failingProfileID])
        XCTAssertEqual(result.contextOutcomes[successfulKey], .retired)
        XCTAssertEqual(result.contextOutcomes[failingKey], .unloadFailed)
        XCTAssertEqual(
            unloadCountByContext[ObjectIdentifier(successfulContext)],
            1
        )
        XCTAssertEqual(
            unloadCountByContext[ObjectIdentifier(failingContext)],
            1
        )
        XCTAssertNil(
            fixture.profileRuntime.contexts(for: successfulProfileID)[
                fixture.extensionID
            ]
        )
        XCTAssertIdentical(
            fixture.profileRuntime.contexts(for: failingProfileID)[
                fixture.extensionID
            ],
            failingContext
        )
        XCTAssertTrue(fixture.auxiliaryWindows.closedExtensionIDs.isEmpty)
        XCTAssertIdentical(
            fixture.optionsWindows.windows[fixture.extensionID],
            optionsWindow
        )
        XCTAssertEqual(fixture.nativeMessagingPorts.count, 1)
        XCTAssertFalse(port.isDisconnected)
        XCTAssertEqual(
            fixture.actionAnchors.anchorCount(for: fixture.extensionID),
            1
        )
        XCTAssertIdentical(
            fixture.sourceCache.entry(for: fixture.extensionID)?
                .resolution.webExtension,
            fixture.webExtension
        )
        XCTAssertEqual(
            fixture.sourceCache.entry(for: fixture.extensionID)?.key,
            sourceKey
        )
        XCTAssertNotNil(
            fixture.runtimeCatalog.manifest(for: fixture.extensionID)
        )
        XCTAssertTrue(
            fixture.nativeMessagingWakes.runtimeTasksForDrain().isEmpty
        )
        XCTAssertEqual(
            fixture.nativeMessagingLoopGuard.evaluate(
                key: loopGuardKey,
                hostBundleIdentifier: "com.example.unsupported"
            ).retryCountBucket,
            .first
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(lease))
        withExtendedLifetime((anchor, optionsWindow, portSession)) {}
    }

    func testTerminalAdmissionDuringUnloadSupersedesOuterMutationWithoutSharedCleanup()
        async throws {
        let fixture = try await makeFixture(extensionID: "terminal-reentry")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let context = try XCTUnwrap(fixture.contextsByProfile[profileID])
        let anchor = NSView()
        fixture.actionAnchors.setAnchor(
            for: fixture.extensionID,
            anchorView: anchor
        )
        let optionsWindow = NSWindow()
        fixture.optionsWindows.trackPresentedWindow(
            optionsWindow,
            delegate: nil,
            for: fixture.extensionID,
            profileID: profileID
        )
        let port = ScopedRetirementMockPort()
        let portSession = makePortSession(
            port: port,
            extensionID: fixture.extensionID,
            profileID: profileID
        )
        XCTAssertNotNil(
            fixture.nativeMessagingPorts.register(
                handler: portSession,
                port: port,
                extensionId: fixture.extensionID,
                profileId: profileID
            )
        )
        let sourceKey = try await fixture.seedRuntimeBookkeeping()
        fixture.seedNativeMessagingWake(profileID: profileID)
        let loopGuardKey = fixture.seedNativeMessagingLoopGuard(
            profileID: profileID
        )
        let lease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )
        var terminalLease: ExtensionRuntimeTerminalLease?
        var unloadCountByContext: [ObjectIdentifier: Int] = [:]

        let result = fixture.retirement { _, unloadedContext in
            unloadCountByContext[
                ObjectIdentifier(unloadedContext),
                default: 0
            ] += 1
            terminalLease = fixture.mutationRegistry.beginTerminal()
        }.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(lease),
            resources: fixture.resources
        )

        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: fixture.extensionID
        )
        XCTAssertEqual(result.completionStatus, .superseded)
        XCTAssertFalse(result.completed)
        XCTAssertEqual(result.initialProfileIDs, [profileID])
        XCTAssertTrue(result.remainingProfileIDs.isEmpty)
        XCTAssertTrue(result.isQuiescent)
        XCTAssertEqual(result.contextOutcomes[key], .retired)
        XCTAssertEqual(unloadCountByContext[ObjectIdentifier(context)], 1)
        XCTAssertEqual(unloadCountByContext.values.reduce(0, +), 1)
        XCTAssertNil(
            fixture.profileRuntime.contexts(for: profileID)[
                fixture.extensionID
            ]
        )
        XCTAssertFalse(fixture.mutationRegistry.isCurrent(lease))
        XCTAssertTrue(fixture.auxiliaryWindows.closedExtensionIDs.isEmpty)
        XCTAssertIdentical(
            fixture.optionsWindows.windows[fixture.extensionID],
            optionsWindow
        )
        XCTAssertEqual(fixture.nativeMessagingPorts.count, 1)
        XCTAssertFalse(port.isDisconnected)
        XCTAssertEqual(
            fixture.actionAnchors.anchorCount(for: fixture.extensionID),
            1
        )
        XCTAssertIdentical(
            fixture.sourceCache.entry(for: fixture.extensionID)?
                .resolution.webExtension,
            fixture.webExtension
        )
        XCTAssertEqual(
            fixture.sourceCache.entry(for: fixture.extensionID)?.key,
            sourceKey
        )
        XCTAssertNotNil(
            fixture.runtimeCatalog.manifest(for: fixture.extensionID)
        )
        XCTAssertTrue(
            fixture.nativeMessagingWakes.runtimeTasksForDrain().isEmpty
        )
        XCTAssertEqual(
            fixture.nativeMessagingLoopGuard.evaluate(
                key: loopGuardKey,
                hostBundleIdentifier: "com.example.unsupported"
            ).retryCountBucket,
            .first
        )
        XCTAssertTrue(
            fixture.mutationRegistry.finish(try XCTUnwrap(terminalLease))
        )
        withExtendedLifetime((anchor, optionsWindow, portSession)) {}
    }

    func testReentrantReplacementIsRetiredWhileMutationRemainsSealed()
        async throws {
        let fixture = try await makeFixture(extensionID: "reentrant")
        let profileID = try XCTUnwrap(fixture.profileIDs.first)
        let original = try XCTUnwrap(fixture.contextsByProfile[profileID])
        let replacement = WKWebExtensionContext(for: fixture.webExtension)
        let lease = try XCTUnwrap(
            fixture.mutationRegistry.begin(
                extensionID: fixture.extensionID,
                operation: .disable
            )
        )
        var unloadedContexts: [WKWebExtensionContext] = []
        var leaseWasCurrentDuringUnload: [Bool] = []
        var unleasedLoadWasRejectedDuringUnload: [Bool] = []
        var competingMutationWasRejected = false

        let result = fixture.retirement { _, context in
            unloadedContexts.append(context)
            leaseWasCurrentDuringUnload.append(
                fixture.mutationRegistry.isCurrent(lease)
            )
            unleasedLoadWasRejectedDuringUnload.append(
                fixture.mutationRegistry.admitsLoad(
                    extensionID: fixture.extensionID,
                    lease: nil
                ) == false
            )
            if context === original {
                _ = fixture.profileRuntime.setContext(
                    replacement,
                    extensionId: fixture.extensionID,
                    profileId: profileID
                )
                competingMutationWasRejected =
                    fixture.mutationRegistry.begin(
                        extensionID: fixture.extensionID,
                        operation: .enable
                    ) == nil
            }
        }.retire(
            extensionID: fixture.extensionID,
            cause: .disabled,
            admission: .mutation(lease),
            resources: fixture.resources
        )

        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profileID,
            extensionId: fixture.extensionID
        )
        XCTAssertTrue(result.isQuiescent)
        XCTAssertEqual(result.contextOutcomes[key], .retired)
        XCTAssertEqual(unloadedContexts.count, 2)
        XCTAssertIdentical(unloadedContexts[0], original)
        XCTAssertIdentical(unloadedContexts[1], replacement)
        XCTAssertEqual(leaseWasCurrentDuringUnload, [true, true])
        XCTAssertEqual(unleasedLoadWasRejectedDuringUnload, [true, true])
        XCTAssertTrue(competingMutationWasRejected)
        XCTAssertNil(
            fixture.profileRuntime.contexts(for: profileID)[
                fixture.extensionID
            ]
        )
        XCTAssertEqual(
            fixture.auxiliaryWindows.closedExtensionIDs,
            [fixture.extensionID]
        )
        XCTAssertTrue(fixture.mutationRegistry.finish(lease))
    }

    private func makeFixture(
        extensionID: String,
        profileCount: Int = 1
    ) async throws -> ScopedRetirementFixture {
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
                "name": "Scoped Runtime Retirement",
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
        return ScopedRetirementFixture(
            extensionID: extensionID,
            webExtension: webExtension,
            profileCount: profileCount
        )
    }

    private func makeRollbackTransaction(
        fixture: ScopedRetirementFixture,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease
    ) throws -> (
        rollback: ExtensionRuntimeRollback,
        loadedContext: ExtensionLoadedContext
    ) {
        let context = try XCTUnwrap(fixture.contextsByProfile[profileID])
        let controller = try XCTUnwrap(
            fixture.controllersByProfile[profileID]
        )
        let receipt = try XCTUnwrap(
            fixture.profileRuntime.contextBindingReceipt(
                extensionId: fixture.extensionID,
                profileId: profileID
            )
        )
        let claim = fixture.loadRegistry.begin(for: receipt.key)
        let contextRetirement = ExtensionContextRetirement(
            profileRuntime: fixture.profileRuntime,
            backgroundRuntimeState: fixture.backgroundRuntimeState,
            runtimeResidency: fixture.runtimeResidency,
            errorObservation: fixture.errorObservation,
            diagnostics: ExtensionRuntimeDiagnostics(),
            unloadContext: { _, _ in },
            isLoadedContext: { _, _ in false }
        )
        let authority = ExtensionLoadedContextAuthority(
            profileRuntime: fixture.profileRuntime,
            mutationRegistry: fixture.mutationRegistry,
            loadRegistry: fixture.loadRegistry,
            contextRetirement: contextRetirement
        )
        let runtimeRetirement = ExtensionRuntimeRetirement(
            scopedRetirement: fixture.retirement { _, _ in },
            actionSurfaces: { nil },
            resources: { fixture.resources }
        )
        return (
            ExtensionRuntimeRollback(
                authority: authority,
                retirement: runtimeRetirement
            ),
            ExtensionLoadedContext(
                context: context,
                controller: controller,
                bindingReceipt: receipt,
                loadClaim: claim,
                mutationLease: mutationLease
            )
        )
    }

    private func makePortSession(
        port: any SumiNativeMessagingPortControlling,
        extensionID: String,
        profileID: UUID
    ) -> SumiNativeMessagingPortSession {
        SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: extensionID,
            profileId: profileID,
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            },
            portInactivityTimeout: .seconds(3_600)
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ScopedRetirementFixture {
    let extensionID: String
    let webExtension: WKWebExtension
    let profileIDs: [UUID]
    let profileRuntime: ExtensionProfileRuntime
    let controllersByProfile: [UUID: WKWebExtensionController]
    let contextsByProfile: [UUID: WKWebExtensionContext]
    let mutationRegistry = ExtensionRuntimeMutationRegistry()
    let loadRegistry = ExtensionContextLoadRegistry()
    private let sourceMutationRegistry = ExtensionRuntimeMutationRegistry()
    private let sourceLoadRegistry = ExtensionContextLoadRegistry()
    let backgroundRuntimeState = ExtensionBackgroundRuntimeStateOwner()
    let runtimeCatalog = ExtensionRuntimeCatalog()
    let runtimeResidency = ExtensionRuntimeResidencyAuthority()
    let errorObservation = ExtensionContextErrorObservation(
        recordErrorUpdateDuration: { _, _ in },
        trace: { _ in }
    )
    let nativeMessagingPorts = ExtensionNativeMessagingPortRegistry()
    let optionsWindows = ExtensionOptionsWindowService()
    let actionAnchors = ExtensionActionAnchorStore()
    let auxiliaryWindows = ScopedRetirementAuxiliaryWindowSpy()
    let nativeMessagingWakes = ExtensionNativeMessagingBackgroundWakeOwner()
    let nativeMessagingLoopGuard: SumiNativeMessagingRelayLoopGuard
    let nativeMessagingRelay: SumiNativeMessagingRelay

    private lazy var sourceAdmission = ExtensionContextLoadAdmission(
        mutationRegistry: sourceMutationRegistry,
        loadRegistry: sourceLoadRegistry
    )
    lazy var sourceCache = WebExtensionRuntimeSourceCache(
        admission: sourceAdmission,
        makeSource: { [webExtension] sourceKind, _, _ in
            WebExtensionRuntimeSourceCache.Resolution(
                webExtension: webExtension,
                loadSource: sourceKind == .safariAppExtension
                    ? .originalAppexBundle
                    : .copiedPackage
            )
        }
    )

    var resources: ExtensionScopedRuntimeRetirement.Resources {
        .init(
            auxiliaryWindows: auxiliaryWindows,
            nativeMessagingWakes: nativeMessagingWakes,
            nativeMessagingRelay: nativeMessagingRelay
        )
    }

    init(
        extensionID: String,
        webExtension: WKWebExtension,
        profileCount: Int
    ) {
        precondition(profileCount > 0)
        self.extensionID = extensionID
        self.webExtension = webExtension
        let nativeMessagingLoopGuard = SumiNativeMessagingRelayLoopGuard()
        self.nativeMessagingLoopGuard = nativeMessagingLoopGuard
        self.nativeMessagingRelay = SumiNativeMessagingRelay(
            loopGuard: nativeMessagingLoopGuard
        )
        let profileIDs = (0..<profileCount).map { _ in UUID() }
        self.profileIDs = profileIDs
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileIDs.first
        )
        var controllers: [UUID: WKWebExtensionController] = [:]
        var contexts: [UUID: WKWebExtensionContext] = [:]
        for profileID in profileIDs {
            let controller = WKWebExtensionController(
                configuration: .init(identifier: UUID())
            )
            let context = WKWebExtensionContext(for: webExtension)
            controllers[profileID] = controller
            contexts[profileID] = context
            profileRuntime.setController(controller, for: profileID)
            _ = profileRuntime.setContext(
                context,
                extensionId: extensionID,
                profileId: profileID
            )
        }
        self.profileRuntime = profileRuntime
        self.controllersByProfile = controllers
        self.contextsByProfile = contexts
    }

    func retirement(
        unload: @escaping @MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) throws -> Void
    ) -> ExtensionScopedRuntimeRetirement {
        let contextRetirement = ExtensionContextRetirement(
            profileRuntime: profileRuntime,
            backgroundRuntimeState: backgroundRuntimeState,
            runtimeResidency: runtimeResidency,
            errorObservation: errorObservation,
            diagnostics: ExtensionRuntimeDiagnostics(),
            unloadContext: unload,
            isLoadedContext: { _, _ in true }
        )
        return ExtensionScopedRuntimeRetirement(
            profileRuntime: profileRuntime,
            mutationRegistry: mutationRegistry,
            loadRegistry: loadRegistry,
            contextRetirement: contextRetirement,
            runtimeCatalog: runtimeCatalog,
            runtimeResidency: runtimeResidency,
            sourceCache: sourceCache,
            errorObservation: errorObservation,
            nativeMessagingPorts: nativeMessagingPorts,
            optionsWindows: optionsWindows,
            actionAnchors: actionAnchors,
            diagnostics: ExtensionRuntimeDiagnostics()
        )
    }

    func seedNativeMessagingWake(profileID: UUID) {
        nativeMessagingWakes.scheduleWake(
            wakeKey: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionID,
                profileId: profileID
            ),
            operation: "test",
            wake: {
                try await Task.sleep(for: .seconds(3_600))
            },
            logFailure: { _, _ in }
        )
    }

    func seedNativeMessagingLoopGuard(
        profileID: UUID
    ) -> SumiNativeMessagingRelayLoopGuard.SessionKey {
        let key = SumiNativeMessagingRelayLoopGuard.SessionKey(
            profileId: profileID,
            extensionId: extensionID,
            applicationIdentifier: "com.example.unsupported"
        )
        nativeMessagingLoopGuard.recordCompanionAppProtocolUnknown(
            key: key,
            launchAttempted: true
        )
        return key
    }

    @discardableResult
    func seedRuntimeBookkeeping() async throws
        -> WebExtensionRuntimeSourceKey {
        let claim = sourceLoadRegistry.begin(
            for: .init(
                profileId: profileIDs[0],
                extensionId: extensionID
            )
        )
        defer { _ = sourceLoadRegistry.finishIfCurrent(claim) }
        _ = try await sourceCache.resolve(
            extensionID: extensionID,
            sourceKind: .directory,
            sourceBundlePath: "/tmp/source",
            packageRoot: URL(
                fileURLWithPath: "/tmp/package",
                isDirectory: true
            ),
            claim: claim,
            mutationLease: nil
        )
        let sourceKey = try XCTUnwrap(
            sourceCache.entry(for: extensionID)?.key
        )
        runtimeCatalog.recordManifest(
            ["manifest_version": 3],
            for: extensionID
        )
        for profileID in profileIDs {
            let key = ExtensionRuntimeResidencyState.ScopedKey(
                profileId: profileID,
                extensionId: extensionID
            )
            runtimeCatalog.recordLoadError(
                NSError(
                    domain: "ExtensionScopedRuntimeRetirementTests",
                    code: 1
                ),
                extensionID: extensionID,
                profileID: profileID
            )
            runtimeResidency.touch(
                extensionID: extensionID,
                profileID: profileID
            )
        }
        return sourceKey
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ScopedRetirementAuxiliaryWindowSpy:
    ExtensionAuxiliaryWindowControl {
    var closedExtensionIDs: [String] = []
    var closeReasons: [AuxiliaryWindowCloseReason] = []

    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession? {
        nil
    }

    func auxiliaryWindowSession(
        for sessionId: UUID
    ) -> AuxiliaryWindowSession? {
        nil
    }

    func auxiliaryWindowSession(
        for window: NSWindow
    ) -> AuxiliaryWindowSession? {
        nil
    }

    func focusedExtensionMiniWindowAdapter(
        forOwnerExtensionID ownerExtensionID: String
    ) -> ExtensionMiniWindowAdapter? {
        nil
    }

    func recordAuxiliaryWindowSessionFocus(_ sessionId: UUID) {}

    func focusAuxiliaryWindowSession(_ sessionId: UUID) {}

    func closeAuxiliaryWindowSession(_ session: AuxiliaryWindowSession) {}

    func closeAuxiliaryWindowWebView(_ webView: WKWebView) {}

    func closeAuxiliaryWindowSessions(
        forExtensionId extensionId: String,
        reason: AuxiliaryWindowCloseReason
    ) {
        closedExtensionIDs.append(extensionId)
        closeReasons.append(reason)
    }

    func containsAuxiliaryWebView(_ webView: WKWebView) -> Bool {
        false
    }
}

@MainActor
private final class ScopedRetirementMockPort:
    SumiNativeMessagingPortControlling {
    var applicationIdentifier: String?
    var isDisconnected = false
    var messageHandler: ((Any?, (any Error)?) -> Void)?
    var disconnectHandler: (((any Error)?) -> Void)?

    func disconnect() {
        isDisconnected = true
        disconnectHandler?(nil)
    }

    func disconnect(throwing error: (any Error)?) {
        isDisconnected = true
        disconnectHandler?(error)
    }
}
