import XCTest

@testable import Sumi

final class SumiModuleRegistryTests: XCTestCase {
    @MainActor
    func testCleanInstallDefaultsAllOptionalModulesDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        for moduleID in SumiModuleID.allCases {
            let isEnabled = registry.isEnabled(moduleID)
            let storedValue = harness.defaults.object(forKey: store.key(for: moduleID))

            XCTAssertFalse(isEnabled, "\(moduleID.rawValue) should default to disabled")
            XCTAssertNil(storedValue)
        }
    }

    @MainActor
    func testCleanInstallDefaultsTrackingProtectionDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        let isEnabled = registry.isEnabled(.trackingProtection)
        let storedValue = harness.defaults.object(forKey: store.key(for: .trackingProtection))

        XCTAssertFalse(isEnabled)
        XCTAssertNil(storedValue)
    }

    @MainActor
    func testCleanInstallDefaultsExtensionsDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        let isEnabled = registry.isEnabled(.extensions)
        let storedValue = harness.defaults.object(forKey: store.key(for: .extensions))

        XCTAssertFalse(isEnabled)
        XCTAssertNil(storedValue)
    }

    @MainActor
    func testCleanInstallDefaultsUserscriptsDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        let isEnabled = registry.isEnabled(.userScripts)
        let storedValue = harness.defaults.object(forKey: store.key(for: .userScripts))

        XCTAssertFalse(isEnabled)
        XCTAssertNil(storedValue)
    }

    @MainActor
    func testCleanInstallDefaultsAdBlockingDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        let isEnabled = registry.isEnabled(.adBlocking)
        let storedValue = harness.defaults.object(forKey: store.key(for: .adBlocking))

        XCTAssertFalse(isEnabled)
        XCTAssertNil(storedValue)
    }

    @MainActor
    func testEnablingModulesPersistsAcrossRegistryRecreation() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        for moduleID in SumiModuleID.allCases {
            let firstRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )
            firstRegistry.enable(moduleID)

            let recreatedRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )

            let isEnabled = recreatedRegistry.isEnabled(moduleID)
            XCTAssertTrue(isEnabled)
        }
    }

    @MainActor
    func testDisablingModulesPersistsAcrossRegistryRecreation() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        for moduleID in SumiModuleID.allCases {
            registry.enable(moduleID)
            registry.disable(moduleID)

            let recreatedRegistry = SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
            )

            let isEnabled = recreatedRegistry.isEnabled(moduleID)
            let storedValue = harness.defaults.object(forKey: store.key(for: moduleID)) as? Bool

            XCTAssertFalse(isEnabled)
            XCTAssertEqual(storedValue, false as Bool?)
        }
    }

    @MainActor
    func testSetEnabledMirrorsEnableAndDisable() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.setEnabled(true, for: .trackingProtection)
        let enabledValue = registry.isEnabled(.trackingProtection)
        XCTAssertTrue(enabledValue)

        registry.setEnabled(false, for: .trackingProtection)
        let disabledValue = registry.isEnabled(.trackingProtection)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testTrackingProtectionEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.trackingProtection)
        let enabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.trackingProtection)
        XCTAssertTrue(enabledValue)

        registry.disable(.trackingProtection)
        let disabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.trackingProtection)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testExtensionsEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.extensions)
        let enabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.extensions)
        XCTAssertTrue(enabledValue)

        registry.disable(.extensions)
        let disabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.extensions)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testUserscriptsEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.userScripts)
        let enabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.userScripts)
        XCTAssertTrue(enabledValue)

        registry.disable(.userScripts)
        let disabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.userScripts)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testAdBlockingEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.adBlocking)
        let enabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking)
        XCTAssertTrue(enabledValue)

        registry.disable(.adBlocking)
        let disabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testSettingsKeysUseExpectedModuleIdentifiers() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)

        let trackingProtectionKey = store.key(for: .trackingProtection)
        let adBlockingKey = store.key(for: .adBlocking)
        let extensionsKey = store.key(for: .extensions)
        let userScriptsKey = store.key(for: .userScripts)

        XCTAssertEqual(trackingProtectionKey, "settings.modules.trackingProtection.enabled")
        XCTAssertEqual(adBlockingKey, "settings.modules.adBlocking.enabled")
        XCTAssertEqual(extensionsKey, "settings.modules.extensions.enabled")
        XCTAssertEqual(userScriptsKey, "settings.modules.userScripts.enabled")
    }

    func testRegistrySourceDoesNotReferenceOptionalRuntimeSymbols() throws {
        let source = try Self.source(named: "Sumi/Services/SumiModuleRegistry.swift")

        XCTAssertEqual(source.components(separatedBy: "\n").filter { $0.hasPrefix("import ") }, ["import Foundation"])

        for forbiddenPattern in [
            "SumiTrackingProtection",
            "SumiContentBlockingService",
            "ExtensionManager",
            "NativeMessagingHandler",
            "SumiScriptsManager",
            "UserScriptStore",
            "WKUserScript",
            "WebKit",
            "SwiftData",
            "TrackerRadarKit",
            "PrivacyConfig",
            "UserScript",
            "Timer",
            "Task",
            "NotificationCenter",
            "addObserver",
            "URLSession",
            "FileManager",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), "\(forbiddenPattern) is referenced by the registry")
        }
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
