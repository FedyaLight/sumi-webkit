import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionRuntimeDataStoreTests: XCTestCase {
    func testTestHostUsesEphemeralPlatformStoresByDefault() {
        XCTAssertFalse(Profile(name: "Test Host Profile").dataStore.isPersistent)
    }

    func testRememberedProfileProvidesCanonicalStoreObject() throws {
        let profile = Profile(name: "Canonical Extension Store")
        let cache = ExtensionProfileWebsiteDataStoreCache()

        cache.remember(profile)
        let resolved = cache.store(
            for: profile.id,
            activeProfile: nil,
            currentProfileId: profile.id
        )

        XCTAssertIdentical(resolved, profile.dataStore)
    }

    func testActiveDifferentProfileCannotAliasRequestedStore() throws {
        let requested = Profile(name: "Requested Extension Store")
        let active = Profile(name: "Active Extension Store")
        let cache = ExtensionProfileWebsiteDataStoreCache()

        cache.remember(requested)
        let resolved = cache.store(
            for: requested.id,
            activeProfile: active,
            currentProfileId: active.id
        )

        XCTAssertIdentical(resolved, requested.dataStore)
        XCTAssertFalse(resolved === active.dataStore)
    }

    func testExtensionRuntimeWebsiteDataStoreMatchesProfileStore() throws {
        let container = try SumiDatabase.inMemory()
        let profile = Profile(name: "Extension Store Profile")
        let fixture = makeManager(
            context: container,
            initialProfile: profile
        )
        let inspection = fixture.inspection
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )

        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllerForCurrentProfile()
        )
        let profileStore = profile.dataStore
        XCTAssertEqual(
            controller.configuration.isPersistent,
            profileStore.isPersistent
        )
        XCTAssertEqual(
            controller.configuration.identifier,
            profileStore.identifier
        )
        let controllerDefaultStore = try XCTUnwrap(
            controller.configuration.defaultWebsiteDataStore
        )
        let pageConfiguration = try XCTUnwrap(
            controller.configuration.webViewConfiguration
        )
        let pageConfigurationStore = pageConfiguration.websiteDataStore

        XCTAssertEqual(controllerDefaultStore.identifier, profileStore.identifier)
        XCTAssertEqual(pageConfigurationStore.identifier, profileStore.identifier)
        XCTAssertEqual(
            pageConfiguration.applicationNameForUserAgent,
            SumiUserAgent.safariCompatibleApplicationNameForUserAgent
        )
        XCTAssertFalse(pageConfiguration.sumiIsNormalTabWebViewConfiguration)
    }

    func testPrepareWebViewConfigurationAlignsWebsiteDataStoreWithProfile() throws {
        let container = try SumiDatabase.inMemory()
        let profile = Profile(name: "Prepared Configuration Profile")
        let fixture = makeManager(
            context: container,
            initialProfile: profile
        )
        let inspection = fixture.inspection
        XCTAssertNil(
            inspection.contextState.profiles.controllerForCurrentProfile()
        )

        let configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionRuntimeDataStoreTests"
        )

        XCTAssertNotNil(
            inspection.contextState.profiles.controllerForCurrentProfile()
        )
        XCTAssertNotNil(configuration.webExtensionController)
        XCTAssertIdentical(configuration.websiteDataStore, profile.dataStore)
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
    }

    func testReadyConfigurationDemandDoesNotReenterWebViewReconciliation() throws {
        let container = try SumiDatabase.inMemory()
        let profile = Profile(name: "Ready Configuration Demand")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let fixture = makeManager(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        manager.attach(browserManager: browserManager)
        inspection.runtimeAuthorities.lifecycle.updateReadiness(isReady: true)
        let reconciler = fixture.attachedRuntime.runtime.controller.reconciler
        let initialCount = reconciler.reconciliationRequestCount

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .webViewConfiguration,
            profileId: profile.id
        )

        XCTAssertEqual(reconciler.reconciliationRequestCount, initialCount)
    }

    func testRepeatedAttachmentToSameBrowserKeepsControllerRuntimeIdentity() throws {
        let container = try SumiDatabase.inMemory()
        let profile = Profile(name: "Repeated Attachment")
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        let fixture = makeManager(
            context: container,
            initialProfile: profile
        )
        let manager = fixture.manager
        manager.attach(browserManager: browserManager)
        let composition = fixture.attachedRuntime.runtime.controller

        manager.attach(browserManager: browserManager)

        let repeated = fixture.attachedRuntime.runtime.controller
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
        let container = try SumiDatabase.inMemory()
        let persistentProfile = Profile(name: "Regular Profile")
        let ephemeralProfile = Profile.createEphemeral()
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = ephemeralProfile
        browserManager.profileManager.profiles = [persistentProfile]
        windowRegistry.register(privateWindow)
        windowRegistry.setActive(privateWindow)

        let fixture = makeManager(
            context: container,
            initialProfile: persistentProfile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        manager.attach(browserManager: browserManager)

        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .webViewConfiguration
        )

        let configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: ephemeralProfile,
            url: URL(string: "https://private.example")
        )
        XCTAssertFalse(configuration.websiteDataStore.isPersistent)
        XCTAssertIdentical(configuration.websiteDataStore, ephemeralProfile.dataStore)

        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
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
        let controller = try XCTUnwrap(configuration.webExtensionController)
        XCTAssertFalse(controller.configuration.isPersistent)
        XCTAssertNil(controller.configuration.identifier)
    }

    func testPrivateRuntimeProfileMarkerSurvivesWindowRegistryLoss() throws {
        let container = try SumiDatabase.inMemory()
        let persistentProfile = Profile(name: "Regular Profile")
        let ephemeralProfile = Profile.createEphemeral()
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = ephemeralProfile
        browserManager.profileManager.profiles = [persistentProfile]
        windowRegistry.register(privateWindow)

        let fixture = makeManager(
            context: container,
            initialProfile: persistentProfile
        )
        let manager = fixture.manager
        let inspection = fixture.inspection
        manager.attach(browserManager: browserManager)

        _ = inspection.controller.provisioning.ensureExtensionController(for: ephemeralProfile.id)
        XCTAssertTrue(inspection.contextState.profiles.isPrivateRuntimeProfile(ephemeralProfile.id))

        windowRegistry.unregister(privateWindow.id)

        XCTAssertTrue(inspection.contextState.profiles.isPrivateRuntimeProfile(ephemeralProfile.id))
    }

    func testProfileStoreCachePreservesCurrentProfileOnEviction() throws {
        let cache = ExtensionProfileWebsiteDataStoreCache(limit: 2)
        let currentProfileId = UUID()
        let inactiveProfileId = UUID()
        let newestProfileId = UUID()

        let currentStore = try XCTUnwrap(cache.store(
            for: currentProfileId,
            activeProfile: nil,
            currentProfileId: currentProfileId
        ))
        let inactiveStore = try XCTUnwrap(cache.store(
            for: inactiveProfileId,
            activeProfile: nil,
            currentProfileId: currentProfileId
        ))

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

    func testProfileStoreCacheTouchRefreshesEvictionOrder() throws {
        let cache = ExtensionProfileWebsiteDataStoreCache(limit: 2)
        let firstProfileId = UUID()
        let secondProfileId = UUID()
        let newestProfileId = UUID()

        let firstStore = try XCTUnwrap(cache.store(
            for: firstProfileId,
            activeProfile: nil,
            currentProfileId: nil
        ))
        let secondStore = try XCTUnwrap(cache.store(
            for: secondProfileId,
            activeProfile: nil,
            currentProfileId: nil
        ))

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

    func testPrivatePartitionSurvivesEvictionPressure() throws {
        let cache = ExtensionProfileWebsiteDataStoreCache(limit: 2)
        let privateProfile = Profile.createEphemeral()

        cache.remember(privateProfile)
        for _ in 0..<3 {
            _ = cache.store(
                for: UUID(),
                activeProfile: nil,
                currentProfileId: nil
            )
        }

        XCTAssertIdentical(
            cache.cachedStore(for: privateProfile.id),
            privateProfile.dataStore
        )
        let resolved = try XCTUnwrap(cache.store(
            for: privateProfile.id,
            activeProfile: nil,
            currentProfileId: nil
        ))
        XCTAssertFalse(resolved.isPersistent)
    }

    func testPrivatePartitionWithoutStoreFailsClosed() {
        let cache = ExtensionProfileWebsiteDataStoreCache()
        let privateProfile = Profile.createEphemeral()

        cache.rememberPrivateRuntimeProfileIfNeeded(privateProfile)

        XCTAssertNil(cache.cachedStore(for: privateProfile.id))
        XCTAssertNil(cache.store(
            for: privateProfile.id,
            activeProfile: nil,
            currentProfileId: nil
        ))
    }

    func testRememberReplacesMintedStoreWithPrivatePartitionStore() throws {
        let cache = ExtensionProfileWebsiteDataStoreCache()
        let privateProfile = Profile.createEphemeral()

        let minted = try XCTUnwrap(cache.store(
            for: privateProfile.id,
            activeProfile: nil,
            currentProfileId: nil
        ))
        XCTAssertFalse(minted.isPersistent)

        cache.remember(privateProfile)

        XCTAssertIdentical(
            cache.cachedStore(for: privateProfile.id),
            privateProfile.dataStore
        )
        let resolved = try XCTUnwrap(cache.store(
            for: privateProfile.id,
            activeProfile: nil,
            currentProfileId: nil
        ))
        XCTAssertFalse(resolved.isPersistent)
    }

    func testUnrememberedPrivateWindowResolvesNonPersistentStore() throws {
        let container = try SumiDatabase.inMemory()
        let persistentProfile = Profile(name: "Regular Profile")
        let ephemeralProfile = Profile.createEphemeral()
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        browserManager.profileManager.profiles = [persistentProfile]

        let fixture = makeManager(
            context: container,
            initialProfile: persistentProfile
        )
        let inspection = fixture.inspection
        fixture.manager.attach(browserManager: browserManager)

        // Registered only after attachment, so the private partition was never
        // remembered by the profile runtime.
        let privateWindow = BrowserWindowState()
        privateWindow.isIncognito = true
        privateWindow.ephemeralProfile = ephemeralProfile
        windowRegistry.register(privateWindow)

        let store = try XCTUnwrap(
            inspection.controller.provisioning.websiteDataStoreIfAdmitted(
                for: ephemeralProfile.id
            )
        )

        XCTAssertIdentical(store, ephemeralProfile.dataStore)
        XCTAssertFalse(store.isPersistent)
        XCTAssertTrue(
            inspection.contextState.profiles
                .isPrivateRuntimeProfile(ephemeralProfile.id)
        )
    }

    func testUnresolvableProfileFailsClosedWhileAttached() throws {
        let container = try SumiDatabase.inMemory()
        let persistentProfile = Profile(name: "Regular Profile")
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        browserManager.profileManager.profiles = [persistentProfile]

        let fixture = makeManager(
            context: container,
            initialProfile: persistentProfile
        )
        let inspection = fixture.inspection
        fixture.manager.attach(browserManager: browserManager)

        XCTAssertNil(
            inspection.controller.provisioning.websiteDataStoreIfAdmitted(
                for: UUID()
            )
        )
        XCTAssertNil(
            inspection.controller.provisioning.controllerIfAdmitted(
                for: UUID()
            )
        )
    }

    private func makeManager(
        context: SumiDatabase,
        initialProfile: Profile
    ) -> (
        manager: ExtensionManager,
        inspection: ExtensionManagerTestInspection,
        attachedRuntime: ExtensionAttachedRuntimeCapture
    ) {
        let inspection = ExtensionManagerInspectionCapture()
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let manager = ExtensionManager(
            database: context,
            initialProfile: initialProfile,
            attachedRuntimeDidInstall: attachedRuntime.install,
            testInspectionDidAssemble: inspection.install
        )
        return (manager, inspection.inspection, attachedRuntime)
    }
}
