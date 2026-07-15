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
        let fixture = try makeManager(
            profile: profile,
            browserConfiguration: BrowserConfiguration()
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        let lease = try XCTUnwrap(
            inspection.contextCoordination.mutations.begin(
                extensionID: "uninstalling-extension",
                operation: .uninstall
            )
        )
        XCTAssertTrue(
            inspection.contextCoordination.mutations.enterIrreversiblePhase(lease)
        )
        let generation = inspection.runtimeAuthorities.loadRevisions.issue()

        let result = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.irreversible"
        )

        XCTAssertEqual(result.completionStatus, .mutationInProgress)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.contextOutcomes.isEmpty)
        XCTAssertTrue(result.remainingBindings.isEmpty)
        XCTAssertTrue(inspection.contextCoordination.mutations.isCurrent(lease))
        XCTAssertEqual(
            inspection.runtimeAuthorities.loadRevisions.issue(),
            generation,
            "a rejected shutdown must not cancel in-flight runtime work"
        )
        XCTAssertTrue(inspection.contextCoordination.mutations.finish(lease))
    }

    func testColdRuntimeTeardownDoesNotMaterializePublicationLifecycle()
        throws {
        let fixture = try makeManager(
            profile: Profile(name: "Cold Teardown Profile"),
            browserConfiguration: BrowserConfiguration()
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        XCTAssertNil(
            inspection.normalTabs.deferredRuntime
                .loadedInitialDocumentRuntimePreparationOwner
        )
        XCTAssertFalse(fixture.attachedRuntime.hasInstalledRuntime)

        _ = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.cold"
        )

        XCTAssertNil(
            inspection.normalTabs.deferredRuntime
                .loadedInitialDocumentRuntimePreparationOwner
        )
        XCTAssertFalse(fixture.attachedRuntime.hasInstalledRuntime)
    }

    func testRetainedPublicationCollaboratorsDoNotRetainExtensionManager()
        throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Publication Lifetime Profile")
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        var manager: ExtensionManager? = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: BrowserConfiguration(),
            extensionPreferences: UserDefaults(
                suiteName: UUID().uuidString
            )!,
            attachedRuntimeDidInstall: attachedRuntime.install
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager?.attach(browserManager: browserManager)
        weak var weakManager = manager
        let reconciler = attachedRuntime.runtime.publications.reconciler
        let publications = attachedRuntime.runtime.publications
            .windowPublications
        let admission = attachedRuntime.runtime.normalTabs.tabOpening

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
        let inspection = fixture.inspection
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install,
            profileId: profile.id
        )
        let controller = try XCTUnwrap(inspection.contextState.profiles.controllersByProfile[profile.id])
        browserConfiguration.webViewConfiguration.webExtensionController = controller

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        inspection.runtimeAuthorities.lifecycle.updateReadiness(isReady: true)
        inspection.runtimeAuthorities.demand.recordRuntimeDemandWithoutEnabledExtensions()
        inspection.runtimeAuthorities.catalog.recordManifest(
            ["manifest_version": 3],
            for: "alpha"
        )
        inspection.actionSurfaces.publication.setActionSurfaceState(
            BrowserExtensionActionSurfaceState(
                extensionID: "alpha",
                label: "Alpha",
                badgeText: "1",
                hasUnreadBadgeText: true,
                isEnabled: true,
                presentsPopup: true,
                icon: nil
            ),
            extensionID: "alpha"
        )
        inspection.runtimeAuthorities.catalog.recordLoadError(
            TestError.failed,
            extensionID: "alpha",
            profileID: profile.id
        )
        inspection.runtimeAuthorities.residency.touch(
            extensionID: "alpha",
            profileID: profile.id
        )
        inspection.runtimeAuthorities.metrics.recordManifestValidationDuration(0, for: "alpha")
        inspection.contextState.errors.seedLoggedErrorFingerprintForTesting(
            "fingerprint",
            extensionId: "alpha",
            profileId: profile.id
        )
        inspection.popups.actionAnchors.setAnchor(for: "alpha", anchorView: anchorView)
        let nativePort = TeardownMockPort()
        _ = inspection.nativeMessaging.ports.register(
            handler: makePortSession(port: nativePort, extensionId: "alpha"),
            port: nativePort,
            extensionId: "alpha",
            profileId: profile.id
        )

        let generationBeforeTeardown = inspection.runtimeAuthorities.loadRevisions.issue()

        let result = manager.shutDownExtensionRuntime(
            reason: "ExtensionRuntimeShutdownTests.full"
        )

        XCTAssertTrue(result.completed)
        XCTAssertEqual(
            inspection.runtimeAuthorities.loadRevisions.issue().generation,
            generationBeforeTeardown.generation + 1
        )
        XCTAssertTrue(inspection.contextState.profiles.controllersByProfile.isEmpty)
        XCTAssertNil(browserConfiguration.webViewConfiguration.webExtensionController)
        XCTAssertFalse(
            inspection.runtimeAuthorities.demand.hasRuntimeDemandWithoutEnabledExtensions
        )
        XCTAssertEqual(
            inspection.runtimeAuthorities.lifecycle.state,
            manager.isExtensionSupportAvailable ? .idle : .unavailable
        )
        XCTAssertFalse(inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertTrue(inspection.runtimeAuthorities.catalog.isEmpty)
        XCTAssertTrue(
            inspection.actionSurfaces.publication
                .actionStatesByExtensionID.isEmpty
        )
        XCTAssertTrue(inspection.runtimeAuthorities.residency.liveContextKeys.isEmpty)
        XCTAssertTrue(inspection.runtimeAuthorities.metrics.isEmpty)
        XCTAssertFalse(inspection.contextState.errors.hasLoggedErrorFingerprints)
        XCTAssertFalse(
            inspection.controller.provisioning.hasExtensionPageUserContentControllers
        )
        XCTAssertTrue(inspection.popups.actionAnchors.isEmpty)
        XCTAssertEqual(inspection.nativeMessaging.ports.count, 0)
        XCTAssertTrue(inspection.nativeMessaging.ports.extensionIDs.isEmpty)
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
        let inspection = fixture.inspection
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        let extensionID = "retry-runtime-shutdown"
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let webExtension = try await makeWebExtension()
        let extensionContext = WKWebExtensionContext(for: webExtension)
        inspection.contextState.profiles.setController(controller, for: profile.id)
        _ = inspection.contextState.profiles.setContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        browserConfiguration.webViewConfiguration.webExtensionController =
            controller

        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        inspection.runtimeAuthorities.lifecycle.updateReadiness(isReady: true)
        inspection.runtimeAuthorities.demand.recordRuntimeDemandWithoutEnabledExtensions()
        inspection.runtimeAuthorities.catalog.recordManifest(
            ["manifest_version": 3],
            for: extensionID
        )
        inspection.runtimeAuthorities.metrics.recordManifestValidationDuration(
            0,
            for: extensionID
        )
        inspection.actionSurfaces.publication.setActionSurfaceState(
            BrowserExtensionActionSurfaceState(
                extensionID: extensionID,
                label: "Retry",
                badgeText: "",
                hasUnreadBadgeText: false,
                isEnabled: true,
                presentsPopup: false,
                icon: nil
            ),
            extensionID: extensionID
        )

        var unloadShouldFail = true
        fixture.unloadBehavior.handler = { _, _ in
            if unloadShouldFail {
                throw TestError.failed
            }
        }

        let generationBeforeShutdown =
            inspection.runtimeAuthorities.loadRevisions.issue()
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
                ),
            ]
        )
        XCTAssertFalse(
            inspection.contextCoordination.mutations.admitsLoad(
                extensionID: extensionID,
                lease: nil
            )
        )
        XCTAssertNil(
            inspection.contextCoordination.mutations.begin(
                extensionID: "another-extension",
                operation: .enable
            )
        )
        XCTAssertIdentical(
            inspection.contextState.profiles.contexts(for: profile.id)[extensionID],
            extensionContext
        )
        XCTAssertIdentical(
            inspection.contextState.profiles.controllersByProfile[profile.id],
            controller
        )
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertEqual(inspection.runtimeAuthorities.lifecycle.state, .ready)
        XCTAssertTrue(
            inspection.runtimeAuthorities.demand.hasRuntimeDemandWithoutEnabledExtensions
        )
        XCTAssertNotNil(
            inspection.runtimeAuthorities.catalog.manifest(for: extensionID)
        )
        XCTAssertNotNil(
            inspection.runtimeAuthorities.metrics.metrics(for: extensionID)
        )
        XCTAssertNotNil(
            inspection.actionSurfaces.publication
                .actionStatesByExtensionID[extensionID]
        )
        XCTAssertTrue(inspection.actionSurfaces.publication.extensionsLoaded)

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
            inspection.contextCoordination.mutations.admitsLoad(
                extensionID: extensionID,
                lease: nil
            )
        )
        let reopenedMutation = try XCTUnwrap(
            inspection.contextCoordination.mutations.begin(
                extensionID: extensionID,
                operation: .enable
            )
        )
        XCTAssertTrue(inspection.contextCoordination.mutations.finish(reopenedMutation))
        XCTAssertTrue(inspection.contextState.profiles.contexts(for: profile.id).isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.controllersByProfile.isEmpty)
        XCTAssertNil(
            browserConfiguration.webViewConfiguration.webExtensionController
        )
        XCTAssertEqual(
            inspection.runtimeAuthorities.lifecycle.state,
            manager.isExtensionSupportAvailable ? .idle : .unavailable
        )
        XCTAssertFalse(
            inspection.runtimeAuthorities.demand.hasRuntimeDemandWithoutEnabledExtensions
        )
        XCTAssertTrue(inspection.runtimeAuthorities.catalog.isEmpty)
        XCTAssertTrue(inspection.runtimeAuthorities.metrics.isEmpty)
        XCTAssertTrue(
            inspection.actionSurfaces.publication
                .actionStatesByExtensionID.isEmpty
        )
        XCTAssertFalse(inspection.actionSurfaces.publication.extensionsLoaded)
        XCTAssertEqual(
            inspection.runtimeAuthorities.loadRevisions.issue(),
            ExtensionLoadRevision(
                generation: generationBeforeShutdown.generation + 2
            )
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
        let inspection = fixture.inspection
        try XCTSkipUnless(manager.isExtensionSupportAvailable)

        let extensionID = "superseded-runtime-shutdown"
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        let extensionContext = WKWebExtensionContext(
            for: try await makeWebExtension()
        )
        inspection.contextState.profiles.setController(controller, for: profile.id)
        _ = inspection.contextState.profiles.setContext(
            extensionContext,
            extensionId: extensionID,
            profileId: profile.id
        )
        browserConfiguration.webViewConfiguration.webExtensionController =
            controller
        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        inspection.runtimeAuthorities.lifecycle.updateReadiness(isReady: true)
        inspection.runtimeAuthorities.demand.recordRuntimeDemandWithoutEnabledExtensions()
        inspection.runtimeAuthorities.catalog.recordManifest(
            ["manifest_version": 3],
            for: extensionID
        )
        inspection.runtimeAuthorities.metrics.recordManifestValidationDuration(
            0,
            for: extensionID
        )
        inspection.actionSurfaces.publication.setActionSurfaceState(
            BrowserExtensionActionSurfaceState(
                extensionID: extensionID,
                label: "Superseded",
                badgeText: "",
                hasUnreadBadgeText: false,
                isEnabled: true,
                presentsPopup: false,
                icon: nil
            ),
            extensionID: extensionID
        )

        let mutationRegistry = inspection.contextCoordination.mutations
        var replacementTerminalLease: ExtensionRuntimeTerminalLease?
        fixture.unloadBehavior.handler = { _, _ in
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
            inspection.contextState.profiles.contexts(for: profile.id)[extensionID]
        )
        XCTAssertIdentical(
            inspection.contextState.profiles.controllersByProfile[profile.id],
            controller
        )
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertEqual(inspection.runtimeAuthorities.lifecycle.state, .ready)
        XCTAssertTrue(
            inspection.runtimeAuthorities.demand.hasRuntimeDemandWithoutEnabledExtensions
        )
        XCTAssertNotNil(
            inspection.runtimeAuthorities.catalog.manifest(for: extensionID)
        )
        XCTAssertNotNil(
            inspection.runtimeAuthorities.metrics.metrics(for: extensionID)
        )
        XCTAssertNotNil(
            inspection.actionSurfaces.publication
                .actionStatesByExtensionID[extensionID]
        )
        XCTAssertTrue(inspection.actionSurfaces.publication.extensionsLoaded)

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
    ) throws -> (
        container: ModelContainer,
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection,
        attachedRuntime: ExtensionAttachedRuntimeCapture,
        unloadBehavior: ShutdownUnloadBehavior
    ) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let inspection = ExtensionManagerInspectionCapture()
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let unloadBehavior = ShutdownUnloadBehavior()
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            extensionPreferences: UserDefaults(suiteName: UUID().uuidString)!,
            attachedRuntimeDidInstall: attachedRuntime.install,
            testInspectionDidAssemble: inspection.install,
            testAssemblyOverrides: .init(
                unloadContext: { controller, context in
                    try unloadBehavior.unload(context, from: controller)
                },
                isLoadedContext: { _, _ in true }
            )
        )
        return (
            container,
            manager,
            inspection.inspection,
            attachedRuntime,
            unloadBehavior
        )
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
}

@available(macOS 15.5, *)
@MainActor
private final class ShutdownUnloadBehavior {
    var handler: (@MainActor (
        WKWebExtensionController,
        WKWebExtensionContext
    ) throws -> Void)?

    func unload(
        _ context: WKWebExtensionContext,
        from controller: WKWebExtensionController
    ) throws {
        if let handler {
            try handler(controller, context)
        } else {
            try controller.unload(context)
        }
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
