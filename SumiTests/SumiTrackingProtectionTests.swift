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

    func testDisabledModuleDoesNotConstructTrackingRuntimeFactories() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return self.makeSettings()
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return self.makeDataStore()
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )

        XCTAssertFalse(module.isEnabled)
        XCTAssertNil(module.settingsIfEnabled())
        XCTAssertNil(module.dataStoreIfEnabled())
        XCTAssertNil(module.contentBlockingServiceIfEnabled())
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
    }

    func testDisabledModuleDoesNotConstructRuleListProviderOrEnabledAssets() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return self.makeSettings()
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return self.makeDataStore()
            },
            contentBlockingAssetsFactory: { settings, dataStore in
                probe.assetsCount += 1
                let ruleListProvider = SumiTrackingRuleListProvider(
                    settings: settings,
                    dataStore: dataStore
                )
                return SumiTrackingContentBlockingAssets(
                    ruleListProvider: ruleListProvider
                )
            }
        )

        XCTAssertNil(module.contentBlockingAssetsIfEnabled())
        XCTAssertNil(module.contentBlockingServiceIfEnabled())
        XCTAssertNil(
            module.normalTabContentBlockingDecision(
                for: URL(string: "https://www.example.com/path")!
            ).contentBlockingAssets
        )
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.assetsCount, 0)
    }

    func testEnabledModuleConstructsRuntimeLazilyOnce() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        let dataStore = makeDataStore()
        let service = SumiContentBlockingService(policy: .disabled)
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return settings
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return dataStore
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return service
            }
        )

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertTrue(module.settingsIfEnabled() === settings)
        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)

        XCTAssertTrue(module.contentBlockingServiceIfEnabled() === service)
        XCTAssertTrue(module.contentBlockingServiceIfEnabled() === service)
        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 1)
        XCTAssertEqual(probe.serviceCount, 1)
    }

    func testEnabledModuleExposesAndCachesModuleOwnedRuleListAssets() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "module-assets-\(requestCount)")]
        }
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return settings
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return dataStore
            },
            contentBlockingAssetsFactory: { settings, dataStore in
                probe.assetsCount += 1
                let ruleListProvider = SumiTrackingRuleListProvider(
                    settings: settings,
                    dataStore: dataStore,
                    trackingRuleSource: ruleSource,
                    siteDataPolicyStore: nil
                )
                return SumiTrackingContentBlockingAssets(
                    ruleListProvider: ruleListProvider
                )
            }
        )

        let assets = try XCTUnwrap(module.contentBlockingAssetsIfEnabled())
        XCTAssertTrue(module.contentBlockingAssetsIfEnabled() === assets)
        XCTAssertTrue(module.contentBlockingServiceIfEnabled() === assets.contentBlockingService)
        XCTAssertTrue(
            module.normalTabContentBlockingDecision(
                for: URL(string: "https://www.example.com/path")!
            ).contentBlockingAssets === assets
        )
        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 1)
        XCTAssertEqual(probe.assetsCount, 1)

        let ruleListSet = try assets.ruleListProvider.ruleListSet(profileId: nil)
        XCTAssertEqual(ruleListSet.definitions(for: .trackerDataSet).count, 1)
        XCTAssertEqual(ruleListSet.definitions(for: .siteDataCookieBlocking).count, 0)
    }

    func testTrackingRuleListProviderBuildsKindedSetFromCurrentWorkingData() throws {
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let provider = SumiTrackingRuleListProvider(
            settings: settings,
            dataStore: dataStore,
            siteDataPolicyStore: nil
        )

        let ruleListSet = try provider.ruleListSet(profileId: nil)

        XCTAssertEqual(ruleListSet.trackerDataSet.count, 1)
        XCTAssertEqual(ruleListSet.siteDataCookieBlocking.count, 0)
        XCTAssertEqual(ruleListSet.allDefinitions.count, 1)
        XCTAssertFalse(ruleListSet.isEmpty)
        XCTAssertEqual(
            ruleListSet.definitions(for: .trackerDataSet),
            ruleListSet.trackerDataSet
        )
    }

    func testEnabledModuleOwnedAssetsAttachRulesForProfiledNormalTabs() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "profiled-assets-\(requestCount)")]
        }
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingAssetsFactory: { settings, dataStore in
                let ruleListProvider = SumiTrackingRuleListProvider(
                    settings: settings,
                    dataStore: dataStore,
                    trackingRuleSource: ruleSource,
                    siteDataRuleSource: EmptySiteDataRuleSource()
                )
                return SumiTrackingContentBlockingAssets(
                    ruleListProvider: ruleListProvider
                )
            }
        )

        let assets = try XCTUnwrap(module.contentBlockingAssetsIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: assets.contentBlockingService,
            profileId: UUID()
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }

        XCTAssertTrue(
            assets.contentBlockingService.privacyConfigurationManager
                .privacyConfig
                .isEnabled(featureKey: .contentBlocking)
        )
        XCTAssertGreaterThanOrEqual(ruleSource.requestCount, 1)
    }

    func testDisablingModulePreventsFutureRuntimeAccess() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return self.makeSettings()
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return self.makeDataStore()
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )

        XCTAssertNotNil(module.contentBlockingServiceIfEnabled())
        XCTAssertEqual(probe.serviceCount, 1)

        registry.disable(.trackingProtection)

        XCTAssertFalse(module.isEnabled)
        XCTAssertNil(module.settingsIfEnabled())
        XCTAssertNil(module.dataStoreIfEnabled())
        XCTAssertNil(module.contentBlockingServiceIfEnabled())
        XCTAssertEqual(probe.serviceCount, 1)
    }

    func testEnabledModuleServicePreservesExistingTrackingContentBlockingBehavior() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "module-enabled-\(requestCount)")]
        }
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return settings
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return dataStore
            },
            contentBlockingServiceFactory: { settings, dataStore in
                probe.serviceCount += 1
                return SumiContentBlockingService(
                    policy: .disabled,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: ruleSource,
                    trackingDataStore: dataStore
                )
            }
        )

        let service = try XCTUnwrap(module.contentBlockingServiceIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )

        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }

        XCTAssertEqual(probe.settingsCount, 1)
        XCTAssertEqual(probe.dataStoreCount, 1)
        XCTAssertEqual(probe.serviceCount, 1)
        XCTAssertEqual(ruleSource.requestCount, 1)
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
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

    func testManualUpdateWhileModuleDisabledIsNoOpAndConstructsNoRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = TrackingProtectionModuleFactoryProbe()
        var updaterFactoryCount = 0
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return self.makeSettings()
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return self.makeDataStore()
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )

        let result = await module.updateTrackerDataManually {
            updaterFactoryCount += 1
            return SumiTrackerDataUpdater(fetch: { request in
                (
                    try Self.trackerDataJSON(domain: "disabled-update.example"),
                    Self.httpResponse(url: request.url, statusCode: 200)
                )
            })
        }

        XCTAssertEqual(result, .disabled)
        XCTAssertEqual(updaterFactoryCount, 0)
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
    }

    func testManualUpdateWhileEnabledStagesValidatesCommitsAndPublishesRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let compiler = CountingTrackingContentRuleListCompiler()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingServiceFactory: { settings, dataStore in
                SumiContentBlockingService(
                    policy: .disabled,
                    compiler: compiler,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                    trackingDataStore: dataStore
                )
            }
        )
        let trackerData = try Self.trackerDataJSON(domain: "manual-enabled.example")

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    trackerData,
                    Self.httpResponse(
                        url: request.url,
                        statusCode: 200,
                        headers: ["ETag": "\"manual-enabled\""]
                    )
                )
            })
        }

        guard case .downloaded(_, let resultETag) = result,
              resultETag == "\"manual-enabled\""
        else {
            return XCTFail("Expected downloaded result, got \(result)")
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(dataStore.metadata.currentSource, .downloaded)
        XCTAssertEqual(dataStore.downloadedETag, "\"manual-enabled\"")
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["manual-enabled.example"])
        XCTAssertNotNil(dataStore.metadata.lastSuccessfulUpdateDate)
        XCTAssertNil(dataStore.metadata.lastUpdateError)
        XCTAssertGreaterThanOrEqual(compiler.compileCount, 1)

        let service = try XCTUnwrap(module.contentBlockingServiceIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testManualUpdateWhileEnabledRefreshesProfileScopedRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingServiceFactory: { settings, dataStore in
                SumiContentBlockingService(
                    policy: .disabled,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                    trackingDataStore: dataStore
                )
            }
        )
        let service = try XCTUnwrap(module.contentBlockingServiceIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service,
            profileId: UUID()
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )
        let trackerData = try Self.trackerDataJSON(domain: "profile-manual-enabled.example")

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    trackerData,
                    Self.httpResponse(
                        url: request.url,
                        statusCode: 200,
                        headers: ["ETag": "\"profile-manual-enabled\""]
                    )
                )
            })
        }

        guard case .downloaded = result else {
            return XCTFail("Expected downloaded result, got \(result)")
        }
        try await waitUntil {
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue != originalIdentifier
        }
        XCTAssertEqual(dataStore.metadata.currentSource, .downloaded)
        XCTAssertEqual(dataStore.downloadedETag, "\"profile-manual-enabled\"")
    }

    func testFailedManualDownloadKeepsPreviousWorkingVersionAndRecordsError() async throws {
        let (module, dataStore, controller) = try await makePreviousWorkingUpdateHarness(
            previousDomain: "last-good-download.example",
            previousETag: "\"last-good-download\""
        )
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    Data("{}".utf8),
                    Self.httpResponse(url: request.url, statusCode: 503)
                )
            })
        }

        guard case .failed = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(activeDataSet.etag, "\"last-good-download\"")
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["last-good-download.example"])
        XCTAssertEqual(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue,
            originalIdentifier
        )
        XCTAssertNotNil(dataStore.metadata.lastUpdateError)
    }

    func testInvalidManualUpdateDataKeepsPreviousWorkingVersionAndRecordsError() async throws {
        let (module, dataStore, controller) = try await makePreviousWorkingUpdateHarness(
            previousDomain: "last-good-invalid.example",
            previousETag: "\"last-good-invalid\""
        )
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    Data("{\"trackers\":".utf8),
                    Self.httpResponse(url: request.url, statusCode: 200)
                )
            })
        }

        guard case .failed = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(activeDataSet.etag, "\"last-good-invalid\"")
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["last-good-invalid.example"])
        XCTAssertEqual(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue,
            originalIdentifier
        )
        XCTAssertNotNil(dataStore.metadata.lastUpdateError)
    }

    func testManualUpdateCompileFailureKeepsPreviousWorkingVersionAndRecordsError() async throws {
        let compiler = FailingAfterSuccessfulCompilesTrackingContentRuleListCompiler(
            allowedSuccessfulCompiles: 1
        )
        let (module, dataStore, controller) = try await makePreviousWorkingUpdateHarness(
            previousDomain: "last-good-compile.example",
            previousETag: "\"last-good-compile\"",
            compiler: compiler
        )
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )
        let trackerData = try Self.trackerDataJSON(domain: "compile-failure.example")

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    trackerData,
                    Self.httpResponse(
                        url: request.url,
                        statusCode: 200,
                        headers: ["ETag": "\"compile-failure\""]
                    )
                )
            })
        }

        guard case .failed = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(activeDataSet.etag, "\"last-good-compile\"")
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["last-good-compile.example"])
        XCTAssertEqual(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue,
            originalIdentifier
        )
        XCTAssertNotNil(dataStore.metadata.lastUpdateError)
    }

    func testManualUpdatePersistenceFailureKeepsPreviousWorkingVersionAndRecordsError() async throws {
        let blockedStorageParent = makeTemporaryDirectory()
        try FileManager.default.createDirectory(
            at: blockedStorageParent,
            withIntermediateDirectories: true
        )
        let blockedStoragePath = blockedStorageParent.appendingPathComponent("blocked-storage")
        try Data("not-a-directory".utf8).write(to: blockedStoragePath)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = SumiTrackingProtectionDataStore(
            userDefaults: makeUserDefaults(),
            storageDirectory: blockedStoragePath,
            bundledProvider: StaticBundledTrackerDataProvider()
        )
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingServiceFactory: { settings, dataStore in
                SumiContentBlockingService(
                    policy: .disabled,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                    trackingDataStore: dataStore
                )
            }
        )
        let service = try XCTUnwrap(module.contentBlockingServiceIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )
        let trackerData = try Self.trackerDataJSON(domain: "persistence-failure.example")

        let result = await module.updateTrackerDataManually {
            SumiTrackerDataUpdater(fetch: { request in
                (
                    trackerData,
                    Self.httpResponse(
                        url: request.url,
                        statusCode: 200,
                        headers: ["ETag": "\"persistence-failure\""]
                    )
                )
            })
        }

        guard case .failed = result else {
            return XCTFail("Expected failed result, got \(result)")
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(dataStore.metadata.currentSource, .bundled)
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["bundled.example"])
        XCTAssertEqual(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue,
            originalIdentifier
        )
        XCTAssertNotNil(dataStore.metadata.lastUpdateError)
    }

    func testManualResetToBundledIsExplicitAndPublishesAfterValidation() async throws {
        let (module, dataStore, controller) = try await makePreviousWorkingUpdateHarness(
            previousDomain: "downloaded-before-reset.example",
            previousETag: "\"downloaded-before-reset\""
        )
        let originalIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )

        let result = await module.resetTrackerDataToBundledManually()

        XCTAssertEqual(result, .resetToBundled)
        try await waitUntil {
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue != originalIdentifier
        }
        let activeDataSet = try dataStore.loadActiveDataSet()
        XCTAssertEqual(dataStore.metadata.currentSource, .bundled)
        XCTAssertEqual(activeDataSet.trackerData.trackers.keys.sorted(), ["bundled.example"])
        XCTAssertNil(dataStore.metadata.lastUpdateError)
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

    func testDefaultSiteOverrideIsInheritAndHostNormalizationUsesRegistrableDomain() throws {
        let settings = makeSettings()

        let url = URL(string: "https://sub.www.example.co.uk/path?tracker=1")!

        XCTAssertEqual(settings.override(for: url), .inherit)
        XCTAssertEqual(settings.normalizedHost(for: url), "example.co.uk")
        XCTAssertEqual(settings.normalizedHost(fromUserInput: "WWW.Example.COM/path?q=1"), "example.com")
    }

    func testModuleDisabledEffectivePolicyIsDisabledWithoutConstructingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let probe = TrackingProtectionModuleFactoryProbe()
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                probe.settingsCount += 1
                return self.makeSettings()
            },
            dataStoreFactory: {
                probe.dataStoreCount += 1
                return self.makeDataStore()
            },
            contentBlockingServiceFactory: { _, _ in
                probe.serviceCount += 1
                return SumiContentBlockingService(
                    policy: .enabled(ruleLists: [Self.validRuleListDefinition(hostSuffix: "disabled-module")])
                )
            }
        )

        let policy = module.effectivePolicy(for: URL(string: "https://www.example.com/path")!)
        let decision = module.normalTabContentBlockingDecision(for: URL(string: "https://www.example.com/path")!)

        XCTAssertEqual(policy.host, "example.com")
        XCTAssertFalse(policy.isEnabled)
        XCTAssertEqual(policy.source, .moduleDisabled)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertEqual(probe.settingsCount, 0)
        XCTAssertEqual(probe.dataStoreCount, 0)
        XCTAssertEqual(probe.serviceCount, 0)
    }

    func testEnabledModuleEffectivePolicyFollowsGlobalAndSiteOverrides() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { self.makeDataStore() },
            contentBlockingServiceFactory: { _, _ in
                SumiContentBlockingService(policy: .disabled)
            }
        )
        let url = URL(string: "https://www.example.com/path")!

        var policy = module.effectivePolicy(for: url)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertEqual(policy.source, .global)

        settings.setGlobalMode(.enabled)
        policy = module.effectivePolicy(for: url)
        XCTAssertTrue(policy.isEnabled)
        XCTAssertEqual(policy.source, .global)

        settings.setSiteOverride(.disabled, for: url)
        policy = module.effectivePolicy(for: url)
        XCTAssertFalse(policy.isEnabled)
        XCTAssertEqual(policy.source, .siteOverride(.disabled))

        settings.setSiteOverride(.enabled, for: url)
        policy = module.effectivePolicy(for: url)
        XCTAssertTrue(policy.isEnabled)
        XCTAssertEqual(policy.source, .siteOverride(.enabled))
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

    func testExistingControllerDoesNotRefreshWhenSiteOverrideChangesBeforeManualReload() async throws {
        let settings = makeSettings()
        let url = URL(string: "https://www.example.com/path")!
        let ruleSource = CountingTrackingRuleSource { requestCount, _ in
            [Self.validRuleListDefinition(hostSuffix: "profile-site-override-\(requestCount)")]
        }
        let service = SumiContentBlockingService(
            policy: .disabled,
            trackingProtectionSettings: settings,
            trackingRuleSource: ruleSource
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service,
            profileId: UUID()
        )
        await controller.awaitContentBlockingAssetsInstalled()

        settings.setGlobalMode(.enabled)
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }
        let enabledIdentifier = try XCTUnwrap(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue
        )
        let requestCountAfterGlobalEnable = ruleSource.requestCount

        settings.setSiteOverride(.disabled, for: url)
        try await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertFalse(settings.resolve(for: url).isEnabled)
        XCTAssertEqual(settings.override(for: url), .disabled)
        XCTAssertEqual(ruleSource.requestCount, requestCountAfterGlobalEnable)
        XCTAssertEqual(
            controller.contentBlockingAssets?.updateEvent.rules.first?.identifier.stringValue,
            enabledIdentifier
        )
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

    func testProductionSourcesDoNotUseSharedTrackingRuntimeOutsideModule() throws {
        let guardedSources = [
            "Sumi/Components/Settings/PrivacySettingsView.swift",
            "Sumi/Components/Sidebar/URLBarView.swift",
            "Sumi/Favicons/DDG/SumiDDGFaviconUserContentController.swift",
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ]

        for relativePath in guardedSources {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("SumiContentBlockingService.shared"), relativePath)
            XCTAssertFalse(source.contains("SumiTrackingProtectionSettings.shared"), relativePath)
            XCTAssertFalse(source.contains("SumiTrackingProtectionDataStore.shared"), relativePath)
            XCTAssertFalse(source.contains("SumiEmbeddedDDGTrackerDataRuleSource("), relativePath)
        }
    }

    func testManualTrackerDataUpdateIsNotStartedByStartupSettingsOrNormalTabs() throws {
        for relativePath in [
            "Sumi/Managers/BrowserManager/BrowserManager.swift",
            "Sumi/Models/BrowserConfig/BrowserConfig.swift",
            "Sumi/Models/Tab/Tab+WebViewRuntime.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("updateTrackerDataManually"), relativePath)
            XCTAssertFalse(source.contains("SumiTrackerDataUpdater("), relativePath)
        }

        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        XCTAssertTrue(settingsSource.contains(".accessibilityLabel(\"Update tracker data\")"))
        XCTAssertTrue(settingsSource.contains("await trackingProtectionModule.updateTrackerDataManually()"))
        XCTAssertFalse(settingsSource.contains(".task"))
        XCTAssertFalse(settingsSource.contains(".onAppear"))
        XCTAssertFalse(settingsSource.contains("SumiTrackerDataUpdater("))
    }

    func testTrackerDataUpdateHasNoAutomaticTimerOrSleepScheduler() throws {
        let moduleSource = try Self.source(named: "Sumi/ContentBlocking/SumiTrackingProtectionModule.swift")
        let dataSource = try Self.source(named: "Sumi/ContentBlocking/SumiTrackingProtection.swift")
        let serviceSource = try Self.source(named: "Sumi/ContentBlocking/SumiContentBlockingService.swift")

        for source in [moduleSource, dataSource] {
            XCTAssertFalse(source.contains("Timer"))
            XCTAssertFalse(source.contains("scheduledTimer"))
            XCTAssertFalse(source.contains("Task.sleep"))
        }
        XCTAssertFalse(moduleSource.localizedCaseInsensitiveContains("stale"))
        XCTAssertFalse(dataSource.localizedCaseInsensitiveContains("stale"))

        XCTAssertEqual(serviceSource.components(separatedBy: "Task.sleep").count - 1, 2)
        XCTAssertTrue(serviceSource.contains("scheduleTrackingPolicyRefresh"))
        XCTAssertTrue(serviceSource.contains("scheduleProfilePolicyRefresh"))
        XCTAssertFalse(serviceSource.contains("SumiTrackerDataUpdater("))
        XCTAssertFalse(serviceSource.contains("updateTrackerDataManually"))
    }

    func testTrackingRuleListPipelineAvoidsFutureDDGAndAdBlockingRuntimeFeatures() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiTrackingRuleListPipeline.swift")

        XCTAssertTrue(source.contains("SumiTrackingRuleListKind"))
        XCTAssertTrue(source.contains("SumiTrackingRuleListProvider"))
        XCTAssertTrue(source.contains("SumiTrackingContentBlockingAssets"))
        XCTAssertFalse(source.contains("ClickToLoad"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("surrogate"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("adblock"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("cosmetic"))
        XCTAssertFalse(source.contains("Timer"))
        XCTAssertFalse(source.contains("scheduledTimer"))
        XCTAssertFalse(source.contains("SumiTrackerDataUpdater("))
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

    private func makePreviousWorkingUpdateHarness(
        previousDomain: String,
        previousETag: String,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler()
    ) async throws -> (
        module: SumiTrackingProtectionModule,
        dataStore: SumiTrackingProtectionDataStore,
        controller: UserContentController
    ) {
        let harness = TestDefaultsHarness()
        defaultsSuites.append(harness.suiteName)
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let settings = makeSettings()
        settings.setGlobalMode(.enabled)
        let dataStore = makeDataStore()
        try dataStore.storeDownloadedData(
            Self.trackerDataJSON(domain: previousDomain),
            etag: previousETag
        )
        let module = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            dataStoreFactory: { dataStore },
            contentBlockingServiceFactory: { settings, dataStore in
                SumiContentBlockingService(
                    policy: .disabled,
                    compiler: compiler,
                    trackingProtectionSettings: settings,
                    trackingRuleSource: SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore),
                    trackingDataStore: dataStore
                )
            }
        )
        let service = try XCTUnwrap(module.contentBlockingServiceIfEnabled())
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        await controller.awaitContentBlockingAssetsInstalled()
        try await waitUntil {
            controller.contentBlockingAssets?.globalRuleLists.count == 1
        }
        return (module, dataStore, controller)
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

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

@MainActor
private final class TrackingProtectionModuleFactoryProbe {
    var settingsCount = 0
    var dataStoreCount = 0
    var serviceCount = 0
    var assetsCount = 0
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
private final class EmptySiteDataRuleSource: SumiSiteDataContentRuleProviding {
    func ruleLists(profileId: UUID?) throws -> [SumiContentRuleListDefinition] {
        _ = profileId
        return []
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

@MainActor
private final class FailingAfterSuccessfulCompilesTrackingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private let allowedSuccessfulCompiles: Int
    private(set) var lookupCount = 0
    private(set) var compileCount = 0

    init(allowedSuccessfulCompiles: Int) {
        self.allowedSuccessfulCompiles = allowedSuccessfulCompiles
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        lookupCount += 1
        return await wrapped.lookUpContentRuleList(forIdentifier: identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compileCount += 1
        guard compileCount <= allowedSuccessfulCompiles else {
            throw SumiTrackingProtectionTestError.unexpectedCompile
        }
        return try await wrapped.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedContentRuleList
        )
    }
}

private enum SumiTrackingProtectionTestError: Error {
    case unexpectedCompile
}
