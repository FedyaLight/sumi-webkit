import BrowserServicesKit
import Foundation
import TrackerRadarKit
import UserScript
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiTrackingProtectionTests: XCTestCase {
    private var defaultsSuites: [String] = []
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for suite in defaultsSuites {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        defaultsSuites.removeAll()
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testDefaultDisabledLoadsNoTrackerDataAndCompilesNoRules() async throws {
        let settings = makeSettings()
        let source = CountingTrackingRuleSource()
        let compiler = RejectingTrackingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            trackingProtectionSettings: settings,
            trackingRuleSource: source
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(source.requestCount, 0)
        XCTAssertEqual(compiler.lookupCount, 0)
        XCTAssertEqual(compiler.compileCount, 0)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
        XCTAssertFalse(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertFalse(controller.userScripts.contains { script in
            let source = script.source.lowercased()
            return source.contains("contentblockerrules")
                || source.contains("surrogates")
                || source.contains("trackerresolver")
        })
    }

    func testManualUpdateWhileDisabledStoresOnlyAndDoesNotCompileOrAttach() async throws {
        let settings = makeSettings()
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource()
        let compiler = RejectingTrackingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            trackingProtectionSettings: settings,
            trackingRuleSource: ruleSource,
            trackingDataStore: dataStore
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()

        let trackerData = try Self.trackerDataJSON(domain: "manual-disabled.example")
        let updater = SumiTrackerDataUpdater(fetch: { request in
            (
                trackerData,
                Self.httpResponse(
                    url: request.url,
                    statusCode: 200,
                    headers: ["ETag": "\"manual-disabled\""]
                )
            )
        })

        await dataStore.updateTrackerData(using: updater)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(dataStore.metadata.currentSource, .downloaded)
        XCTAssertEqual(dataStore.downloadedETag, "\"manual-disabled\"")
        XCTAssertEqual(ruleSource.requestCount, 0)
        XCTAssertEqual(compiler.lookupCount, 0)
        XCTAssertEqual(compiler.compileCount, 0)
        XCTAssertEqual(controller.contentBlockingAssets?.globalRuleLists.count, 0)
    }

    func testManualUpdateWhileEnabledRegeneratesCompilesAndPublishesRules() async throws {
        let settings = makeSettings()
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "enabled-update-\(requestCount)")]
        }
        let compiler = CountingTrackingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            trackingProtectionSettings: settings,
            trackingRuleSource: ruleSource,
            trackingDataStore: dataStore
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()

        settings.setGlobalMode(.enabled)
        try await waitUntil {
            ruleSource.requestCount == 1 && controller.contentBlockingAssets?.globalRuleLists.count == 1
        }

        let trackerData = try Self.trackerDataJSON(domain: "manual-enabled.example")
        let updater = SumiTrackerDataUpdater(fetch: { request in
            (
                trackerData,
                Self.httpResponse(
                    url: request.url,
                    statusCode: 200,
                    headers: ["ETag": "\"manual-enabled\""]
                )
            )
        })

        await dataStore.updateTrackerData(using: updater)
        try await waitUntil {
            ruleSource.requestCount == 2
                && compiler.compileCount >= 2
                && controller.contentBlockingAssets?.globalRuleLists.count == 1
        }

        XCTAssertEqual(dataStore.metadata.currentSource, .downloaded)
        XCTAssertEqual(dataStore.downloadedETag, "\"manual-enabled\"")
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testFailedManualUpdatePreservesLastGoodDownloadedData() async throws {
        let dataStore = makeDataStore()
        let lastGoodData = try Self.trackerDataJSON(domain: "last-good.example")
        try dataStore.storeDownloadedData(lastGoodData, etag: "\"last-good\"")

        let failingUpdater = SumiTrackerDataUpdater(fetch: { request in
            (
                Data("{}".utf8),
                Self.httpResponse(url: request.url, statusCode: 503)
            )
        })

        await dataStore.updateTrackerData(using: failingUpdater)

        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(dataStore.metadata.currentSource, .downloaded)
        XCTAssertEqual(activeDataSet.etag, "\"last-good\"")
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["last-good.example"])
        XCTAssertNotNil(dataStore.metadata.lastUpdateError)
    }

    func testResetToBundledPublishesOnlyWhenProtectionIsActive() async throws {
        let settings = makeSettings()
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "reset-\(requestCount)")]
        }
        let service = SumiContentBlockingService(
            policy: .disabled,
            trackingProtectionSettings: settings,
            trackingRuleSource: ruleSource,
            trackingDataStore: dataStore
        )
        _ = service

        try dataStore.storeDownloadedData(
            Self.trackerDataJSON(domain: "reset-disabled.example"),
            etag: "\"reset-disabled\""
        )
        dataStore.resetToBundled()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(ruleSource.requestCount, 0)
        XCTAssertEqual(dataStore.metadata.currentSource, .bundled)

        settings.setGlobalMode(.enabled)
        try await waitUntil { ruleSource.requestCount == 1 }
        try dataStore.storeDownloadedData(
            Self.trackerDataJSON(domain: "reset-enabled.example"),
            etag: "\"reset-enabled\""
        )
        try await waitUntil { ruleSource.requestCount == 2 }
        dataStore.resetToBundled()
        try await waitUntil { ruleSource.requestCount == 3 }
        XCTAssertEqual(dataStore.metadata.currentSource, .bundled)
    }

    func testGeneratedRulesAreTrackerOnlyAndRespectSitePolicyScopes() throws {
        let dataStore = makeDataStore()
        let source = SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore)

        let globalEnabledRules = try source.ruleLists(
            for: SumiTrackingProtectionPolicy(
                globalMode: .enabled,
                enabledSiteHosts: [],
                disabledSiteHosts: ["example.com"]
            )
        )
        let globalEnabledJSON = try Self.decodedRuleJSON(from: globalEnabledRules)
        XCTAssertTrue(Self.ruleJSON(globalEnabledJSON, containsAction: "block"))
        XCTAssertTrue(Self.ruleJSON(globalEnabledJSON, containsTriggerKey: "if-domain", value: "*example.com"))
        XCTAssertFalse(Self.ruleJSON(globalEnabledJSON, containsAction: "css-display-none"))

        let siteEnabledRules = try source.ruleLists(
            for: SumiTrackingProtectionPolicy(
                globalMode: .disabled,
                enabledSiteHosts: ["site.example"],
                disabledSiteHosts: []
            )
        )
        let siteEnabledJSON = try Self.decodedRuleJSON(from: siteEnabledRules)
        XCTAssertTrue(Self.ruleJSON(siteEnabledJSON, containsAction: "block"))
        XCTAssertTrue(Self.ruleJSON(siteEnabledJSON, containsAction: "ignore-previous-rules"))
        XCTAssertTrue(Self.ruleJSON(siteEnabledJSON, containsTriggerKey: "unless-domain", value: "*site.example"))
        XCTAssertFalse(Self.ruleJSON(siteEnabledJSON, containsAction: "css-display-none"))
    }

    func testTrackingPolicyResolutionAndPersistence() throws {
        let defaults = makeUserDefaults()
        let settings = SumiTrackingProtectionSettings(userDefaults: defaults)
        let url = URL(string: "https://www.example.com/path")!

        let defaultPolicy = settings.resolve(for: url)
        XCTAssertEqual(defaultPolicy.host, "example.com")
        XCTAssertFalse(defaultPolicy.isEnabled)
        XCTAssertEqual(defaultPolicy.source, .global)

        settings.setGlobalMode(.enabled)
        let globalEnabledPolicy = settings.resolve(for: url)
        XCTAssertTrue(globalEnabledPolicy.isEnabled)
        XCTAssertEqual(globalEnabledPolicy.source, .global)

        settings.setSiteOverride(.disabled, for: url)
        let siteDisabledPolicy = settings.resolve(for: url)
        XCTAssertFalse(siteDisabledPolicy.isEnabled)
        XCTAssertEqual(siteDisabledPolicy.source, .siteOverride(.disabled))

        settings.setGlobalMode(.disabled)
        settings.setSiteOverride(.enabled, for: url)
        let siteEnabledPolicy = settings.resolve(for: url)
        XCTAssertTrue(siteEnabledPolicy.isEnabled)
        XCTAssertEqual(siteEnabledPolicy.source, .siteOverride(.enabled))

        let reloaded = SumiTrackingProtectionSettings(userDefaults: defaults)
        XCTAssertEqual(reloaded.globalMode, .disabled)
        XCTAssertTrue(reloaded.resolve(for: url).isEnabled)
        XCTAssertEqual(reloaded.resolve(for: url).source, .siteOverride(.enabled))
    }

    func testURLHubToggleOverrideEnablesSiteWithoutChangingGlobalMode() throws {
        let settings = makeSettings()
        let url = URL(string: "https://www.example.com/path")!

        XCTAssertEqual(settings.globalMode, .disabled)
        let override = URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(
            for: settings.resolve(for: url)
        )
        settings.setSiteOverride(override, for: url)

        XCTAssertEqual(override, .enabled)
        XCTAssertEqual(settings.globalMode, .disabled)
        XCTAssertEqual(settings.override(for: url), .enabled)
        XCTAssertTrue(settings.resolve(for: url).isEnabled)
    }

    func testURLHubToggleOverrideDisablesSiteWithoutChangingGlobalMode() throws {
        let settings = makeSettings()
        let url = URL(string: "https://www.example.com/path")!
        settings.setGlobalMode(.enabled)

        let override = URLBarTrackingProtectionPresenter.siteOverrideAfterToggle(
            for: settings.resolve(for: url)
        )
        settings.setSiteOverride(override, for: url)

        XCTAssertEqual(override, .disabled)
        XCTAssertEqual(settings.globalMode, .enabled)
        XCTAssertEqual(settings.override(for: url), .disabled)
        XCTAssertFalse(settings.resolve(for: url).isEnabled)
    }

    func testRapidPolicyChangesAreCoalescedBeforeRuleGeneration() async throws {
        let settings = makeSettings()
        let source = CountingTrackingRuleSource { _, _ in [] }
        let service = SumiContentBlockingService(
            policy: .disabled,
            trackingProtectionSettings: settings,
            trackingRuleSource: source
        )
        _ = service

        settings.setGlobalMode(.enabled)
        _ = settings.setSiteOverride(.disabled, forUserInput: "example.com")
        _ = settings.setSiteOverride(.enabled, forUserInput: "example.org")

        try await waitUntil { source.requestCount == 1 }
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(source.requestCount, 1)
        XCTAssertEqual(source.policies.last?.globalMode, .enabled)
        XCTAssertEqual(source.policies.last?.enabledSiteHosts, ["example.org"])
        XCTAssertEqual(source.policies.last?.disabledSiteHosts, ["example.com"])
    }

    private func makeSettings() -> SumiTrackingProtectionSettings {
        SumiTrackingProtectionSettings(userDefaults: makeUserDefaults())
    }

    private func makeDataStore() -> SumiTrackingProtectionDataStore {
        SumiTrackingProtectionDataStore(
            userDefaults: makeUserDefaults(),
            storageDirectory: makeTemporaryDirectory(),
            bundledProvider: StaticBundledTrackerDataProvider()
        )
    }

    private func makeUserDefaults() -> UserDefaults {
        let suite = "SumiTrackingProtectionTests.\(UUID().uuidString)"
        defaultsSuites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiTrackingProtectionTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    nonisolated fileprivate static func trackerDataJSON(domain: String = "tracker.example") throws -> Data {
        let ownerName = "Tracker Example"
        let tracker = KnownTracker(
            domain: domain,
            defaultAction: .block,
            owner: KnownTracker.Owner(
                name: ownerName,
                displayName: ownerName,
                ownedBy: nil
            ),
            prevalence: 1,
            subdomains: nil,
            categories: ["Analytics"],
            rules: nil
        )
        let entity = Entity(
            displayName: ownerName,
            domains: [domain],
            prevalence: 1
        )
        let trackerData = TrackerData(
            trackers: [domain: tracker],
            entities: [ownerName: entity],
            domains: [domain: ownerName],
            cnames: nil
        )
        return try JSONEncoder().encode(trackerData)
    }

    nonisolated private static func validRuleListDefinition(hostSuffix: String) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "SumiTrackingProtectionTestRules-\(hostSuffix)-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*tracker-\(hostSuffix)\\\\.example/.*",
                  "load-type": ["third-party"]
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    nonisolated private static func httpResponse(
        url: URL?,
        statusCode: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url ?? URL(string: "https://static.example/trackerData.json")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static func decodedRuleJSON(
        from definitions: [SumiContentRuleListDefinition]
    ) throws -> [[String: Any]] {
        let data = try XCTUnwrap(definitions.first?.encodedContentRuleList.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private static func ruleJSON(
        _ rules: [[String: Any]],
        containsAction action: String
    ) -> Bool {
        rules.contains { rule in
            (rule["action"] as? [String: Any])?["type"] as? String == action
        }
    }

    private static func ruleJSON(
        _ rules: [[String: Any]],
        containsTriggerKey key: String,
        value: String
    ) -> Bool {
        rules.contains { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let values = trigger[key] as? [String]
            else {
                return false
            }
            return values.contains(value)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for tracking-protection condition")
    }
}

private struct StaticBundledTrackerDataProvider: SumiBundledTrackerDataProviding {
    let embeddedDataEtag = "\"bundled-test\""
    let embeddedDataSHA = "bundled-test-sha"

    func embeddedData() throws -> Data {
        try SumiTrackingProtectionTests.trackerDataJSON(domain: "bundled.example")
    }
}

@MainActor
private final class CountingTrackingRuleSource: SumiTrackingProtectionRuleProviding {
    private let makeDefinitions: (Int, SumiTrackingProtectionPolicy) -> [SumiContentRuleListDefinition]
    private(set) var requestCount = 0
    private(set) var policies: [SumiTrackingProtectionPolicy] = []

    init(
        makeDefinitions: @escaping (Int, SumiTrackingProtectionPolicy) -> [SumiContentRuleListDefinition] = { _, _ in [] }
    ) {
        self.makeDefinitions = makeDefinitions
    }

    func ruleLists(for policy: SumiTrackingProtectionPolicy) throws -> [SumiContentRuleListDefinition] {
        requestCount += 1
        policies.append(policy)
        return makeDefinitions(requestCount, policy)
    }
}

@MainActor
private final class RejectingTrackingContentRuleListCompiler: SumiContentRuleListCompiling {
    private(set) var lookupCount = 0
    private(set) var compileCount = 0

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        _ = identifier
        lookupCount += 1
        return nil
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        _ = identifier
        _ = encodedContentRuleList
        compileCount += 1
        throw SumiTrackingProtectionTestError.unexpectedCompile
    }
}

@MainActor
private final class CountingTrackingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private(set) var lookupCount = 0
    private(set) var compileCount = 0

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        lookupCount += 1
        return await wrapped.lookUpContentRuleList(forIdentifier: identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compileCount += 1
        return try await wrapped.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedContentRuleList
        )
    }
}

private enum SumiTrackingProtectionTestError: Error {
    case unexpectedCompile
}
