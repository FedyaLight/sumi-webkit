import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SafariContentBlockerRuleLocatorTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
    }

    func testStaticJSONRulesLocateAndCompile() async throws {
        let candidate = try makeContentBlockerCandidate(
            resourceFiles: [
                .init(
                    relativePath: "blockerList.json",
                    data: Self.validRuleListData(blockedHost: "ads.example")
                ),
            ]
        )

        let located = try SafariContentBlockerRuleLocator.locateRules(in: candidate)
        XCTAssertEqual(located.definitions.count, 1)
        XCTAssertEqual(located.ignoredEmptyRuleListCount, 0)
        XCTAssertTrue(
            located.definitions[0].webKitStoreIdentifier
                .contains("com-example-contentblocker")
        )

        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: located.definitions)
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory
            .makeController(contentBlockingService: service)
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 1)
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.updateRuleCount, 1)
    }

    func testEmptyPlaceholderReportsUnavailable() throws {
        let candidate = try makeContentBlockerCandidate(
            resourceFiles: [
                .init(relativePath: "emptyBlockingRules.json", data: Data("[]".utf8)),
            ]
        )

        XCTAssertThrowsError(try SafariContentBlockerRuleLocator.locateRules(in: candidate)) { error in
            XCTAssertEqual(error as? SafariContentBlockerRuleLocatorError, .staticRulesUnavailable)
        }
    }

    func testEmptyPlaceholderIsIgnoredWhenNonEmptyRulesExist() throws {
        let candidate = try makeContentBlockerCandidate(
            resourceFiles: [
                .init(relativePath: "emptyBlockingRules.json", data: Data("[]".utf8)),
                .init(
                    relativePath: "General/blockerList.json",
                    data: Self.validRuleListData(blockedHost: "tracker.example")
                ),
            ]
        )

        let located = try SafariContentBlockerRuleLocator.locateRules(in: candidate)

        XCTAssertEqual(located.definitions.count, 1)
        XCTAssertEqual(located.ignoredEmptyRuleListCount, 1)
    }

    func testInvalidJSONReportsCompileFailureStatus() async throws {
        let candidate = try makeContentBlockerCandidate(
            resourceFiles: [
                .init(relativePath: "blockerList.json", data: Data("{]".utf8)),
            ]
        )
        let module = try makeModule()

        do {
            _ = try await module.enableSafariContentBlocker(from: candidate)
            XCTFail("Expected invalid JSON to fail")
        } catch {
            let record = try XCTUnwrap(
                module.safariContentBlockerRecord(
                    forBundleIdentifier: candidate.extensionBundleIdentifier
                )
            )
            XCTAssertEqual(record.compileStatus, .compileFailed)
            XCTAssertFalse(record.isEnabled)
            XCTAssertTrue(record.lastError?.contains("Invalid content blocker JSON") == true)
        }
    }

    func testResourceFingerprintChangesWhenRulesChange() throws {
        let candidate = try makeContentBlockerCandidate(
            resourceFiles: [
                .init(
                    relativePath: "blockerList.json",
                    data: Self.validRuleListData(blockedHost: "first.example")
                ),
            ]
        )

        let first = SafariContentBlockerRuleLocator.resourceFingerprint(
            appexURL: candidate.appexURL
        )
        let ruleURL = candidate.appexURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("blockerList.json")
        try Self.validRuleListData(blockedHost: "second.example")
            .write(to: ruleURL, options: [.atomic])

        let second = SafariContentBlockerRuleLocator.resourceFingerprint(
            appexURL: candidate.appexURL
        )
        XCTAssertNotEqual(first, second)
    }

    func testSiteOverridePersistsAcrossModuleInstancesAndClearsToInherit() throws {
        let defaults = UserDefaults(
            suiteName: "SafariContentBlockerRuleLocatorTests.\(UUID().uuidString)"
        )!
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))

        let firstModule = try makeModule(defaults: defaults)
        firstModule.setSafariContentBlockerSiteOverride(.disabled, for: url)

        let reloadedModule = try makeModule(defaults: defaults)
        XCTAssertFalse(
            reloadedModule.safariContentBlockerSiteState(for: url).isEnabledForSite
        )

        reloadedModule.setSafariContentBlockerSiteOverride(.inherit, for: url)

        let clearedModule = try makeModule(defaults: defaults)
        XCTAssertTrue(
            clearedModule.safariContentBlockerSiteState(for: url).isEnabledForSite
        )
    }

    private func makeContentBlockerCandidate(
        resourceFiles: [SafariExtensionScannerTestSupport.SyntheticResourceFile]
    ) throws -> DiscoveredSafariExtensionCandidate {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: scratchDirectory,
            appName: "ContentBlocker",
            appBundleIdentifier: "com.example.contentblocker.app",
            extensions: [
                .init(
                    name: "Content Blocker",
                    bundleIdentifier: "com.example.contentblocker",
                    displayName: "Content Blocker",
                    extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                    includeManifest: false,
                    includeExtensionAttributes: false,
                    resourceFiles: resourceFiles
                ),
            ]
        )

        var issues: [SafariExtensionScannerIssue] = []
        let candidates = SafariExtensionScanner()
            .inspectContainingAppBundle(at: appURL, issues: &issues)
        XCTAssertTrue(issues.isEmpty)
        return try XCTUnwrap(candidates.first)
    }

    private func makeModule(
        defaults: UserDefaults = UserDefaults(
            suiteName: "SafariContentBlockerRuleLocatorTests.\(UUID().uuidString)"
        )!
    ) throws -> SumiExtensionsModule {
        let container = try ModelContainer(
            for: SafariContentBlockerEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(true, for: .extensions)
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container)
        )
    }

    private static func validRuleListData(blockedHost: String) -> Data {
        Data(
            """
            [
              {
                "action": { "type": "block" },
                "trigger": { "url-filter": ".*", "if-domain": ["\(blockedHost)"] }
              }
            ]
            """.utf8
        )
    }
}
