import XCTest

@testable import Sumi

final class SettingsModuleToggleTests: XCTestCase {
    func testDescriptorsStillCoverOptionalModules() {
        XCTAssertEqual(
            moduleToggleDescriptors.map(\.moduleID),
            [.extensions, .userScripts]
        )
    }

    @MainActor
    func testToggleModelsPersistThroughModuleRegistryStore() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        for descriptor in moduleToggleDescriptors {
            let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
            let model = SumiSettingsModuleToggleModel(descriptor: descriptor, registry: registry)
            model.setEnabled(true)
            XCTAssertTrue(registry.isEnabled(descriptor.moduleID))
            model.setEnabled(false)
            XCTAssertFalse(registry.isEnabled(descriptor.moduleID))
        }
    }

    private var moduleToggleDescriptors: [SumiSettingsModuleToggleDescriptor] {
        [.extensions, .userScripts]
    }
}
