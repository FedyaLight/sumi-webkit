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
        _ = manager.runtimeDemandCoordinator.request(
            reason: .install,
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
        XCTAssertNil(manager.controllerRuntimeComposition)
        XCTAssertNil(manager.extensionController)

        let configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionRuntimeDataStoreTests"
        )

        XCTAssertNil(manager.controllerRuntimeComposition)
        XCTAssertNotNil(manager.extensionController)
        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
        XCTAssertTrue(configuration.websiteDataStore.isPersistent)
    }

    func testReadyConfigurationDemandDoesNotReenterWebViewReconciliation() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Ready Configuration Demand")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        manager.attach(browserManager: browserManager)
        manager.runtimeLifecycle.updateReadiness(isReady: true)
        let reconciler = manager.profileWebViewRuntimeReconciler
        let initialCount = reconciler.reconciliationRequestCount

        _ = manager.runtimeDemandCoordinator.request(
            reason: .webViewConfiguration,
            allowWithoutEnabledExtensions: true,
            profileId: profile.id
        )

        XCTAssertEqual(reconciler.reconciliationRequestCount, initialCount)
    }

    func testRepeatedAttachmentToSameBrowserKeepsControllerRuntimeIdentity() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let profile = Profile(name: "Repeated Attachment")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let manager = ExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        manager.attach(browserManager: browserManager)
        let composition = try XCTUnwrap(manager.controllerRuntimeComposition)

        manager.attach(browserManager: browserManager)

        let repeated = try XCTUnwrap(manager.controllerRuntimeComposition)
        XCTAssertIdentical(repeated.profiles, composition.profiles)
        XCTAssertIdentical(repeated.controllers, composition.controllers)
        XCTAssertIdentical(repeated.webViews, composition.webViews)
        XCTAssertIdentical(repeated.admission, composition.admission)
        XCTAssertIdentical(repeated.mismatch, composition.mismatch)
        XCTAssertIdentical(repeated.repair, composition.repair)
        XCTAssertIdentical(repeated.reconciler, composition.reconciler)
        XCTAssertIdentical(
            repeated.contextCompatibility,
            composition.contextCompatibility
        )
        XCTAssertIdentical(
            repeated.tabWebViewResolver,
            composition.tabWebViewResolver
        )
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

        _ = manager.runtimeDemandCoordinator.request(
            reason: .webViewConfiguration,
            allowWithoutEnabledExtensions: true
        )

        let configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: ephemeralProfile,
            url: URL(string: "https://private.example")
        )
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertIdentical(configuration.websiteDataStore, ephemeralProfile.dataStore)

        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: ephemeralProfile.id,
            reason: "SafariExtensionRuntimeDataStoreTests.ephemeral"
        )

        XCTAssertIdentical(configuration.websiteDataStore, ephemeralProfile.dataStore)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertIdentical(
            configuration.webExtensionController?.configuration.defaultWebsiteDataStore,
            ephemeralProfile.dataStore
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

    func testProfileStoreCachePreservesCurrentProfileOnEviction() {
        let cache = ExtensionProfileWebsiteDataStoreCache(limit: 2)
        let currentProfileId = UUID()
        let inactiveProfileId = UUID()
        let newestProfileId = UUID()

        let currentStore = cache.store(
            for: currentProfileId,
            activeProfile: nil,
            currentProfileId: currentProfileId
        )
        let inactiveStore = cache.store(
            for: inactiveProfileId,
            activeProfile: nil,
            currentProfileId: currentProfileId
        )

        XCTAssertIdentical(cache.cachedStore(for: currentProfileId), currentStore)
        XCTAssertIdentical(cache.cachedStore(for: inactiveProfileId), inactiveStore)

        _ = cache.store(
            for: newestProfileId,
            activeProfile: nil,
            currentProfileId: currentProfileId
        )

        XCTAssertIdentical(cache.cachedStore(for: currentProfileId), currentStore)
        XCTAssertNil(cache.cachedStore(for: inactiveProfileId))
        XCTAssertNotNil(cache.cachedStore(for: newestProfileId))
    }

    func testProfileStoreCacheTouchRefreshesEvictionOrder() {
        let cache = ExtensionProfileWebsiteDataStoreCache(limit: 2)
        let firstProfileId = UUID()
        let secondProfileId = UUID()
        let newestProfileId = UUID()

        let firstStore = cache.store(
            for: firstProfileId,
            activeProfile: nil,
            currentProfileId: nil
        )
        let secondStore = cache.store(
            for: secondProfileId,
            activeProfile: nil,
            currentProfileId: nil
        )

        XCTAssertIdentical(cache.cachedStore(for: firstProfileId), firstStore)
        XCTAssertIdentical(cache.cachedStore(for: secondProfileId), secondStore)

        _ = cache.store(
            for: firstProfileId,
            activeProfile: nil,
            currentProfileId: nil
        )
        _ = cache.store(
            for: newestProfileId,
            activeProfile: nil,
            currentProfileId: nil
        )

        XCTAssertIdentical(cache.cachedStore(for: firstProfileId), firstStore)
        XCTAssertNil(cache.cachedStore(for: secondProfileId))
        XCTAssertNotNil(cache.cachedStore(for: newestProfileId))
    }
}
