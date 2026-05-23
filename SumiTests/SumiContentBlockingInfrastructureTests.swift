import Combine
import Network
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiContentBlockingInfrastructureTests: XCTestCase {
    private var preexistingCompiledRuleListIdentifiers = Set<String>()

    override func setUp() async throws {
        try await super.setUp()
        preexistingCompiledRuleListIdentifiers = Set(
            await SumiWKContentRuleListCompiler().availableContentRuleListIdentifiers()
        )
    }

    override func tearDown() async throws {
        let compiler = SumiWKContentRuleListCompiler()
        let currentIdentifiers = Set(await compiler.availableContentRuleListIdentifiers())
        for identifier in currentIdentifiers.subtracting(preexistingCompiledRuleListIdentifiers) {
            try? await compiler.removeContentRuleList(forIdentifier: identifier)
        }
        preexistingCompiledRuleListIdentifiers.removeAll()
        try await super.tearDown()
    }

    func testDefaultFactoryInstallsDisabledAssetsWithoutContentBlockingService() async throws {
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController()
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 0)
        XCTAssertFalse(summary.isContentBlockingFeatureEnabled)
        XCTAssertFalse(controller.userScripts.isEmpty)
    }

    func testDefaultFactoryExposesDisabledAssetsBeforeAwaitingInstallation() throws {
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController()
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 0)
        XCTAssertEqual(summary.updateRuleCount, 0)
        XCTAssertFalse(summary.isContentBlockingFeatureEnabled)
    }

    func testDisabledEmptyAssetSourceIsCheapAndHasNoRuleLists() async throws {
        let scriptsProvider = SumiNormalTabUserScripts()
        let assetSource = SumiNormalTabContentBlockingAssetSource.disabledEmpty(
            scriptsProvider: scriptsProvider
        )
        var publishedAssetCount = 0
        let cancellable = assetSource.assetsPublisher.sink { _ in
            publishedAssetCount += 1
        }
        defer { cancellable.cancel() }

        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: scriptsProvider
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 0)
        XCTAssertFalse(summary.isContentBlockingFeatureEnabled)
        XCTAssertEqual(publishedAssetCount, 0)
        XCTAssertNotNil(assetSource.initialContent)
        XCTAssertFalse(assetSource.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertTrue(scriptsProvider.userScripts.isEmpty == false)
    }

    func testDefaultPolicyInstallsNoGlobalRuleListsThroughNormalTabController() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 0)
        XCTAssertFalse(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertFalse(summary.isContentBlockingFeatureEnabled)
        XCTAssertFalse(controller.userScripts.isEmpty)
    }

    func testEnabledPolicyCompilesAndAttachesSmallWebKitRuleList() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 1)
        XCTAssertEqual(summary.updateRuleCount, 1)
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
    }

    func testAssetSummaryReportsStoreLookupAndAddedIdentifiersSeparately() async throws {
        let definition = Self.validRuleListDefinition(
            name: "SumiLookupSummaryRuleList-\(UUID().uuidString)",
            blockedHost: "lookup-summary.example"
        )
        let expectedStoreIdentifier = Self.storeIdentifier(for: definition)
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [definition])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertEqual(summary.lookupSucceededIdentifiers, [expectedStoreIdentifier])
        XCTAssertTrue(summary.lookupFailedIdentifiers.isEmpty)
        XCTAssertEqual(summary.addedToUserContentControllerIdentifiers, [expectedStoreIdentifier])
        XCTAssertEqual(summary.globalRuleListIdentifiers, [expectedStoreIdentifier])
    }

    func testDynamicRuleProviderWaitsForInitialResolvedRulesInsteadOfPublishingEmptyPlaceholder() async throws {
        let provider = StaticContentRuleListSetProvider(
            ruleListSet: SumiContentRuleListSet(
                definitions: [Self.validRuleListDefinition()]
            )
        )
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: CountingContentRuleListCompiler(),
            ruleListProvider: provider,
            compiledRuleListCatalog: InMemoryCompiledRuleListCatalog()
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertTrue(summary.isInstalled)
        XCTAssertEqual(summary.globalRuleListCount, 1)
        XCTAssertEqual(summary.updateRuleCount, 1)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
    }

    func testInvalidRuleDataFailsSafelyWithoutAttachingRules() async throws {
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                SumiContentRuleListDefinition(
                    name: "SumiInvalidRuleList-\(UUID().uuidString)",
                    encodedContentRuleList: "{]"
                )
            ])
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertEqual(summary.globalRuleListCount, 0)
        XCTAssertFalse(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
        XCTAssertFalse(summary.isContentBlockingFeatureEnabled)
    }

    func testInvalidReplacementPolicyPreservesPreviouslyInstalledRuleLists() async throws {
        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()]),
            compiler: compiler
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 1)

        service.setPolicy(.enabled(ruleLists: [
            SumiContentRuleListDefinition(
                name: "SumiInvalidReplacementRuleList-\(UUID().uuidString)",
                encodedContentRuleList: "{]"
            )
        ]))
        try await waitForCompilerFailure(compiler)

        let summary = normalTabController.contentBlockingAssetSummary
        XCTAssertEqual(summary.globalRuleListCount, 1)
        XCTAssertTrue(summary.isContentBlockingFeatureEnabled)
        XCTAssertTrue(service.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking))
    }

    func testPolicyUpdateReplacesRuleListsOnExistingNormalTabController() async throws {
        let service = SumiContentBlockingService(policy: .disabled)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(normalTabController.contentBlockingAssetSummary.globalRuleListCount, 0)

        service.setPolicy(.enabled(ruleLists: [Self.validRuleListDefinition()]))
        let enabledRuleListCount = await Self.waitForAssetRuleListCount(on: normalTabController) { $0 == 1 }
        XCTAssertEqual(enabledRuleListCount, 1)

        service.setPolicy(.disabled)
        let disabledRuleListCount = await Self.waitForAssetRuleListCount(on: normalTabController) { $0 == 0 }
        XCTAssertEqual(disabledRuleListCount, 0)
    }

    func testCompiledRuleListsAreCachedAcrossControllersAndScriptReplacement() async throws {
        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()]),
            compiler: compiler
        )

        let firstController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let firstNormalTabController = try XCTUnwrap(firstController.sumiNormalTabUserContentController)
        await firstNormalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(compiler.compileCount, 1)

        let secondController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let secondNormalTabController = try XCTUnwrap(secondController.sumiNormalTabUserContentController)
        await secondNormalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(compiler.compileCount, 1)

        let replacementProvider = SumiNormalTabUserScripts(
            managedUserScripts: [TestContentBlockingProviderUserScript(source: "window.__sumiReplacementScript = true;")]
        )
        await firstNormalTabController.replaceNormalTabUserScripts(with: replacementProvider)
        XCTAssertEqual(compiler.compileCount, 1)
    }

    func testWarmStoreRuleListDoesNotPerformDuplicateSmokeLookup() async throws {
        let definition = Self.validRuleListDefinition(
            name: "SumiWarmStoreRuleList-\(UUID().uuidString)",
            blockedHost: "warm-store.example"
        )
        let storeIdentifier = Self.storeIdentifier(for: definition)

        let setupService = SumiContentBlockingService(
            policy: .enabled(ruleLists: [definition]),
            compiler: CountingContentRuleListCompiler()
        )
        let setupController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: setupService
        )
        let setupNormalTabController = try XCTUnwrap(setupController.sumiNormalTabUserContentController)
        await setupNormalTabController.waitForContentBlockingAssetsInstalled()
        setupNormalTabController.cleanUpBeforeClosing()

        let warmCompiler = CountingContentRuleListCompiler()
        let warmService = SumiContentBlockingService(
            policy: .enabled(ruleLists: [definition]),
            compiler: warmCompiler
        )
        let warmController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: warmService
        )
        let warmNormalTabController = try XCTUnwrap(warmController.sumiNormalTabUserContentController)
        await warmNormalTabController.waitForContentBlockingAssetsInstalled()
        defer { warmNormalTabController.cleanUpBeforeClosing() }

        let summary = warmNormalTabController.contentBlockingAssetSummary
        XCTAssertEqual(summary.lookupSucceededIdentifiers, [storeIdentifier])
        XCTAssertEqual(warmCompiler.lookupCount, 1)
        XCTAssertEqual(warmCompiler.canLookupCount, 0)
        XCTAssertEqual(warmCompiler.compileCount, 0)
    }

    func testExistingRuleListUpdateLooksUpWarmRuleListsWithoutRecompiling() async throws {
        let definition = Self.validRuleListDefinition(
            name: "SumiExistingRuleListUpdate-\(UUID().uuidString)",
            blockedHost: "existing-update.example"
        )

        let setupService = SumiContentBlockingService(
            policy: .enabled(ruleLists: [definition]),
            compiler: CountingContentRuleListCompiler()
        )
        let setupController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: setupService
        )
        let setupNormalTabController = try XCTUnwrap(setupController.sumiNormalTabUserContentController)
        await setupNormalTabController.waitForContentBlockingAssetsInstalled()
        setupNormalTabController.cleanUpBeforeClosing()

        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            compiledRuleListCatalog: InMemoryCompiledRuleListCatalog()
        )

        let prepared = try await service.prepareExistingRuleListUpdate(
            ruleLists: [definition.metadataOnly()]
        )

        XCTAssertEqual(prepared.updateEvent.rules.count, 1)
        XCTAssertEqual(compiler.lookupCount, 1)
        XCTAssertEqual(compiler.canLookupCount, 0)
        XCTAssertEqual(compiler.compileCount, 0)
    }

    func testExistingRuleListUpdateFailsWithoutCompilingWhenStoreEntryIsMissing() async throws {
        let definition = Self.validRuleListDefinition(
            name: "SumiMissingExistingRuleListUpdate-\(UUID().uuidString)",
            blockedHost: "missing-existing-update.example"
        )
        let identifier = Self.storeIdentifier(for: definition)
        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            compiledRuleListCatalog: InMemoryCompiledRuleListCatalog()
        )

        do {
            _ = try await service.prepareExistingRuleListUpdate(
                ruleLists: [definition.metadataOnly()]
            )
            XCTFail("Expected lookup-only restore to report the missing compiled rule list")
        } catch let error as SumiContentBlockingCompilationError {
            XCTAssertEqual(error.identifier, identifier)
        }

        XCTAssertEqual(compiler.lookupCount, 1)
        XCTAssertEqual(compiler.canLookupCount, 0)
        XCTAssertEqual(compiler.compileCount, 0)
    }

    func testPolicyUpdateRemovesPreviousCompiledRuleListForSameName() async throws {
        let compiler = CountingContentRuleListCompiler()
        let catalog = InMemoryCompiledRuleListCatalog()
        let ruleListName = "SumiReplacementCleanupRuleList-\(UUID().uuidString)"
        let firstDefinition = Self.validRuleListDefinition(
            name: ruleListName,
            blockedHost: "first-cleanup.example"
        )
        let secondDefinition = Self.validRuleListDefinition(
            name: ruleListName,
            blockedHost: "second-cleanup.example"
        )
        let firstIdentifier = Self.storeIdentifier(for: firstDefinition)
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [firstDefinition]),
            compiler: compiler,
            compiledRuleListCatalog: catalog
        )
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        await normalTabController.waitForContentBlockingAssetsInstalled()
        XCTAssertFalse(compiler.removedIdentifiers.contains(firstIdentifier))

        service.setPolicy(.enabled(ruleLists: [secondDefinition]))
        let enabledRuleListCount = await Self.waitForAssetRuleListCount(on: normalTabController) { $0 == 1 }
        XCTAssertEqual(enabledRuleListCount, 1)

        try await waitForRemovedIdentifier(firstIdentifier, in: compiler)
    }

    func testValidationRemovesTransientCompiledRuleList() async throws {
        let compiler = CountingContentRuleListCompiler()
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            compiledRuleListCatalog: InMemoryCompiledRuleListCatalog()
        )
        let definition = Self.validRuleListDefinition(
            name: "SumiValidationCleanupRuleList-\(UUID().uuidString)",
            blockedHost: "validation-cleanup.example"
        )
        let identifier = Self.storeIdentifier(for: definition)

        try await service.validateRuleLists([definition])

        try await waitForRemovedIdentifier(identifier, in: compiler)
    }

    func testFunctionalWebKitSmokeOffLoadsResourceAndAdblockBlocksResource() async throws {
        let server = try await LocalHTTPResourceServer.start()
        defer { server.stop() }

        let offController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: SumiContentBlockingService(policy: .disabled)
        )
        let offNormalController = try XCTUnwrap(offController.sumiNormalTabUserContentController)
        await offNormalController.waitForContentBlockingAssetsInstalled()
        let offWebView = makeWebView(userContentController: offController)
        try await loadURL(server.pageURL(cacheBuster: UUID().uuidString), into: offWebView)

        let offLoadedResource = await server.waitForRequest(path: "/blocked-resource.png", timeout: 2)
        XCTAssertTrue(offLoadedResource, "Off should allow the known test resource to reach the local HTTP server.")

        server.resetRequests()

        let blockedIdentifier = "sumi.adblock.network.functional-smoke-\(UUID().uuidString)"
        let service = SumiContentBlockingService(
            policy: .enabled(ruleLists: [
                SumiContentRuleListDefinition(
                    name: blockedIdentifier,
                    encodedContentRuleList: """
                    [
                      {
                        "trigger": {
                          "url-filter": ".*blocked-resource\\\\.png.*"
                        },
                        "action": {
                          "type": "block"
                        }
                      }
                    ]
                    """,
                    storeIdentifierOverride: blockedIdentifier
                ),
            ])
        )
        let adblockController: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingService: service
        )
        let adblockNormalController = try XCTUnwrap(adblockController.sumiNormalTabUserContentController)
        await adblockNormalController.waitForContentBlockingAssetsInstalled()
        let summary = adblockNormalController.contentBlockingAssetSummary
        XCTAssertEqual(summary.lookupSucceededIdentifiers, [blockedIdentifier])
        XCTAssertEqual(summary.addedToUserContentControllerIdentifiers, [blockedIdentifier])

        let adblockWebView = makeWebView(userContentController: adblockController)
        try await loadURL(server.pageURL(cacheBuster: UUID().uuidString), into: adblockWebView)

        let adblockLoadedResource = await server.waitForRequest(path: "/blocked-resource.png", timeout: 1)
        XCTAssertFalse(adblockLoadedResource, "Adblock must attach a WKContentRuleList that prevents the known resource request.")
    }

    func testPreparedUpdateCompilesAllRuleListsBeforeFailingSmokeLookup() async throws {
        let firstDefinition = Self.validRuleListDefinition(
            name: "SumiPreparedShardSmokeFirst-\(UUID().uuidString)",
            blockedHost: "prepared-shard-smoke-first.example"
        )
        let secondDefinition = Self.validRuleListDefinition(
            name: "SumiPreparedShardSmokeSecond-\(UUID().uuidString)",
            blockedHost: "prepared-shard-smoke-second.example"
        )
        let failingIdentifier = Self.storeIdentifier(for: secondDefinition)
        let compiler = SmokeLookupFailingContentRuleListCompiler(
            failingIdentifiers: [failingIdentifier]
        )
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            compiledRuleListCatalog: InMemoryCompiledRuleListCatalog()
        )

        do {
            _ = try await service.prepareRuleListUpdate(
                ruleLists: [firstDefinition, secondDefinition]
            )
            XCTFail("Expected prepared update smoke lookup to fail")
        } catch let error as SumiContentBlockingCompilationError {
            XCTAssertEqual(error.identifier, failingIdentifier)
        }

        XCTAssertEqual(
            Set(compiler.compiledIdentifiers),
            Set([
                Self.storeIdentifier(for: firstDefinition),
                failingIdentifier
            ])
        )
        XCTAssertEqual(compiler.compiledIdentifiers.count, 2)
    }

    func testContentBlockingUserScriptsUseNormalProviderPath() async throws {
        let marker = "window.__sumiContentBlockingProviderScript = true;"
        let provider = SumiNormalTabUserScripts(
            contentBlockingUserScripts: [TestContentBlockingProviderUserScript(source: marker)]
        )
        let service = SumiContentBlockingService(policy: .disabled)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            scriptsProvider: provider,
            contentBlockingService: service
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        await normalTabController.waitForContentBlockingAssetsInstalled()

        XCTAssertTrue(controller.userScripts.contains { $0.source.contains(marker) })
        XCTAssertTrue(controller.sumiNormalTabUserScriptsProvider === provider)
    }

    func testWebViewCoordinatorUsesFastInitialLoadWhenUserContentIsPreinstalled() throws {
        let source = try Self.source(named: "Sumi/Managers/WebViewCoordinator/WebViewCoordinator.swift")

        let fastPathRange = try XCTUnwrap(source.range(of: "controller.hasInstalledInitialUserContent"))
        let fastLoadRange = try XCTUnwrap(source.range(of: "performLoad()", range: fastPathRange.upperBound..<source.endIndex))
        let waitRange = try XCTUnwrap(source.range(of: "await controller.waitForInitialUserContentInstallation()", range: fastLoadRange.upperBound..<source.endIndex))
        let fallbackLoadRange = try XCTUnwrap(source.range(of: "performLoad()", range: waitRange.upperBound..<source.endIndex))

        XCTAssertLessThan(fastPathRange.lowerBound, fastLoadRange.lowerBound)
        XCTAssertLessThan(fastLoadRange.lowerBound, waitRange.lowerBound)
        XCTAssertLessThan(waitRange.lowerBound, fallbackLoadRange.lowerBound)
    }

    func testInitialNormalTabLoadUsesPreinstalledUserContentFastPath() throws {
        let tabRuntime = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let navigationState = try Self.source(named: "Sumi/Models/Tab/Tab+NavigationState.swift")

        let fastPathRange = try XCTUnwrap(tabRuntime.range(of: "controller.hasInstalledInitialUserContent"))
        let fastLoadRange = try XCTUnwrap(tabRuntime.range(of: "loadURL(url)", range: fastPathRange.upperBound..<tabRuntime.endIndex))
        let waitRange = try XCTUnwrap(tabRuntime.range(of: "await controller.waitForInitialUserContentInstallation()", range: fastLoadRange.upperBound..<tabRuntime.endIndex))
        let fallbackLoadRange = try XCTUnwrap(tabRuntime.range(of: "self.loadURL(self.url)", range: waitRange.upperBound..<tabRuntime.endIndex))

        XCTAssertLessThan(fastPathRange.lowerBound, fastLoadRange.lowerBound)
        XCTAssertLessThan(fastLoadRange.lowerBound, waitRange.lowerBound)
        XCTAssertLessThan(waitRange.lowerBound, fallbackLoadRange.lowerBound)
        XCTAssertFalse(tabRuntime.contains("if controller.contentBlockingAssetSummary.isInstalled {\n                    loadURL(url)"))
        XCTAssertFalse(navigationState.contains("guard !controller.contentBlockingAssetSummary.isInstalled else"))
    }

    func testNormalPageInterceptionIsNotRegisteredInSumiSources() throws {
        let source = try Self.sumiSourceCorpus()

        XCTAssertFalse(source.contains("setURLSchemeHandler("))
        XCTAssertFalse(source.contains("WKURLSchemeHandler"))
    }

    private static func validRuleListDefinition() -> SumiContentRuleListDefinition {
        validRuleListDefinition(
            name: "SumiTestRuleList-\(UUID().uuidString)",
            blockedHost: "blocked.example"
        )
    }

    private static func validRuleListDefinition(
        name: String,
        blockedHost: String
    ) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: name,
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*\(blockedHost.replacingOccurrences(of: ".", with: "\\\\."))/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    private static func storeIdentifier(
        for definition: SumiContentRuleListDefinition
    ) -> String {
        SumiContentBlockerRulesIdentifier(
            name: definition.name,
            tdsEtag: definition.contentHash,
            tempListId: nil,
            allowListId: nil,
            unprotectedSitesHash: nil
        ).stringValue
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func sumiSourceCorpus() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sumiURL = repoRoot.appendingPathComponent("Sumi", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: sumiURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var corpus = ""
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            corpus += try String(contentsOf: url, encoding: .utf8)
            corpus += "\n"
        }
        return corpus
    }

    private static func waitForAssetRuleListCount(
        on controller: SumiNormalTabUserContentControlling,
        where predicate: @escaping (Int) -> Bool
    ) async -> Int {
        let currentCount = controller.contentBlockingAssetSummary.globalRuleListCount
        if predicate(currentCount) {
            return currentCount
        }

        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = controller.contentBlockingAssetSummaryPublisher.sink { summary in
                let count = summary.globalRuleListCount
                guard predicate(count) else { return }
                continuation.resume(returning: count)
                cancellable?.cancel()
            }
        }
    }

    private func waitForCompilerFailure(
        _ compiler: CountingContentRuleListCompiler
    ) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if compiler.failureCount > 0 {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for invalid replacement rule compilation to fail")
    }

    private func waitForRemovedIdentifier(
        _ identifier: String,
        in compiler: CountingContentRuleListCompiler
    ) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if compiler.removedIdentifiers.contains(identifier) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for compiled rule list removal: \(identifier)")
    }

    private func makeWebView(userContentController: WKUserContentController) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        return WKWebView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
    }

    private func loadURL(
        _ url: URL,
        into webView: WKWebView
    ) async throws {
        let didFinish = expectation(description: "page loaded")
        let delegate = ContentBlockingNavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        await fulfillment(of: [didFinish], timeout: 5)
        webView.navigationDelegate = nil
    }
}

