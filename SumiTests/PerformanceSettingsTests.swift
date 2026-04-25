import XCTest

@testable import Sumi

@MainActor
final class PerformanceSettingsTests: XCTestCase {
    func testDefaultMemoryModeIsBalanced() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let settings = SumiSettingsService(userDefaults: harness.defaults)

        XCTAssertEqual(settings.memoryMode, .balanced)
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

    func testPerformanceSettingsExposeAllMemoryModes() throws {
        XCTAssertEqual(
            SumiMemoryModeSettingsDescriptor.all.map(\.mode),
            [.lightweight, .balanced, .performance]
        )
        XCTAssertEqual(
            Set(SumiMemoryModeSettingsDescriptor.all.map(\.mode)),
            Set(SumiMemoryMode.allCases)
        )
        XCTAssertEqual(
            SumiMemoryModeSettingsDescriptor.all.map(\.title),
            ["Lightweight", "Balanced", "Performance"]
        )

        let source = try Self.source(named: "Sumi/Components/Settings/Tabs/Performance.swift")
        XCTAssertTrue(source.contains("Picker(\"Memory Mode\""))
        XCTAssertTrue(source.contains("ForEach(SumiMemoryModeSettingsDescriptor.all)"))
    }

    func testPerformanceSettingsCopyMatchesMemoryModeContract() {
        let copy = Self.performanceCopy

        XCTAssertTrue(copy.contains("hidden eligible WebView instances"))
        XCTAssertTrue(copy.contains("reduce memory usage"))
        XCTAssertTrue(copy.contains("Recommended default"))
        XCTAssertTrue(copy.contains("suspend hidden inactive tabs after a timeout"))
        XCTAssertTrue(copy.contains("Keeps more tabs warm"))
        XCTAssertTrue(copy.contains("may use more memory"))
        XCTAssertTrue(copy.contains("Suspended tabs remain visible"))
        XCTAssertTrue(copy.contains("Pinned tabs and Essentials remain launchers"))
        XCTAssertTrue(copy.contains("does not remove Essentials"))
        XCTAssertTrue(copy.contains("convert them into normal tabs"))
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
            XCTAssertFalse(source.contains("memoryMode"), "\(sourcePath) should not consume memory modes")
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
