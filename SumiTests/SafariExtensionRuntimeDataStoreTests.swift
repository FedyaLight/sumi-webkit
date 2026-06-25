import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionRuntimeDataStoreTests: XCTestCase {
    func testExtensionRuntimeWebsiteDataStoreMatchesProfileStore() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Extension Store Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )

        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )

        let controller = try XCTUnwrap(manager.extensionController)
        let profileStore = profile.dataStore
        let controllerDefaultStore = try XCTUnwrap(
            controller.configuration.defaultWebsiteDataStore
        )
        let pageConfigurationStore = try XCTUnwrap(
            controller.configuration.webViewConfiguration?.websiteDataStore
        )

        XCTAssertEqual(controllerDefaultStore.identifier, profileStore.identifier)
        XCTAssertEqual(pageConfigurationStore.identifier, profileStore.identifier)
    }

    func testPrepareWebViewConfigurationAlignsWebsiteDataStoreWithProfile() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Prepared Configuration Profile")
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
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
            profileId: profile.id,
            reason: "SafariExtensionRuntimeDataStoreTests"
        )

        XCTAssertTrue(configuration.websiteDataStore === profile.dataStore)
        XCTAssertTrue(configuration.websiteDataStore.isPersistent)
    }

    func testPrepareWebViewConfigurationPreservesEphemeralProfileDataStore() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let persistentProfile = Profile(name: "Regular Profile")
        let ephemeralProfile = Profile.createEphemeral()
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = ephemeralProfile
        browserManager.windowRegistry = windowRegistry
        browserManager.profileManager.profiles = [persistentProfile]
        windowRegistry.register(privateWindow)
        windowRegistry.setActive(privateWindow)

        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: persistentProfile
        )
        manager.attach(browserManager: browserManager)

        _ = manager.requestExtensionRuntime(
            reason: .webViewConfiguration,
            allowWithoutEnabledExtensions: true
        )

        let configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: ephemeralProfile,
            url: URL(string: "https://private.example")
        )
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(configuration.websiteDataStore === ephemeralProfile.dataStore)

        manager.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: ephemeralProfile.id,
            reason: "SafariExtensionRuntimeDataStoreTests.ephemeral"
        )

        XCTAssertTrue(configuration.websiteDataStore === ephemeralProfile.dataStore)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(
            configuration.webExtensionController?.configuration.defaultWebsiteDataStore
                === ephemeralProfile.dataStore
        )
    }

    func testPrivateRuntimeProfileMarkerSurvivesWindowRegistryLoss() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let persistentProfile = Profile(name: "Regular Profile")
        let ephemeralProfile = Profile.createEphemeral()
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = ephemeralProfile
        browserManager.windowRegistry = windowRegistry
        browserManager.profileManager.profiles = [persistentProfile]
        windowRegistry.register(privateWindow)

        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: persistentProfile
        )
        manager.attach(browserManager: browserManager)

        _ = manager.ensureExtensionController(for: ephemeralProfile.id)
        XCTAssertTrue(manager.isPrivateExtensionRuntimeProfile(ephemeralProfile.id))

        windowRegistry.unregister(privateWindow.id)

        XCTAssertTrue(manager.isPrivateExtensionRuntimeProfile(ephemeralProfile.id))
    }
}
