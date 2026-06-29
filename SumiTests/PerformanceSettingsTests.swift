import XCTest

@testable import Sumi

@MainActor
final class PerformanceSettingsTests: XCTestCase {
    func testDefaultMemoryModeIsBalanced() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memoryMode, .balanced)
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 2 * 60 * 60)
    }

    func testEachMemoryModePersistsAcrossSettingsRecreation() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        for mode in SumiMemoryMode.allCases {
            let settings = SumiSettingsService(userDefaults: harness.defaults)
            settings.memoryMode = mode

            let recreatedSettings = SumiSettingsService(userDefaults: harness.defaults)

            XCTAssertEqual(recreatedSettings.memoryMode, mode)
            XCTAssertEqual(harness.defaults.string(forKey: "settings.memoryMode"), mode.rawValue)
        }
    }

    func testOldMemoryModeValuesMigrateToPrompt22Modes() {
        let cases: [(stored: String, expected: SumiMemoryMode)] = [
            ("lightweight", .maximum),
            ("performance", .moderate),
            ("balanced", .balanced),
            ("unknown", .balanced),
        ]

        for testCase in cases {
            let harness = TestDefaultsHarness()
            defer { harness.reset() }
            harness.defaults.set(testCase.stored, forKey: "settings.memoryMode")

            let settings = SumiSettingsService(userDefaults: harness.defaults)

            XCTAssertEqual(settings.memoryMode, testCase.expected, "stored=\(testCase.stored)")
            XCTAssertEqual(harness.defaults.string(forKey: "settings.memoryMode"), testCase.expected.rawValue)
        }
    }

    func testCustomDeactivationDelayPersistsAndClamps() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)
        settings.memorySaverCustomDeactivationDelay = 30 * 60
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 30 * 60)

        settings.memorySaverCustomDeactivationDelay = 5 * 60
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 5 * 60)

        settings.memorySaverCustomDeactivationDelay = 30
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 60)

        settings.memorySaverCustomDeactivationDelay = 48 * 60 * 60
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 2 * 60 * 60)

        let recreatedSettings = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(recreatedSettings.memorySaverCustomDeactivationDelay, 2 * 60 * 60)
    }

    func testInvalidPersistedCustomDeactivationDelayFallsBackToDefault() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        harness.defaults.set(-1.0, forKey: "settings.memorySaver.customDeactivationDelay")

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 2 * 60 * 60)
        XCTAssertEqual(harness.defaults.double(forKey: "settings.memorySaver.customDeactivationDelay"), 2 * 60 * 60)
    }

    func testPerformanceSettingsExposeAllMemoryModes() {
        XCTAssertEqual(
            SumiMemoryModeSettingsDescriptor.all.map(\.mode),
            [.moderate, .balanced, .maximum, .custom]
        )
        XCTAssertEqual(
            Set(SumiMemoryModeSettingsDescriptor.all.map(\.mode)),
            Set(SumiMemoryMode.allCases)
        )
        XCTAssertEqual(
            SumiMemoryModeSettingsDescriptor.all.map(\.title),
            ["Moderate", "Balanced", "Maximum", "Custom Deactivation Delay"]
        )
        let expectedPresetOptions: [TimeInterval] = [
            2 * 60 * 60,
            60 * 60,
            30 * 60,
            15 * 60,
            5 * 60,
            60,
        ]
        XCTAssertEqual(SumiMemorySaverCustomDelay.presetOptions, expectedPresetOptions)

    }

    func testPerformanceSettingsCopyMatchesMemoryModeContract() {
        let copy = Self.performanceCopy

        XCTAssertTrue(copy.contains("Deactivates inactive tabs after a longer period"))
        XCTAssertTrue(copy.contains("Recommended. Balances memory savings and convenience"))
        XCTAssertTrue(copy.contains("Deactivates inactive tabs sooner"))
        XCTAssertTrue(copy.contains("Choose when inactive tabs are deactivated"))
        XCTAssertFalse(copy.contains("Frees memory faster"))
    }

    func testSettingsNavigationReferencesPerformanceTab() {
        XCTAssertTrue(SettingsTabs.ordered.contains(.performance))
        XCTAssertEqual(SettingsTabs(paneQueryValue: "performance"), .performance)
        XCTAssertEqual(SettingsPaneDescriptor.descriptor(for: .performance).title, "Performance")
        XCTAssertEqual(SettingsTabs.performance.settingsSurfaceURL.absoluteString, "sumi://settings?pane=performance")
    }

    private static var performanceCopy: String {
        (
            SumiMemoryModeSettingsDescriptor.all.flatMap {
                [$0.title, $0.detail]
            }
        )
        .joined(separator: " ")
    }

}
