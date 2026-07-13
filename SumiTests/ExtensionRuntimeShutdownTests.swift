import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeShutdownTests: XCTestCase {
    private enum TestError: Error {
        case failed
    }

    func testIrreversibleMutationDefersShutdownWithoutCancellingRuntime()
        throws {
        let profile = Profile(name: "Irreversible Mutation Profile")
        let manager = try makeManager(
            profile: profile,
            browserConfiguration: BrowserConfiguration()
        ).manager
        let lease = try XCTUnwrap(
            manager.runtimeMutationRegistry.begin(
                extensionID: "uninstalling-extension",
                operation: .uninstall
            )
        )
        XCTAssertTrue(
            manager.runtimeMutationRegistry.enterIrreversiblePhase(lease)
        )
        let generation = manager.runtimeSession.extensionLoadGeneration

        let result = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.irreversible"
        )

        XCTAssertEqual(result.completionStatus, .mutationInProgress)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.contextOutcomes.isEmpty)
        XCTAssertTrue(result.remainingBindings.isEmpty)
        XCTAssertTrue(manager.runtimeMutationRegistry.isCurrent(lease))
        XCTAssertEqual(
            manager.runtimeSession.extensionLoadGeneration,
            generation,
            "a rejected shutdown must not cancel in-flight runtime work"
        )
        XCTAssertTrue(manager.runtimeMutationRegistry.finish(lease))
    }

    func testColdRuntimeTeardownDoesNotMaterializePublicationLifecycle()
        throws {
        let fixture = try makeManager(
            profile: Profile(name: "Cold Teardown Profile"),
            browserConfiguration: BrowserConfiguration()
        )
        let manager = fixture.manager
        XCTAssertNil(manager.loadedRuntimePublicationReconciler)

        _ = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.cold"
        )

        XCTAssertNil(manager.loadedRuntimePublicationReconciler)
    }

    func testRetainedPublicationCollaboratorsDoNotRetainExtensionManager()
        throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Publication Lifetime Profile")
        var manager: ExtensionManager? = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            extensionPreferences: UserDefaults(
                suiteName: UUID().uuidString
            )!
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager?.attach(browserManager: browserManager)
        weak var weakManager = manager
        let reconciler = try XCTUnwrap(
            manager?.runtimePublicationReconciler
        )
        let publications = try XCTUnwrap(manager?.windowPublications)
        let admission = try XCTUnwrap(manager?.tabPublicationAdmission)

        manager = nil

        XCTAssertNil(weakManager)
        withExtendedLifetime(
            (reconciler, publications, admission, browserManager)
        ) {}
    }

    func testFullRuntimeTeardownReleasesControllerAndClearsBookkeeping() throws {
        let profile = Profile(name: "Teardown Profile")
        let browserConfiguration = BrowserConfiguration()
        let fixture = try makeManager(
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = fixture.manager
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true,
            profileId: profile.id
        )
        let controller = try XCTUnwrap(manager.profileRuntime.controllersByProfile[profile.id])
        browserConfiguration.webViewConfiguration.webExtensionController = controller

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        manager.extensionsLoaded = true
        manager.runtimeSession.runtimeState = .ready
        manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions = true
        manager.runtimeSession.loadedExtensionManifests["alpha"] = ["manifest_version": 3]
        manager.actionStatesByExtensionID["alpha"] = BrowserExtensionActionSurfaceState(
            extensionID: "alpha",
            label: "Alpha",
            badgeText: "1",
            hasUnreadBadgeText: true,
            isEnabled: true,
            presentsPopup: true,
            icon: nil
        )
        manager.runtimeSession.lastExtensionLoadErrors["\(profile.id):alpha"] = TestError.failed
        manager.runtimeSession.extensionRuntimeResidencyState.touch(
            extensionId: "alpha",
            profileId: profile.id
        )
        manager.runtimeSession.runtimeMetricsByExtensionID["alpha"] =
            ExtensionManager.ExtensionRuntimeMetrics()
        manager.contextErrorObservation.seedLoggedErrorFingerprintForTesting(
            "fingerprint",
            extensionId: "alpha",
            profileId: profile.id
        )
        manager.actionAnchorStore.setAnchor(for: "alpha", anchorView: anchorView)
        let nativePort = TeardownMockPort()
        _ = manager.nativeMessagingPortRegistry.register(
            handler: makePortSession(port: nativePort, extensionId: "alpha"),
            port: nativePort,
            extensionId: "alpha",
            profileId: profile.id
        )

        let generationBeforeTeardown = manager.runtimeSession.extensionLoadGeneration

        let result = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.full"
        )

        XCTAssertTrue(result.completed)
        XCTAssertEqual(manager.runtimeSession.extensionLoadGeneration, generationBeforeTeardown + 1)
        XCTAssertTrue(manager.profileRuntime.controllersByProfile.isEmpty)
        XCTAssertNil(browserConfiguration.webViewConfiguration.webExtensionController)
        XCTAssertFalse(manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertEqual(
            manager.runtimeSession.runtimeState,
            manager.isExtensionSupportAvailable ? .idle : .unavailable
        )
        XCTAssertFalse(manager.extensionsLoaded)
        XCTAssertTrue(manager.runtimeSession.loadedExtensionManifests.isEmpty)
        XCTAssertTrue(manager.actionStatesByExtensionID.isEmpty)
        XCTAssertTrue(manager.runtimeSession.lastExtensionLoadErrors.isEmpty)
        XCTAssertTrue(manager.runtimeSession.extensionRuntimeResidencyState.liveContextKeys.isEmpty)
        XCTAssertTrue(manager.runtimeSession.runtimeMetricsByExtensionID.isEmpty)
        XCTAssertFalse(manager.contextErrorObservation.hasLoggedErrorFingerprints)
        XCTAssertFalse(
            manager.controllerProvisioningOwner.hasExtensionPageUserContentControllers
        )
        XCTAssertTrue(manager.actionAnchorStore.isEmpty)
        XCTAssertEqual(manager.nativeMessagingPortRegistry.count, 0)
        XCTAssertTrue(manager.nativeMessagingPortRegistry.extensionIDs.isEmpty)
    }

    func testIncompleteShutdownKeepsTerminalAdmissionSealedUntilSuccessfulRetry()
        async throws {
        let profile = Profile(name: "Retried Teardown Profile")
        let browserConfiguration = BrowserConfiguration()
        let fixture = try makeManager(
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = fixture.manager
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        let extensionID = "retry-runtime-shutdown"
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let webExtension = try await makeWebExtension()
        let extensionContext = WKWebExtensionContext(for: webExtension)
        manager.profileRuntime.setController(controller, for: profile.id)
        _ = manager.profileRuntime.setContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        browserConfiguration.webViewConfiguration.webExtensionController =
            controller

        manager.extensionsLoaded = true
        manager.runtimeSession.runtimeState = .ready
        manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions = true
        manager.runtimeSession.loadedExtensionManifests[extensionID] = [
            "manifest_version": 3
        ]
        manager.runtimeSession.runtimeMetricsByExtensionID[extensionID] =
            ExtensionManager.ExtensionRuntimeMetrics()
        manager.actionStatesByExtensionID[extensionID] =
            BrowserExtensionActionSurfaceState(
                extensionID: extensionID,
                label: "Retry",
                badgeText: "",
                hasUnreadBadgeText: false,
                isEnabled: true,
                presentsPopup: false,
                icon: nil
            )

        var unloadShouldFail = true
        installShutdownCollaborators(on: manager) { _, _ in
            if unloadShouldFail {
                throw TestError.failed
            }
        }

        let generationBeforeShutdown =
            manager.runtimeSession.extensionLoadGeneration
        let incomplete = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.incomplete"
        )

        XCTAssertEqual(incomplete.completionStatus, .contextsRemaining)
        XCTAssertFalse(incomplete.completed)
        XCTAssertEqual(
            incomplete.remainingBindings,
            [
                ExtensionRuntimeResidencyState.ScopedKey(
                    profileId: profile.id,
                    extensionId: extensionID
                )
            ]
        )
        XCTAssertFalse(
            manager.runtimeMutationRegistry.admitsLoad(
                extensionID: extensionID,
                lease: nil
            )
        )
        XCTAssertNil(
            manager.runtimeMutationRegistry.begin(
                extensionID: "another-extension",
                operation: .enable
            )
        )
        XCTAssertIdentical(
            manager.profileRuntime.contexts(for: profile.id)[extensionID],
            extensionContext
        )
        XCTAssertIdentical(
            manager.profileRuntime.controllersByProfile[profile.id],
            controller
        )
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertEqual(manager.runtimeSession.runtimeState, .ready)
        XCTAssertTrue(manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertNotNil(
            manager.runtimeSession.loadedExtensionManifests[extensionID]
        )
        XCTAssertNotNil(
            manager.runtimeSession.runtimeMetricsByExtensionID[extensionID]
        )
        XCTAssertNotNil(manager.actionStatesByExtensionID[extensionID])
        XCTAssertTrue(manager.extensionsLoaded)

        unloadShouldFail = false
        let completed = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.retry"
        )

        XCTAssertEqual(completed.completionStatus, .completed)
        XCTAssertTrue(completed.completed)
        XCTAssertTrue(completed.remainingBindings.isEmpty)
        XCTAssertEqual(
            completed.contextOutcomes[
                ExtensionRuntimeResidencyState.ScopedKey(
                    profileId: profile.id,
                    extensionId: extensionID
                )
            ],
            .retired
        )
        XCTAssertTrue(
            manager.runtimeMutationRegistry.admitsLoad(
                extensionID: extensionID,
                lease: nil
            )
        )
        let reopenedMutation = try XCTUnwrap(
            manager.runtimeMutationRegistry.begin(
                extensionID: extensionID,
                operation: .enable
            )
        )
        XCTAssertTrue(manager.runtimeMutationRegistry.finish(reopenedMutation))
        XCTAssertTrue(manager.profileRuntime.contexts(for: profile.id).isEmpty)
        XCTAssertTrue(manager.profileRuntime.controllersByProfile.isEmpty)
        XCTAssertNil(
            browserConfiguration.webViewConfiguration.webExtensionController
        )
        XCTAssertEqual(
            manager.runtimeSession.runtimeState,
            manager.isExtensionSupportAvailable ? .idle : .unavailable
        )
        XCTAssertFalse(manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertTrue(manager.runtimeSession.loadedExtensionManifests.isEmpty)
        XCTAssertTrue(manager.runtimeSession.runtimeMetricsByExtensionID.isEmpty)
        XCTAssertTrue(manager.actionStatesByExtensionID.isEmpty)
        XCTAssertFalse(manager.extensionsLoaded)
        XCTAssertEqual(
            manager.runtimeSession.extensionLoadGeneration,
            generationBeforeShutdown + 2
        )
    }

    func testSupersededShutdownPreservesBookkeepingControllerAndNewTerminalSeal()
        async throws {
        let profile = Profile(name: "Superseded Teardown Profile")
        let browserConfiguration = BrowserConfiguration()
        let fixture = try makeManager(
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = fixture.manager
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        let extensionID = "superseded-runtime-shutdown"
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let extensionContext = WKWebExtensionContext(
            for: try await makeWebExtension()
        )
        manager.profileRuntime.setController(controller, for: profile.id)
        _ = manager.profileRuntime.setContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        browserConfiguration.webViewConfiguration.webExtensionController =
            controller
        manager.extensionsLoaded = true
        manager.runtimeSession.runtimeState = .ready
        manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions = true
        manager.runtimeSession.loadedExtensionManifests[extensionID] = [
            "manifest_version": 3
        ]
        manager.runtimeSession.runtimeMetricsByExtensionID[extensionID] =
            ExtensionManager.ExtensionRuntimeMetrics()
        manager.actionStatesByExtensionID[extensionID] =
            BrowserExtensionActionSurfaceState(
                extensionID: extensionID,
                label: "Superseded",
                badgeText: "",
                hasUnreadBadgeText: false,
                isEnabled: true,
                presentsPopup: false,
                icon: nil
            )

        let mutationRegistry = manager.runtimeMutationRegistry
        var replacementTerminalLease: ExtensionRuntimeTerminalLease?
        installShutdownCollaborators(on: manager) { _, _ in
            replacementTerminalLease = mutationRegistry.beginTerminal()
        }

        let result = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.superseded"
        )

        let key = ExtensionRuntimeResidencyState.ScopedKey(
            profileId: profile.id,
            extensionId: extensionID
        )
        XCTAssertEqual(result.completionStatus, .superseded)
        XCTAssertFalse(result.completed)
        XCTAssertEqual(result.contextOutcomes[key], .retired)
        XCTAssertTrue(result.remainingBindings.isEmpty)
        XCTAssertNil(
            manager.profileRuntime.contexts(for: profile.id)[extensionID]
        )
        XCTAssertIdentical(
            manager.profileRuntime.controllersByProfile[profile.id],
            controller
        )
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertEqual(manager.runtimeSession.runtimeState, .ready)
        XCTAssertTrue(manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertNotNil(
            manager.runtimeSession.loadedExtensionManifests[extensionID]
        )
        XCTAssertNotNil(
            manager.runtimeSession.runtimeMetricsByExtensionID[extensionID]
        )
        XCTAssertNotNil(manager.actionStatesByExtensionID[extensionID])
        XCTAssertTrue(manager.extensionsLoaded)

        let activeTerminalLease = try XCTUnwrap(
            replacementTerminalLease
        )
        XCTAssertTrue(mutationRegistry.isCurrent(activeTerminalLease))
        XCTAssertFalse(
            mutationRegistry.admitsLoad(extensionID: extensionID, lease: nil)
        )
        XCTAssertNil(
            mutationRegistry.begin(
                extensionID: extensionID,
                operation: .enable
            )
        )
        XCTAssertTrue(mutationRegistry.finish(activeTerminalLease))
    }

    private func makePortSession(
        port: any SumiNativeMessagingPortControlling,
        extensionId: String
    ) -> SumiNativeMessagingPortSession {
        SumiNativeMessagingPortSession(
            port: port,
            adapter: nil,
            extensionId: extensionId,
            hostBundleIdentifier: "com.example.host",
            resolverBucket: .explicitApplicationIdentifier,
            logDiagnostic: { _ in /* no-op */ },
            companionProtocolErrorProvider: {
                SumiNativeMessagingErrorMapper.relayError(
                    code: .companionAppProtocolUnknown,
                    diagnostic: nil
                )
            }
        )
    }

    private func makeManager(
        profile: Profile,
        browserConfiguration: BrowserConfiguration
    ) throws -> (container: ModelContainer, manager: ExtensionManager) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            extensionPreferences: UserDefaults(suiteName: UUID().uuidString)!
        )
        return (container, manager)
    }

    private func makeWebExtension() async throws -> WKWebExtension {
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
                "name": "Runtime Shutdown Retry",
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        return try await WKWebExtension(resourceBaseURL: directory)
    }

    private func installShutdownCollaborators(
        on manager: ExtensionManager,
        unloadContext: @escaping @MainActor (
            WKWebExtensionController,
            WKWebExtensionContext
        ) throws -> Void
    ) {
        let contextRetirement = ExtensionContextRetirement(
            profileRuntime: manager.profileRuntime,
            backgroundRuntimeState: manager.backgroundRuntimeStateOwner,
            runtimeSession: manager.runtimeSession,
            errorObservation: manager.contextErrorObservation,
            diagnostics: manager.runtimeDiagnostics,
            unloadContext: unloadContext,
            isLoadedContext: { _, _ in true }
        )
        let scopedRetirement = ExtensionScopedRuntimeRetirement(
            profileRuntime: manager.profileRuntime,
            mutationRegistry: manager.runtimeMutationRegistry,
            loadRegistry: manager.contextLoadRegistry,
            contextRetirement: contextRetirement,
            runtimeSession: manager.runtimeSession,
            errorObservation: manager.contextErrorObservation,
            nativeMessagingPorts: manager.nativeMessagingPortRegistry,
            optionsWindows: manager.optionsWindows,
            actionAnchors: manager.actionAnchorStore,
            diagnostics: manager.runtimeDiagnostics
        )
        manager.contextRetirement = contextRetirement
        manager.scopedRuntimeRetirement = scopedRetirement
        manager.runtimeShutdown = ExtensionRuntimeShutdown(
            activityCancellation: manager.runtimeActivityCancellation,
            mutationRegistry: manager.runtimeMutationRegistry,
            scopedRetirement: scopedRetirement,
            bookkeepingReset: manager.runtimeBookkeepingReset,
            controllerRelease: manager.controllerRuntimeRelease,
            profileRuntime: manager.profileRuntime,
            runtimeSession: manager.runtimeSession,
            errorObservation: manager.contextErrorObservation,
            optionsWindows: manager.optionsWindows,
            actionAnchors: manager.actionAnchorStore,
            nativeMessagingPorts: manager.nativeMessagingPortRegistry,
            diagnostics: manager.runtimeDiagnostics
        )
    }
}

@MainActor
private final class TeardownMockPort: SumiNativeMessagingPortControlling {
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
