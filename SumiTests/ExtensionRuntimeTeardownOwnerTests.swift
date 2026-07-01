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
        let controller = try XCTUnwrap(manager.extensionControllersByProfile[profile.id])
        browserConfiguration.webViewConfiguration.webExtensionController = controller

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        let nativePortKey = ObjectIdentifier(anchorView)
        manager.extensionsLoaded = true
        manager.runtimeState = .ready
        manager.allowsRuntimeWithoutEnabledExtensions = true
        manager.loadedExtensionManifests["alpha"] = ["manifest_version": 3]
        manager.actionStatesByExtensionID["alpha"] = BrowserExtensionActionSurfaceState(
            extensionID: "alpha",
            label: "Alpha",
            badgeText: "1",
            hasUnreadBadgeText: true,
            isEnabled: true,
            presentsPopup: true,
            icon: nil
        )
        manager.lastExtensionLoadErrors["\(profile.id):alpha"] = TestError.failed
        manager.extensionRuntimeResidencyState.touch(
            extensionId: "alpha",
            profileId: profile.id
        )
        manager.runtimeMetricsByExtensionID["alpha"] =
            ExtensionManager.ExtensionRuntimeMetrics()
        manager.lastLoggedExtensionErrorFingerprints["alpha"] = "fingerprint"
        manager.extensionPageUserContentControllersByProfile[profile.id] =
            WKUserContentController()
        manager.actionAnchorStore.setAnchor(for: "alpha", anchorView: anchorView)
        manager.nativeMessagingPortRegistry.nativeMessagePortExtensionIDs[nativePortKey] = "alpha"
        manager.nativeMessagingPortRegistry.nativeMessagePortProfileIDs[nativePortKey] = profile.id

        let generationBeforeTeardown = manager.extensionLoadGeneration

        manager.tearDownExtensionRuntime(
            reason: "ExtensionRuntimeTeardownOwnerTests.full",
            removeUIState: true,
            releaseController: true
        )

        XCTAssertEqual(manager.extensionLoadGeneration, generationBeforeTeardown + 1)
        XCTAssertTrue(manager.extensionControllersByProfile.isEmpty)
        XCTAssertNil(browserConfiguration.webViewConfiguration.webExtensionController)
        XCTAssertFalse(manager.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertEqual(
            manager.runtimeState,
            manager.isExtensionSupportAvailable ? .idle : .unavailable
        )
        XCTAssertFalse(manager.extensionsLoaded)
        XCTAssertTrue(manager.loadedExtensionManifests.isEmpty)
        XCTAssertTrue(manager.actionStatesByExtensionID.isEmpty)
        XCTAssertTrue(manager.lastExtensionLoadErrors.isEmpty)
        XCTAssertTrue(manager.extensionRuntimeResidencyState.liveContextKeys.isEmpty)
        XCTAssertTrue(manager.runtimeMetricsByExtensionID.isEmpty)
        XCTAssertTrue(manager.lastLoggedExtensionErrorFingerprints.isEmpty)
        XCTAssertTrue(manager.extensionPageUserContentControllersByProfile.isEmpty)
        XCTAssertTrue(manager.actionAnchorStore.isEmpty)
        XCTAssertTrue(manager.nativeMessagingPortRegistry.nativeMessagePortExtensionIDs.isEmpty)
        XCTAssertTrue(manager.nativeMessagingPortRegistry.nativeMessagePortProfileIDs.isEmpty)
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
        let controller = try XCTUnwrap(manager.extensionControllersByProfile[profile.id])
        browserConfiguration.webViewConfiguration.webExtensionController = controller

        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        manager.extensionsLoaded = true
        manager.runtimeState = .ready
        manager.allowsRuntimeWithoutEnabledExtensions = true
        manager.loadedExtensionManifests["alpha"] = ["manifest_version": 3]
        manager.actionAnchorStore.setAnchor(for: "alpha", anchorView: anchorView)

        manager.tearDownExtensionRuntime(
            reason: "ExtensionRuntimeTeardownOwnerTests.partial",
            removeUIState: false,
            releaseController: false
        )

        XCTAssertIdentical(manager.extensionControllersByProfile[profile.id], controller)
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controller
        )
        XCTAssertTrue(manager.allowsRuntimeWithoutEnabledExtensions)
        XCTAssertEqual(manager.runtimeState, .ready)
        XCTAssertTrue(manager.extensionsLoaded)
        XCTAssertTrue(manager.loadedExtensionManifests.isEmpty)
        XCTAssertEqual(manager.actionAnchorStore.anchorCount(for: "alpha"), 1)
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
            extensionPreferences: UserDefaults(suiteName: UUID().uuidString) ?? preconditionFailure("Unable to create test user defaults")
        )
        return (container, manager)
    }
}
