import XCTest

@testable import Sumi

final class SumiModuleRegistryTests: XCTestCase {
    func testCleanInstallDefaultsAllOptionalModulesDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        for moduleID in SumiModuleID.allCases {
            XCTAssertFalse(registry.isEnabled(moduleID), "\(moduleID.rawValue) should default to disabled")
            XCTAssertNil(harness.defaults.object(forKey: store.key(for: moduleID)))
        }
    }

    func testCleanInstallDefaultsTrackingProtectionDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .trackingProtection)))
    }

    func testCleanInstallDefaultsExtensionsDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        XCTAssertFalse(registry.isEnabled(.extensions))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .extensions)))
    }

    func testCleanInstallDefaultsUserscriptsDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        XCTAssertFalse(registry.isEnabled(.userScripts))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .userScripts)))
    }

    func testCleanInstallDefaultsAdBlockingDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        XCTAssertFalse(registry.isEnabled(.adBlocking))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .adBlocking)))
    }

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

            XCTAssertTrue(recreatedRegistry.isEnabled(moduleID))
        }
    }

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

            XCTAssertFalse(recreatedRegistry.isEnabled(moduleID))
            XCTAssertEqual(harness.defaults.object(forKey: store.key(for: moduleID)) as? Bool, false as Bool?)
        }
    }

    func testSetEnabledMirrorsEnableAndDisable() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.setEnabled(true, for: .trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))

        registry.setEnabled(false, for: .trackingProtection)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
    }

    func testTrackingProtectionEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.trackingProtection)
        XCTAssertTrue(
            SumiModuleRegistry(settingsStore: store).isEnabled(.trackingProtection)
        )

        registry.disable(.trackingProtection)
        XCTAssertFalse(
            SumiModuleRegistry(settingsStore: store).isEnabled(.trackingProtection)
        )
    }

    func testExtensionsEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.extensions)
        XCTAssertTrue(
            SumiModuleRegistry(settingsStore: store).isEnabled(.extensions)
        )

        registry.disable(.extensions)
        XCTAssertFalse(
            SumiModuleRegistry(settingsStore: store).isEnabled(.extensions)
        )
    }

    func testUserscriptsEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.userScripts)
        XCTAssertTrue(
            SumiModuleRegistry(settingsStore: store).isEnabled(.userScripts)
        )

        registry.disable(.userScripts)
        XCTAssertFalse(
            SumiModuleRegistry(settingsStore: store).isEnabled(.userScripts)
        )
    }

    func testAdBlockingEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.adBlocking)
        XCTAssertTrue(
            SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking)
        )

        registry.disable(.adBlocking)
        XCTAssertFalse(
            SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking)
        )
    }

    func testSettingsKeysUseExpectedModuleIdentifiers() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)

        XCTAssertEqual(store.key(for: .trackingProtection), "settings.modules.trackingProtection.enabled")
        XCTAssertEqual(store.key(for: .adBlocking), "settings.modules.adBlocking.enabled")
        XCTAssertEqual(store.key(for: .extensions), "settings.modules.extensions.enabled")
        XCTAssertEqual(store.key(for: .userScripts), "settings.modules.userScripts.enabled")
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
