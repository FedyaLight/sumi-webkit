import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionProfileIsolationTests: XCTestCase {
    func testProfileRuntimeOwnerResolvesExplicitTabProfileBeforeCurrentFallback() {
        let currentProfileId = UUID()
        let tabProfileId = UUID()
        let owner = ExtensionProfileRuntimeOwner(initialProfileId: currentProfileId)
        let tab = Tab()
        tab.profileId = tabProfileId

        XCTAssertEqual(
            owner.resolvedProfileId(for: tab, browserManager: nil),
            tabProfileId
        )
        XCTAssertEqual(
            owner.resolvedProfileId(explicitProfileId: nil, browserManager: nil),
            currentProfileId
        )
    }

    func testProfileRuntimeOwnerProfileActivationReportsRuntimeDemand() {
        let owner = ExtensionProfileRuntimeOwner(initialProfileId: nil)
        let profileId = UUID()

        XCTAssertFalse(
            owner.activateProfile(
                profileId,
                hasExtensionDemand: false,
                runtimeIsReadyOrLoading: false
            )
        )
        XCTAssertEqual(owner.currentProfileId, profileId)

        XCTAssertTrue(
            owner.activateProfile(
                UUID(),
                hasExtensionDemand: true,
                runtimeIsReadyOrLoading: false
            )
        )
    }

    func testExtensionControllersAreDistinctPerProfile() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        let controllerA = manager.ensureExtensionController(for: profileA.id)
        let controllerB = manager.ensureExtensionController(for: profileB.id)

        XCTAssertNotIdentical(controllerA, controllerB)
        XCTAssertNotEqual(
            controllerA.configuration.identifier,
            controllerB.configuration.identifier
        )
        XCTAssertEqual(
            controllerA.configuration.defaultWebsiteDataStore?.identifier,
            profileA.dataStore.identifier
        )
        XCTAssertEqual(
            controllerB.configuration.defaultWebsiteDataStore?.identifier,
            profileB.dataStore.identifier
        )
        XCTAssertNotEqual(
            controllerA.configuration.defaultWebsiteDataStore?.identifier,
            controllerB.configuration.defaultWebsiteDataStore?.identifier
        )
    }

    func testSwitchProfileActivatesDistinctControllerAndStore() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        manager.switchProfile(profileId: profileA.id)
        let activeA = try XCTUnwrap(manager.extensionController)
        XCTAssertEqual(
            activeA.configuration.defaultWebsiteDataStore?.identifier,
            profileA.dataStore.identifier
        )

        manager.switchProfile(profileId: profileB.id)
        let activeB = try XCTUnwrap(manager.extensionController)
        XCTAssertNotIdentical(activeA, activeB)
        XCTAssertEqual(
            activeB.configuration.defaultWebsiteDataStore?.identifier,
            profileB.dataStore.identifier
        )
    }

    func testPrepareWebViewConfigurationUsesTabProfileStore() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )

        _ = manager.requestExtensionRuntime(
            reason: .webViewConfiguration,
            allowWithoutEnabledExtensions: true
        )

        let configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionProfileIsolationTests"
        )

        XCTAssertEqual(
            configuration.websiteDataStore.identifier,
            profileB.dataStore.identifier
        )
        XCTAssertEqual(
            configuration.webExtensionController?.configuration.defaultWebsiteDataStore?
                .identifier,
            profileB.dataStore.identifier
        )
    }

    func testExtensionControllerIdentifierDiffersFromProfileDataStoreIdentifier() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        XCTAssertNotEqual(
            manager.extensionControllerIdentifier(for: profile.id),
            profile.id
        )
    }

    func testPrivateTabActionPopupGuardRemainsWired() throws {
        let uiSource = try String(
            contentsOfFile: projectPath("Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            uiSource.contains("guard currentTab.isEphemeral == false else"),
            "Private tabs must remain blocked for extension action popups"
        )
        XCTAssertTrue(
            uiSource.contains("Private tabs are not eligible for extension action popups."),
            "Private tab popup block message must remain present"
        )
    }

    private func projectPath(_ relativePath: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
