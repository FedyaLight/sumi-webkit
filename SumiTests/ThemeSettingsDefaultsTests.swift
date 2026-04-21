import XCTest
@testable import Sumi

@MainActor
final class ThemeSettingsDefaultsTests: XCTestCase {
    func testWindowSchemeDefaultsToAuto() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.windowSchemeMode, .auto)
    }

    func testStoredWindowSchemeIsUsedAsIs() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        harness.defaults.set(WindowSchemeMode.dark.rawValue, forKey: "settings.windowSchemeMode")

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.windowSchemeMode, .dark)
    }
}
