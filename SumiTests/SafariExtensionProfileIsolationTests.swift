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
        let owner = ExtensionProfileRuntime(initialProfileId: currentProfileId)
        let profiles = ExtensionTabProfileResolution(
            profileRuntime: owner,
            windowProfiles: nil
        )
        let tab = Tab()
        tab.profileId = tabProfileId

        XCTAssertEqual(profiles.profileID(for: tab), tabProfileId)
        XCTAssertEqual(profiles.profileID(for: Tab()), currentProfileId)
    }

    func testProfileRuntimeOwnerRemembersItsCurrentProfileWithoutBrowserGraph() {
        let profile = Profile(name: "Remembered Profile")
        let owner = ExtensionProfileRuntime(
            initialProfileId: profile.id,
            initialProfile: profile
        )

        XCTAssertIdentical(owner.rememberedProfile(for: profile.id), profile)
        XCTAssertIdentical(owner.currentRememberedProfile, profile)
    }

    func testProfileRuntimeOwnerProfileActivationReportsRuntimeDemand() {
        let owner = ExtensionProfileRuntime(initialProfileId: nil)
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
        let fixture = makeManager(
            context: container.mainContext,
            initialProfile: profileA
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        let controllerA = inspection.controller.provisioning.ensureExtensionController(for: profileA.id)
        let controllerB = inspection.controller.provisioning.ensureExtensionController(for: profileB.id)

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
        let fixture = makeManager(
            context: container.mainContext,
            initialProfile: profileA
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        inspection.contextCoordination.profileTransition.switchProfile(profileID: profileA.id)
        let activeA = try XCTUnwrap(inspection.contextState.profiles.controllerForCurrentProfile())
        XCTAssertEqual(
            activeA.configuration.defaultWebsiteDataStore?.identifier,
            profileA.dataStore.identifier
        )

        inspection.contextCoordination.profileTransition.switchProfile(profileID: profileB.id)
        let activeB = try XCTUnwrap(inspection.contextState.profiles.controllerForCurrentProfile())
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
        let fixture = makeManager(
            context: container.mainContext,
            initialProfile: profileA
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .webViewConfiguration
        )

        let configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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
        let fixture = makeManager(
            context: container.mainContext,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection

        XCTAssertNotEqual(
            manager.controllerIdentifierOwner.identifier,
            profile.id
        )
    }

    private func makeManager(
        context: ModelContext,
        initialProfile: Profile
    ) -> (
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection
    ) {
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            context: context,
            initialProfile: initialProfile,
            testInspectionDidAssemble: inspection.install
        )
        return (manager, inspection.inspection)
    }
}