private final class LocalHTTPResourceServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "sumi.content-blocking.http-smoke")
    private let lock = NSLock()
    private var requests: [String] = []
    private var startContinuation: CheckedContinuation<Void, Error>?

    static func start() async throws -> LocalHTTPResourceServer {
        let server = try LocalHTTPResourceServer()
        try await server.start()
        return server
    }

    private init() throws {
        listener = try NWListener(
            using: .tcp,
            on: NWEndpoint.Port(rawValue: 0)!
        )
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    func pageURL(cacheBuster: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)/?cache=\(cacheBuster)")!
    }

    func stop() {
        listener.cancel()
    }

    func resetRequests() {
        lock.withLock {
            requests.removeAll(keepingCapacity: true)
        }
    }

    func waitForRequest(path: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasRequest(path: path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return hasRequest(path: path)
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishStart(.success(()))
                case .failed(let error):
                    self?.finishStart(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        let continuation = lock.withLock {
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func hasRequest(path: String) -> Bool {
        lock.withLock {
            requests.contains(path)
        }
    }

    private func recordRequest(path: String) {
        lock.withLock {
            requests.append(path)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulatedData: Data())
    }

    private func receiveRequest(
        on connection: NWConnection,
        accumulatedData: Data
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }
            let headerTerminator = Data("\r\n\r\n".utf8)
            guard requestData.range(of: headerTerminator) != nil || isComplete || error != nil else {
                self.receiveRequest(on: connection, accumulatedData: requestData)
                return
            }
            respond(to: requestData, on: connection)
        }
    }

    private func respond(
        to requestData: Data,
        on connection: NWConnection
    ) {
        let requestText = String(decoding: requestData, as: UTF8.self)
        let requestTarget = requestText
            .split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = requestTarget.split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestTarget
        recordRequest(path: path)

        let cacheToken = requestTarget.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? "none"
        let body: Data
        let contentType: String
        if path == "/" {
            body = Data("""
            <!doctype html>
            <html>
              <body>
                <p>content blocking smoke</p>
                <img src="/blocked-resource.png?\(cacheToken)" alt="blocked resource">
              </body>
            </html>
            """.utf8)
            contentType = "text/html; charset=utf-8"
        } else {
            body = Data("ok".utf8)
            contentType = "image/png"
        }
        let header = Data([
            "HTTP/1.1 200 OK",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n").utf8)
        connection.send(content: header + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private final class ContentBlockingNavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        onFinish()
    }
}

@MainActor
private final class CountingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private(set) var lookupCount = 0
    private(set) var canLookupCount = 0
    private(set) var compileCount = 0
    private(set) var failureCount = 0
    private(set) var removedIdentifiers: [String] = []

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        lookupCount += 1
        return await wrapped.lookUpContentRuleList(forIdentifier: identifier)
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        canLookupCount += 1
        return await wrapped.canLookUpContentRuleList(forIdentifier: identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compileCount += 1
        do {
            return try await wrapped.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: encodedContentRuleList
            )
        } catch {
            failureCount += 1
            throw error
        }
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        await wrapped.availableContentRuleListIdentifiers()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        removedIdentifiers.append(identifier)
        try await wrapped.removeContentRuleList(forIdentifier: identifier)
    }
}

@MainActor
private final class SmokeLookupFailingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private let failingIdentifiers: Set<String>
    private(set) var compiledIdentifiers: [String] = []

    init(failingIdentifiers: Set<String>) {
        self.failingIdentifiers = failingIdentifiers
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        await wrapped.lookUpContentRuleList(forIdentifier: identifier)
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        guard !failingIdentifiers.contains(identifier) else { return false }
        return await wrapped.canLookUpContentRuleList(forIdentifier: identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compiledIdentifiers.append(identifier)
        return try await wrapped.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: encodedContentRuleList
        )
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        await wrapped.availableContentRuleListIdentifiers()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        try await wrapped.removeContentRuleList(forIdentifier: identifier)
    }
}

@MainActor
private final class InMemoryCompiledRuleListCatalog: SumiCompiledContentRuleListCataloging {
    private var identifiersByName: [String: Set<String>] = [:]

    func cachedIdentifiersToForget(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        orphanedIdentifiersWithoutMutating(
            replacing: previousRules,
            with: activeRules
        )
    }

    func orphanedIdentifiers(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let orphanedIdentifiers = orphanedIdentifiersWithoutMutating(
            replacing: previousRules,
            with: activeRules
        )
        let activeIdentifiersByName = Self.identifiersByName(for: activeRules)
        let namesToSweep = Set(identifiersByName.keys).union(activeIdentifiersByName.keys)
        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            identifiersByName[name] = activeIdentifiers.isEmpty ? nil : activeIdentifiers
        }
        return Array(orphanedIdentifiers)
    }

    func forgetIdentifiers(_ identifiers: [String]) {
        let identifiersToForget = Set(identifiers)
        for name in Array(identifiersByName.keys) {
            identifiersByName[name]?.subtract(identifiersToForget)
            if identifiersByName[name]?.isEmpty == true {
                identifiersByName.removeValue(forKey: name)
            }
        }
    }

    private func orphanedIdentifiersWithoutMutating(
        replacing previousRules: [SumiContentBlockerRules],
        with activeRules: [SumiContentBlockerRules]
    ) -> [String] {
        let previousIdentifiersByName = Self.identifiersByName(for: previousRules)
        let activeIdentifiersByName = Self.identifiersByName(for: activeRules)
        let namesToSweep = Set(previousIdentifiersByName.keys).union(activeIdentifiersByName.keys)
        var orphanedIdentifiers = Set<String>()

        for name in namesToSweep {
            let activeIdentifiers = activeIdentifiersByName[name] ?? []
            var knownIdentifiers = identifiersByName[name] ?? []
            knownIdentifiers.formUnion(previousIdentifiersByName[name] ?? [])
            orphanedIdentifiers.formUnion(knownIdentifiers.subtracting(activeIdentifiers))
        }

        return Array(orphanedIdentifiers)
    }

    private static func identifiersByName(
        for rules: [SumiContentBlockerRules]
    ) -> [String: Set<String>] {
        rules.reduce(into: [:]) { result, rules in
            result[rules.identifier.name, default: []].insert(rules.identifier.stringValue)
        }
    }
}

@MainActor
private final class StaticContentRuleListSetProvider: SumiContentRuleListSetProviding {
    let changesPublisher = PassthroughSubject<Void, Never>().eraseToAnyPublisher()
    let hasProfileSpecificRuleLists = false

    private let ruleListSet: SumiContentRuleListSet

    init(ruleListSet: SumiContentRuleListSet) {
        self.ruleListSet = ruleListSet
    }

    func ruleListSet(profileId: UUID?) throws -> SumiContentRuleListSet {
        ruleListSet
    }
}

private final class TestContentBlockingProviderUserScript: NSObject, SumiUserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String] = []

    init(source: String) {
        self.source = source
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}
