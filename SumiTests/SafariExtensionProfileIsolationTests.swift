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
        let container = try SumiDatabase.inMemory()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let fixture = makeManager(
            context: container,
            initialProfile: profileA
        )
        let inspection = fixture.inspection

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        let controllerA = inspection.controller.provisioning.ensureExtensionController(for: profileA.id)
        let controllerB = inspection.controller.provisioning.ensureExtensionController(for: profileB.id)

        XCTAssertNotIdentical(controllerA, controllerB)
        XCTAssertFalse(
            controllerA.configuration.defaultWebsiteDataStore
                === controllerB.configuration.defaultWebsiteDataStore
        )
    }

    func testSwitchProfileActivatesDistinctControllerAndStore() throws {
        let container = try SumiDatabase.inMemory()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let fixture = makeManager(
            context: container,
            initialProfile: profileA
        )
        let inspection = fixture.inspection

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        inspection.contextCoordination.profileTransition.switchProfile(profileID: profileA.id)
        let activeA = try XCTUnwrap(inspection.contextState.profiles.controllerForCurrentProfile())

        inspection.contextCoordination.profileTransition.switchProfile(profileID: profileB.id)
        let activeB = try XCTUnwrap(inspection.contextState.profiles.controllerForCurrentProfile())
        XCTAssertNotIdentical(activeA, activeB)
        XCTAssertFalse(
            activeA.configuration.defaultWebsiteDataStore
                === activeB.configuration.defaultWebsiteDataStore
        )
    }

    func testPrepareWebViewConfigurationUsesTabProfileStore() throws {
        let container = try SumiDatabase.inMemory()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let fixture = makeManager(
            context: container,
            initialProfile: profileA
        )
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

        XCTAssertTrue(
            configuration.websiteDataStore
                === configuration.webExtensionController?.configuration.defaultWebsiteDataStore
        )
    }

    func testExtensionControllerIdentifierDiffersFromProfileDataStoreIdentifier() throws {
        let container = try SumiDatabase.inMemory()
        let profile = Profile(name: "Profile")
        let fixture = makeManager(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager

        XCTAssertNotEqual(
            manager.controllerIdentifierOwner.identifier,
            profile.id
        )
    }

    private func makeManager(
        context: SumiDatabase,
        initialProfile: Profile
    ) -> (
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection
    ) {
        let inspection = ExtensionManagerInspectionCapture()
        let manager = ExtensionManager(
            database: context,
            initialProfile: initialProfile,
            testInspectionDidAssemble: inspection.install
        )
        return (manager, inspection.inspection)
    }
}
