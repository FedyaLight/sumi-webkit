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
    func testCleanInstallDefaultsBoostsDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        let isEnabled = registry.isEnabled(.boosts)
        let storedValue = harness.defaults.object(forKey: store.key(for: .boosts))

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

        registry.setEnabled(true, for: .extensions)
        let enabledValue = registry.isEnabled(.extensions)
        XCTAssertTrue(enabledValue)

        registry.setEnabled(false, for: .extensions)
        let disabledValue = registry.isEnabled(.extensions)
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
    func testBoostsEnableDisablePersists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)

        registry.enable(.boosts)
        let enabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.boosts)
        XCTAssertTrue(enabledValue)

        registry.disable(.boosts)
        let disabledValue = SumiModuleRegistry(settingsStore: store).isEnabled(.boosts)
        XCTAssertFalse(disabledValue)
    }

    @MainActor
    func testSettingsKeysUseExpectedModuleIdentifiers() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)

        let extensionsKey = store.key(for: .extensions)
        let boostsKey = store.key(for: .boosts)

        XCTAssertEqual(extensionsKey, "settings.modules.extensions.enabled")
        XCTAssertEqual(boostsKey, "settings.modules.boosts.enabled")
    }
}
