import XCTest

@testable import Sumi

@MainActor
final class PerformanceSettingsTests: XCTestCase {
    func testDefaultMemoryModeIsBalanced() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memoryMode, .balanced)
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 4 * 60 * 60)
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
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 15 * 60)

        settings.memorySaverCustomDeactivationDelay = 48 * 60 * 60
        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 24 * 60 * 60)

        let recreatedSettings = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertEqual(recreatedSettings.memorySaverCustomDeactivationDelay, 24 * 60 * 60)
    }

    func testInvalidPersistedCustomDeactivationDelayFallsBackToDefault() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        harness.defaults.set(-1.0, forKey: "settings.memorySaver.customDeactivationDelay")

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memorySaverCustomDeactivationDelay, 4 * 60 * 60)
        XCTAssertEqual(harness.defaults.double(forKey: "settings.memorySaver.customDeactivationDelay"), 4 * 60 * 60)
    }

    func testPerformanceSettingsExposeAllMemoryModes() throws {
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

        let source = try Self.source(named: "Sumi/Components/Settings/Tabs/Performance.swift")
        XCTAssertTrue(source.contains("Picker(\"Memory Saver\""))
        XCTAssertTrue(source.contains("ForEach(SumiMemoryModeSettingsDescriptor.all)"))
        XCTAssertTrue(source.contains("settings.memoryMode == .custom"))
        XCTAssertTrue(source.contains("Deactivate inactive tabs after:"))
    }

    func testPerformanceSettingsCopyMatchesMemoryModeContract() {
        let copy = Self.performanceCopy

        XCTAssertTrue(copy.contains("Deactivates inactive tabs after a longer period"))
        XCTAssertTrue(copy.contains("Recommended. Balances memory savings and convenience"))
        XCTAssertTrue(copy.contains("Deactivates inactive tabs sooner"))
        XCTAssertTrue(copy.contains("Choose when inactive tabs are deactivated"))
        XCTAssertTrue(copy.contains("Deactivated tabs remain visible"))
        XCTAssertTrue(copy.contains("Pinned tabs and Essentials remain launchers"))
        XCTAssertTrue(copy.contains("can deactivate their hidden live runtime"))
    }

    func testSettingsNavigationReferencesPerformanceTab() throws {
        let settingsUtilsSource = try Self.source(named: "Sumi/Components/Settings/SettingsUtils.swift")
        let tabRootSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsTabRootView.swift")

        XCTAssertTrue(SettingsTabs.ordered.contains(.performance))
        XCTAssertEqual(SettingsTabs(paneQueryValue: "performance"), .performance)
        XCTAssertEqual(SettingsTabs.performance.name, "Performance")
        XCTAssertEqual(SettingsTabs.performance.settingsSurfaceURL.absoluteString, "sumi://settings?pane=performance")
        XCTAssertTrue(settingsUtilsSource.contains("case performance"))
        XCTAssertTrue(tabRootSource.contains("SettingsPerformanceTab()"))
    }

    func testOnlyTabSuspensionServiceReadsMemoryModeForRuntimePolicy() throws {
        let suspensionSource = try Self.source(named: "Sumi/Managers/TabSuspensionService.swift")

        XCTAssertTrue(suspensionSource.contains("SumiMemoryMode"))
        XCTAssertTrue(suspensionSource.contains("memoryMode"))
        XCTAssertTrue(suspensionSource.contains("TabSuspensionPolicy"))

        for sourcePath in [
            "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
        ] {
            let source = try Self.source(named: sourcePath)
            XCTAssertFalse(source.contains("SumiMemoryMode"), "\(sourcePath) should not consume memory modes")
        }
    }

    func testSettingsSourcesDoNotAddSuspensionOrEvictionCalls() throws {
        let source = try Self.combinedSource(in: "Sumi/Components/Settings")
        let forbiddenPatterns = [
            ".suspend(",
            "suspendWebViews(",
            "handleMemoryPressure(",
            "evictHiddenWebViews",
            "canEvictHiddenWebView",
            "removeAllWebViews(",
            "unloadTab(",
            "TabSuspensionService(",
            "WebViewCoordinator(",
        ]

        for pattern in forbiddenPatterns {
            XCTAssertFalse(source.contains(pattern), "\(pattern) should not be called from Settings")
        }
    }

    private static var performanceCopy: String {
        (
            SumiMemoryModeSettingsDescriptor.all.flatMap {
                [$0.title, $0.detail]
            } + [SumiMemoryModeSettingsDescriptor.launcherPreservationCopy]
        )
        .joined(separator: " ")
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func combinedSource(in relativeDirectory: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directoryURL = repoRoot.appendingPathComponent(relativeDirectory)
        let fileURLs = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )?.compactMap { $0 as? URL } ?? []

        return try fileURLs
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
