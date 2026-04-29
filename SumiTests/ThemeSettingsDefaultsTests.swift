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

    func testSidebarPositionPersistsRightSide() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.sidebarPosition = .right

        let recreatedSettings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.sidebarPosition, .right)
        XCTAssertEqual(recreatedSettings.sidebarPosition, .right)
        XCTAssertEqual(harness.defaults.string(forKey: "settings.sidebarPosition"), "right")
    }

    func testInvalidSidebarPositionFallsBackToLeft() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        harness.defaults.set("center", forKey: "settings.sidebarPosition")

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.sidebarPosition, .left)
    }
}
