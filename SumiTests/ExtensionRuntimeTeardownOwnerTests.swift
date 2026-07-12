import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeTeardownOwnerTests: XCTestCase {
    private enum TestError: Error {
        case failed
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
        manager.errorObservationOwner.seedLoggedErrorFingerprintForTesting(
            "fingerprint",
            extensionId: "alpha"
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

        manager.tearDownExtensionRuntime(
            reason: "ExtensionRuntimeTeardownOwnerTests.full",
            removeUIState: true,
            releaseController: true
        )

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
        XCTAssertFalse(manager.errorObservationOwner.hasLoggedErrorFingerprints)
        XCTAssertFalse(
            manager.controllerProvisioningOwner.hasExtensionPageUserContentControllers
        )
        XCTAssertTrue(manager.actionAnchorStore.isEmpty)
        XCTAssertEqual(manager.nativeMessagingPortRegistry.count, 0)
        XCTAssertTrue(manager.nativeMessagingPortRegistry.extensionIDs.isEmpty)
        XCTAssertFalse(manager.hasLoadedUserExtensionRuntime)
    }

    func testRuntimeTeardownCanPreserveControllerAndUIState() throws {
        let profile = Profile(name: "Partial Teardown Profile")
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
        manager.actionAnchorStore.setAnchor(for: "alpha", anchorView: anchorView)

        manager.tearDownExtensionRuntime(
            reason: "ExtensionRuntimeTeardownOwnerTests.partial",
            removeUIState: false,
            releaseController: false
        )

        XCTAssertIdentical(manager.profileRuntime.controllersByProfile[profile.id], controller)
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertTrue(manager.runtimeSession.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertEqual(manager.runtimeSession.runtimeState, .ready)
        XCTAssertTrue(manager.extensionsLoaded)
        XCTAssertTrue(manager.runtimeSession.loadedExtensionManifests.isEmpty)
        XCTAssertEqual(manager.actionAnchorStore.anchorCount(for: "alpha"), 1)
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
