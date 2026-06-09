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

        XCTAssertEqual(
            configuration.websiteDataStore.identifier,
            profile.dataStore.identifier
        )
    }
}
