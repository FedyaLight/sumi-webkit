import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockUpdatePipelineTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testDownloaderPersistsConditionalRequestHeadersFromMetadata() async throws {
        let requestRecorder = RequestRecorder()
        let downloader = AdblockFilterListDownloader { request in
            await requestRecorder.record(request)
            return (
                Data("||ads.example^".utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["ETag": "\"next\"", "Last-Modified": "Tue, 14 May 2024 12:00:00 GMT"]
                )!
            )
        }

        _ = try await downloader.download(
            descriptor: Self.descriptor("easylist"),
            previousMetadata: AdblockFilterListHTTPMetadata(
                eTag: "\"old\"",
                lastModified: "Mon, 13 May 2024 12:00:00 GMT"
            )
        )

        let observedRequest = await requestRecorder.recordedRequest()
        XCTAssertEqual(observedRequest?.value(forHTTPHeaderField: "If-None-Match"), "\"old\"")
        XCTAssertEqual(observedRequest?.value(forHTTPHeaderField: "If-Modified-Since"), "Mon, 13 May 2024 12:00:00 GMT")
    }

    func testDefaultSelectionIsConservativeAndRegionalListsRemainOptional() {
        let registry = AdblockFilterListRegistry()
        let selected = registry.selectedDescriptors(
            selection: .defaultSelection,
            locale: Locale(identifier: "en_US")
        )
        let regionalLists = registry.descriptors.filter { $0.category == .regional }

        XCTAssertEqual(selected.map(\.id), ["easylist"])
        XCTAssertGreaterThan(regionalLists.count, 12)
        XCTAssertTrue(regionalLists.allSatisfy { !$0.defaultEnabled })
        XCTAssertTrue(registry.descriptors.contains { $0.id == "ru-adlist" })
        XCTAssertTrue(registry.descriptors.contains { $0.category == .privacyOverlap && !$0.defaultEnabled })
    }

    func testNativeProfilesRepresentCurrentLightBalancedHighAndOraLikeSeparately() {
        let registry = AdblockFilterListRegistry()
        let profiles = Dictionary(uniqueKeysWithValues: registry.nativeProfiles.map { ($0.id, $0) })
        let current = profiles[.currentDefault]
        let light = profiles[.lightNative]
        let balanced = profiles[.balancedNative]
        let high = profiles[.highBlockingNative]
        let oraLike = profiles[.oraLikeNative]

        XCTAssertEqual(current?.listIdentifiers, ["easylist"])
        XCTAssertEqual(light?.listIdentifiers, ["easylist"])
        XCTAssertEqual(balanced?.listIdentifiers, ["adguard-base", "adguard-mobile-ads"])
        XCTAssertEqual(high?.listIdentifiers, ["adguard-base", "adguard-mobile-ads", "adguard-annoyances"])
        XCTAssertEqual(
            oraLike?.listIdentifiers,
            [
                "adguard-base",
                "adguard-mobile-ads",
                "adguard-tracking-protection",
                "adguard-url-tracking",
                "adguard-annoyances",
            ]
        )
        XCTAssertEqual(registry.defaultSelectionIdentifiers, ["easylist"])
        XCTAssertEqual(Set(registry.nativeProfiles.map(\.id)).count, 5)
        XCTAssertFalse(balanced?.isRecommended == true)
        XCTAssertTrue(light?.isDeveloperOnly == true)
        XCTAssertTrue(balanced?.isDeveloperOnly == true)
        XCTAssertTrue(high?.isExperimental == true)
        XCTAssertTrue(high?.isDeveloperOnly == true)
        XCTAssertTrue(oraLike?.isExperimental == true)
        XCTAssertTrue(oraLike?.isDeveloperOnly == true)
        XCTAssertEqual(registry.normalUserSelectableNativeProfiles.map(\.id), [.currentDefault])
        XCTAssertTrue(oraLike?.listIdentifiers.allSatisfy { id in
            registry.descriptors.contains { $0.id == id && !$0.defaultEnabled }
        } == true)
    }

    func testNativeCompilerCatalogKeepsSafariConverterAsExternalHarnessOnly() {
        let registry = AdblockFilterListRegistry()
        let compilers = Dictionary(uniqueKeysWithValues: registry.nativeCompilerDescriptors.map { ($0.id, $0) })

        XCTAssertEqual(compilers[.adblockRust]?.integrationStatus, .production)
        XCTAssertEqual(compilers[.adGuardSafariExperimental]?.integrationStatus, .externalHarnessOnly)
        XCTAssertTrue(compilers[.adGuardSafariExperimental]?.isExperimental == true)
    }

    func testDefaultSelectionUsesProfileBaselineAndOptionalRegionalList() {
        let registry = AdblockFilterListRegistry()

        let balanced = registry.selectedDescriptors(
            selection: .defaultSelection,
            profileKind: .balancedNative,
            locale: Locale(identifier: "ru_RU")
        )
        let oraLike = registry.selectedDescriptors(
            selection: .defaultSelection,
            profileKind: .oraLikeNative,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertEqual(balanced.map(\.id), ["adguard-base", "adguard-mobile-ads", "ru-adlist"])
        XCTAssertEqual(
            oraLike.map(\.id),
            [
                "adguard-annoyances",
                "adguard-base",
                "adguard-mobile-ads",
                "adguard-tracking-protection",
                "adguard-url-tracking",
            ]
        )
    }

    func testRussianLocaleRecommendsRUAdListWithoutEnablingAllRegionalLists() {
        let registry = AdblockFilterListRegistry()
        let selected = registry.selectedDescriptors(
            selection: .defaultSelection,
            locale: Locale(identifier: "ru_RU")
        )

        XCTAssertTrue(selected.map(\.id).contains("ru-adlist"))
        XCTAssertLessThan(selected.filter { $0.category == .regional }.count, registry.descriptors.filter { $0.category == .regional }.count)
    }

    func testMutuallyExclusiveEasyListVariantsResolveToNormalList() {
        let registry = AdblockFilterListRegistry()
        let validation = registry.validatedSelection(
            SumiAdblockFilterListSelection(identifiers: ["easylist", "easylist-without-element-hiding"]),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(validation.resolvedIdentifiers, ["easylist"])
        XCTAssertEqual(validation.droppedConflictingIdentifiers, ["easylist-without-element-hiding"])
    }

    func testExplicitEasyListNoElementHidingVariantCanBeSelectedAlone() {
        let registry = AdblockFilterListRegistry()
        let validation = registry.validatedSelection(
            SumiAdblockFilterListSelection(identifiers: ["easylist-without-element-hiding"]),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(validation.resolvedIdentifiers, ["easylist-without-element-hiding"])
        XCTAssertTrue(validation.droppedConflictingIdentifiers.isEmpty)
    }

    func testCoordinatorDownloadsOnlySelectedListsAndWritesManifest() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let downloader = FakeAdblockDownloader(results: [
            "easylist": .downloaded(Data("||ads.example^".utf8), Self.response(for: "easylist", eTag: "\"one\"")),
        ])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            registry: AdblockFilterListRegistry(descriptors: [
                Self.descriptor("easylist", defaultEnabled: true),
                Self.descriptor("regional-de", defaultEnabled: false),
            ]),
            selection: SumiAdblockFilterListSelection(identifiers: ["easylist"]),
            downloader: downloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        )

        let optionalManifest = try await coordinator.updateIfEnabled(reason: "manual")
        let manifest = try XCTUnwrap(optionalManifest)
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        let activeGenerationId = try await manifestStore.activeManifest()?.activeGenerationId

        XCTAssertEqual(requestedIdentifiers, ["easylist"])
        XCTAssertEqual(compileCount, 1)
        XCTAssertEqual(manifest.schemaVersion, 5)
        XCTAssertEqual(manifest.selectedFilterLists.map(\.id), ["easylist"])
        XCTAssertEqual(manifest.selectedFilterLists.map(\.contentHash), [Self.sha256Hex(Data("||ads.example^".utf8))])
        XCTAssertEqual(manifest.nativeProfile, .currentDefault)
        XCTAssertEqual(manifest.nativeCompiler?.name, "fake-native")
        XCTAssertEqual(manifest.nativeCompilerSourceLists?.map(\.id), ["easylist"])
        XCTAssertEqual(manifest.networkShards.count, 1)
        XCTAssertEqual(manifest.nativeCSSShards.count, 1)
        XCTAssertEqual(manifest.nativeCompilationSummary?.convertedNetworkRuleCount, 1)
        XCTAssertEqual(manifest.nativeCompilationSummary?.convertedNativeCosmeticRuleCount, 1)
        XCTAssertEqual(manifest.nativeCompilationSummary?.ruleCap.wasHit, false)
        XCTAssertTrue(manifest.webKitRuleListIdentifiers.allSatisfy(AdblockUpdateCoordinator.isAdblockGeneratedWebKitIdentifier))
        XCTAssertEqual(activeGenerationId, manifest.activeGenerationId)
        XCTAssertEqual(publisher.publishedManifests.count, 1)
        XCTAssertNil(manifest.enhancedRuntimeBundle)
        XCTAssertTrue(manifest.compilerDiagnosticsSummary.contains("nativeCSSConverted=1"))
        XCTAssertTrue(manifest.compilerDiagnosticsSummary.contains("scriptletOrProceduralIgnored=0"))
    }

    func testLegacyManifestDecodesWithoutNativeProfileOrCompilationSummary() throws {
        let legacyJSON = """
        {
          "schemaVersion": 3,
          "activeGenerationId": "legacy",
          "createdDate": 0,
          "selectedFilterLists": [
            { "id": "easylist", "displayName": "EasyList", "contentHash": "hash" }
          ],
          "webKitRuleListIdentifiers": ["sumi.adblock.network.legacy"],
          "groupedOutputs": [
            {
              "kind": "network",
              "webKitIdentifier": "sumi.adblock.network.legacy",
              "contentHash": "hash",
              "convertedRuleCount": 1
            }
          ],
          "compilerDiagnosticsSummary": "legacy",
          "lastSuccessfulUpdateDate": 0
        }
        """

        let manifest = try JSONDecoder().decode(
            AdblockCompiledGenerationManifest.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(manifest.schemaVersion, 3)
        XCTAssertNil(manifest.nativeProfile)
        XCTAssertNil(manifest.nativeCompilationSummary)
        XCTAssertNil(manifest.nativeCompiler)
    }

    func testLegacyManifestSingleGroupsMigrateIntoSingleShardRepresentation() throws {
        let legacyJSON = """
        {
          "schemaVersion": 4,
          "activeGenerationId": "legacy-generation",
          "createdDate": 0,
          "selectedFilterLists": [
            { "id": "easylist", "displayName": "EasyList", "contentHash": "hash" }
          ],
          "webKitRuleListIdentifiers": [
            "sumi.adblock.network.legacy",
            "sumi.adblock.nativeCSS.legacy"
          ],
          "groupedOutputs": [
            {
              "kind": "network",
              "webKitIdentifier": "sumi.adblock.network.legacy",
              "contentHash": "network-hash",
              "convertedRuleCount": 4
            },
            {
              "kind": "nativeCosmeticCSS",
              "webKitIdentifier": "sumi.adblock.nativeCSS.legacy",
              "contentHash": "css-hash",
              "convertedRuleCount": 2
            }
          ],
          "compilerDiagnosticsSummary": "legacy",
          "lastSuccessfulUpdateDate": 0
        }
        """

        let manifest = try JSONDecoder().decode(
            AdblockCompiledGenerationManifest.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(manifest.networkShards.count, 1)
        XCTAssertEqual(manifest.nativeCSSShards.count, 1)
        XCTAssertEqual(manifest.networkShards[0].approximateRuleCount, 4)
        XCTAssertEqual(manifest.nativeCSSShards[0].approximateRuleCount, 2)
        XCTAssertEqual(manifest.networkShards[0].generationId, "legacy-generation")
    }

    func testCoordinatorDoesNotDownloadDroppedConflictingVariant() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let downloader = FakeAdblockDownloader(results: [
            "easylist": .downloaded(Data("||ads.example^".utf8), Self.response(for: "easylist")),
            "easylist-without-element-hiding": .downloaded(Data("||variant.example^".utf8), Self.response(for: "easylist-without-element-hiding")),
        ])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            registry: AdblockFilterListRegistry(),
            selection: SumiAdblockFilterListSelection(identifiers: ["easylist", "easylist-without-element-hiding"]),
            downloader: downloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        )

        _ = try await coordinator.updateIfEnabled(reason: "manual")

        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        XCTAssertEqual(requestedIdentifiers, ["easylist"])
    }

    func testNotModifiedReusesPreviousRawContent() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let firstDownloader = FakeAdblockDownloader(results: [
            "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist", eTag: "\"one\"")),
        ])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        _ = try await Self.coordinator(
            downloader: firstDownloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        ).updateIfEnabled(reason: "manual")

        let secondDownloader = FakeAdblockDownloader(results: [
            "easylist": .notModified(Self.response(for: "easylist", statusCode: 304)),
        ])
        _ = try await Self.coordinator(
            downloader: secondDownloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        ).updateIfEnabled(reason: "manual")

        let inputs = await compiler.inputs
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs.last?.filterTexts.first, "||first.example^")
    }

    func testDisabledCoordinatorIsInert() async throws {
        let downloader = FakeAdblockDownloader(results: [:])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            isEnabled: false,
            downloader: downloader,
            manifestStore: AdblockUpdateManifestStore(rootDirectory: temporaryDirectory()),
            compiler: compiler,
            publisher: publisher
        )

        let manifest = try await coordinator.updateIfEnabled(reason: "manual")

        XCTAssertNil(manifest)
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        XCTAssertTrue(requestedIdentifiers.isEmpty)
        XCTAssertEqual(compileCount, 0)
        XCTAssertTrue(publisher.publishedManifests.isEmpty)
    }

    func testDownloadAndCompileFailuresKeepPreviousManifest() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let publisher = FakeAdblockPublisher()
        let optionalFirstManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let firstManifest = try XCTUnwrap(optionalFirstManifest)

        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .failure(AdblockUpdateDiagnostics(summary: "offline")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(),
                publisher: publisher
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected download failure")
        } catch {}

        let activeAfterDownloadFailure = try await manifestStore.activeManifest()?.activeGenerationId
        XCTAssertEqual(activeAfterDownloadFailure, firstManifest.activeGenerationId)

        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .downloaded(Data("||second.example^".utf8), Self.response(for: "easylist")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(error: AdblockUpdateDiagnostics(summary: "compiler failed")),
                publisher: publisher
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected compile failure")
        } catch {}

        let activeAfterCompileFailure = try await manifestStore.activeManifest()?.activeGenerationId
        XCTAssertEqual(activeAfterCompileFailure, firstManifest.activeGenerationId)
    }

    func testShardPublishFailurePreventsManifestSwitchAndPreservesPreviousGeneration() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let optionalFirstManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(networkShardCount: 2, nativeCSSShardCount: 2),
            publisher: FakeAdblockPublisher()
        ).updateIfEnabled(reason: "manual")
        let firstManifest = try XCTUnwrap(optionalFirstManifest)

        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .downloaded(Data("||second.example^".utf8), Self.response(for: "easylist")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(networkShardCount: 3, nativeCSSShardCount: 2),
                publisher: FakeAdblockPublisher(
                    error: SumiContentBlockingCompilationError.missingCompiledRuleList(
                        "sumi.adblock.network.failed.0002.hash"
                    )
                )
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected shard publish failure")
        } catch let diagnostics as AdblockUpdateDiagnostics {
            XCTAssertEqual(diagnostics.failedShardIdentifier, "sumi.adblock.network.failed.0002.hash")
        }

        let activeAfterFailure = try await manifestStore.activeManifest()
        XCTAssertEqual(activeAfterFailure?.activeGenerationId, firstManifest.activeGenerationId)
        XCTAssertEqual(activeAfterFailure?.webKitRuleListIdentifiers, firstManifest.webKitRuleListIdentifiers)
    }

    func testSelectionChangeCreatesDifferentGenerationAndPreservesPreviousUntilSwitch() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let publisher = FakeAdblockPublisher()
        let optionalFirstManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let firstManifest = try XCTUnwrap(optionalFirstManifest)

        let optionalSecondManifest = try await Self.coordinator(
            registry: AdblockFilterListRegistry(descriptors: [
                Self.descriptor("easylist", defaultEnabled: true),
                Self.descriptor("regional-de", defaultEnabled: false),
            ]),
            selection: SumiAdblockFilterListSelection(identifiers: ["easylist", "regional-de"]),
            downloader: FakeAdblockDownloader(results: [
                "easylist": .notModified(Self.response(for: "easylist", statusCode: 304)),
                "regional-de": .downloaded(Data("||second.example^".utf8), Self.response(for: "regional-de")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let secondManifest = try XCTUnwrap(optionalSecondManifest)
        let archivedFirstManifest = try await manifestStore.archivedManifest(generationId: firstManifest.activeGenerationId)

        XCTAssertNotEqual(firstManifest.activeGenerationId, secondManifest.activeGenerationId)
        XCTAssertEqual(secondManifest.previousGenerationId, firstManifest.activeGenerationId)
        XCTAssertNotNil(archivedFirstManifest)
        XCTAssertEqual(secondManifest.selectedFilterLists.map(\.id), ["easylist", "regional-de"])
    }

    func testProfileChangeCreatesDifferentGenerationEvenWhenBaselineListsMatch() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let publisher = FakeAdblockPublisher()
        let optionalFirstManifest = try await Self.coordinator(
            profile: .currentDefault,
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let firstManifest = try XCTUnwrap(optionalFirstManifest)

        let optionalSecondManifest = try await Self.coordinator(
            profile: .lightNative,
            downloader: FakeAdblockDownloader(results: [
                "easylist": .notModified(Self.response(for: "easylist", statusCode: 304)),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher
        ).updateIfEnabled(reason: "manual")
        let secondManifest = try XCTUnwrap(optionalSecondManifest)

        XCTAssertNotEqual(firstManifest.activeGenerationId, secondManifest.activeGenerationId)
        XCTAssertEqual(firstManifest.nativeProfile, .currentDefault)
        XCTAssertEqual(secondManifest.nativeProfile, .lightNative)
    }

    func testManualUpdateUsesSelectedNativeProfileBaselineLists() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            registry: AdblockFilterListRegistry(descriptors: [
                Self.descriptor("adguard-base", defaultEnabled: false),
                Self.descriptor("adguard-mobile-ads", defaultEnabled: false),
            ]),
            selection: .defaultSelection,
            profile: .balancedNative,
            downloader: FakeAdblockDownloader(results: [
                "adguard-base": .downloaded(Data("||base.example^".utf8), Self.response(for: "adguard-base")),
                "adguard-mobile-ads": .downloaded(Data("||mobile.example^".utf8), Self.response(for: "adguard-mobile-ads")),
            ]),
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher
        )

        let updateManifest = try await coordinator.updateIfEnabled(reason: "manual")
        let manifest = try XCTUnwrap(updateManifest)
        let inputs = await compiler.inputs

        XCTAssertEqual(manifest.nativeProfile, .balancedNative)
        XCTAssertEqual(manifest.selectedFilterLists.map(\.id), ["adguard-base", "adguard-mobile-ads"])
        XCTAssertEqual(inputs.last?.nativeProfile, .balancedNative)
        XCTAssertEqual(inputs.last?.sourceLists.map(\.id), ["adguard-base", "adguard-mobile-ads"])
    }

    func testManifestRecordsAllShardIdentifiersCountsAndSizes() async throws {
        let optionalManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: AdblockUpdateManifestStore(rootDirectory: temporaryDirectory()),
            compiler: FakeAdblockCompiler(networkShardCount: 3, nativeCSSShardCount: 2),
            publisher: FakeAdblockPublisher()
        ).updateIfEnabled(reason: "manual")
        let manifest = try XCTUnwrap(optionalManifest)

        XCTAssertEqual(manifest.networkShards.count, 3)
        XCTAssertEqual(manifest.nativeCSSShards.count, 2)
        XCTAssertEqual(manifest.webKitRuleListIdentifiers.count, 5)
        XCTAssertEqual(manifest.networkShards.map(\.approximateRuleCount), [1, 1, 1])
        XCTAssertEqual(manifest.nativeCSSShards.map(\.jsonByteCount), [2, 2])
        XCTAssertTrue(manifest.webKitRuleListIdentifiers.allSatisfy { $0.contains(manifest.activeGenerationId) })
    }

    func testManifestProviderAttachesAllShardsSelectedByCosmeticMode() throws {
        let manifest = Self.manifest(
            generationId: "generation",
            previousGenerationId: nil,
            listIds: ["easylist"],
            identifiers: [
                "sumi.adblock.network.generation.0001.hash-a",
                "sumi.adblock.network.generation.0002.hash-b",
                "sumi.adblock.nativeCSS.generation.0001.hash-c",
                "sumi.adblock.nativeCSS.generation.0002.hash-d",
            ]
        )

        let definitions = Self.definitions(for: manifest)
        let offProvider = AdblockManifestRuleListProvider(
            manifest: manifest,
            cosmeticMode: .off,
            compiledDefinitions: definitions
        )
        let nativeCSSProvider = AdblockManifestRuleListProvider(
            manifest: manifest,
            cosmeticMode: .nativeCSS,
            compiledDefinitions: definitions
        )
        let enhancedProvider = AdblockManifestRuleListProvider(
            manifest: manifest,
            cosmeticMode: .enhancedRuntime,
            compiledDefinitions: definitions
        )

        XCTAssertEqual(
            try offProvider.ruleListSet(profileId: nil).allDefinitions.map(\.name).sorted(),
            [
                "sumi.adblock.network.generation.0001.hash-a",
                "sumi.adblock.network.generation.0002.hash-b",
            ]
        )
        XCTAssertEqual(try nativeCSSProvider.ruleListSet(profileId: nil).allDefinitions.count, 4)
        XCTAssertEqual(try enhancedProvider.ruleListSet(profileId: nil).allDefinitions.count, 4)
    }

    func testManifestProviderFailsInsteadOfAttachingEmptyShardDefinitions() throws {
        let manifest = Self.manifest(
            generationId: "generation",
            previousGenerationId: nil,
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.generation.0001.hash-a"]
        )
        let provider = AdblockManifestRuleListProvider(manifest: manifest, cosmeticMode: .off)

        XCTAssertThrowsError(try provider.ruleListSet(profileId: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Missing compiled Adblock shard definition"))
        }
    }

    func testRuleCapDiagnosticsArePersistedForLargeProfileOutput() async throws {
        let optionalManifest = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: AdblockUpdateManifestStore(rootDirectory: temporaryDirectory()),
            compiler: FakeAdblockCompiler(
                ruleCap: NativeContentBlockingRuleCapDiagnostics(
                    configuredRuleLimit: 150_000,
                    wasHit: true,
                    discardedRuleCount: 42_000,
                    sourcePressure: [
                        NativeContentBlockingRuleCapDiagnostics.SourcePressure(
                            listIdentifier: "easylist",
                            approximateRuleCount: 80_000,
                            inputByteCount: 1_000_000
                        ),
                    ]
                )
            ),
            publisher: FakeAdblockPublisher()
        ).updateIfEnabled(reason: "manual")
        let manifest = try XCTUnwrap(optionalManifest)

        XCTAssertEqual(manifest.nativeCompilationSummary?.ruleCap.configuredRuleLimit, 150_000)
        XCTAssertEqual(manifest.nativeCompilationSummary?.ruleCap.wasHit, true)
        XCTAssertEqual(manifest.nativeCompilationSummary?.ruleCap.discardedRuleCount, 42_000)
        XCTAssertTrue(manifest.compilerDiagnosticsSummary.contains("ruleCapHit=true"))
        XCTAssertTrue(manifest.compilerDiagnosticsSummary.contains("discarded=42000"))
    }

    func testCleanupPreservesActiveAndPreviousAndDeletesOlderGenerations() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let active = Self.manifest(
            generationId: "20240515T000002Z-activehash",
            previousGenerationId: "20240515T000001Z-prevhash",
            listIds: ["easylist"],
            identifiers: [
                "sumi.adblock.network.activehash.0001",
                "sumi.adblock.network.activehash.0002",
                "sumi.adblock.nativeCSS.activehash.0001",
            ]
        )
        let previous = Self.manifest(
            generationId: "20240515T000001Z-prevhash",
            previousGenerationId: "20240515T000000Z-oldhash",
            listIds: ["regional-de"],
            identifiers: [
                "sumi.adblock.network.prevhash.0001",
                "sumi.adblock.nativeCSS.prevhash.0001",
                "sumi.adblock.nativeCSS.prevhash.0002",
            ]
        )
        let old = Self.manifest(
            generationId: "20240515T000000Z-oldhash",
            previousGenerationId: nil,
            listIds: ["obsolete"],
            identifiers: ["sumi.adblock.network.oldhash", "sumi.adblock.nativeCSS.oldhash"]
        )
        try await archive(old, in: manifestStore)
        try await archive(previous, in: manifestStore)
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        try writeRawList("easylist", root: root)
        try writeRawList("regional-de", root: root)
        try writeRawList("obsolete", root: root)
        try createStagingDirectory(root: root, name: "interrupted")
        let ruleStore = FakeContentRuleListStore(identifiers: [
            "sumi.adblock.network.activehash.0001",
            "sumi.adblock.network.activehash.0002",
            "sumi.adblock.nativeCSS.activehash.0001",
            "sumi.adblock.network.prevhash.0001",
            "sumi.adblock.nativeCSS.prevhash.0001",
            "sumi.adblock.nativeCSS.prevhash.0002",
            "sumi.adblock.network.oldhash",
            "sumi.trackingProtection.tds",
            "third.party.rule.list",
        ])
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )

        let report = await cleaner.cleanupAfterSuccessfulUpdate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000002Z-activehash").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000001Z-prevhash").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Generated/20240515T000000Z-oldhash").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/easylist.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/regional-de.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("RawLists/obsolete.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Staging/interrupted").path))
        let removedIdentifiers = ruleStore.removedIdentifiers()
        let remainingIdentifiers = ruleStore.identifiers()
        XCTAssertEqual(removedIdentifiers, ["sumi.adblock.network.oldhash"])
        XCTAssertTrue(remainingIdentifiers.contains("sumi.trackingProtection.tds"))
        XCTAssertTrue(remainingIdentifiers.contains("third.party.rule.list"))
        XCTAssertTrue(report.diagnostics.isEmpty)
    }

    func testCleanupToleratesMissingFilesAndReportsWebKitRemoveFailures() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let active = Self.manifest(
            generationId: "activehash",
            previousGenerationId: nil,
            listIds: ["easylist"],
            identifiers: ["sumi.adblock.network.activehash"]
        )
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        let ruleStore = FakeContentRuleListStore(
            identifiers: ["sumi.adblock.network.oldhash"],
            removeFailures: ["sumi.adblock.network.oldhash"]
        )
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )

        let report = await cleaner.cleanupAfterSuccessfulUpdate()
        let activeAfterCleanup = try await manifestStore.activeManifest()

        XCTAssertEqual(activeAfterCleanup?.activeGenerationId, active.activeGenerationId)
        XCTAssertTrue(report.diagnostics.contains { $0.contains("Failed to remove WebKit rule list") })
    }

    func testCleanupRunsOnlyAfterSuccessfulManifestSwitch() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let ruleStore = FakeContentRuleListStore(identifiers: ["sumi.adblock.network.oldhash"])
        let cleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: ruleStore
        )
        let publisher = FakeAdblockPublisher()
        _ = try await Self.coordinator(
            downloader: FakeAdblockDownloader(results: [
                "easylist": .downloaded(Data("||first.example^".utf8), Self.response(for: "easylist")),
            ]),
            manifestStore: manifestStore,
            compiler: FakeAdblockCompiler(),
            publisher: publisher,
            garbageCollector: cleaner
        ).updateIfEnabled(reason: "manual")

        XCTAssertEqual(ruleStore.removedIdentifiers(), ["sumi.adblock.network.oldhash"])

        let failingRuleStore = FakeContentRuleListStore(identifiers: ["sumi.adblock.network.afterfailure"])
        let failingCleaner = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: failingRuleStore
        )
        do {
            _ = try await Self.coordinator(
                downloader: FakeAdblockDownloader(results: [
                    "easylist": .failure(AdblockUpdateDiagnostics(summary: "offline")),
                ]),
                manifestStore: manifestStore,
                compiler: FakeAdblockCompiler(),
                publisher: publisher,
                garbageCollector: failingCleaner
            ).updateIfEnabled(reason: "manual")
            XCTFail("Expected update failure")
        } catch {}

        XCTAssertTrue(failingRuleStore.removedIdentifiers().isEmpty)
    }

    func testRollbackSwitchesActiveGenerationBackToPreviousWithoutDownloadOrCompile() async throws {
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let previous = Self.manifest(
            generationId: "prevhash",
            previousGenerationId: nil,
            listIds: ["easylist"],
            nativeProfile: .lightNative,
            identifiers: [
                "sumi.adblock.network.prevhash.0001",
                "sumi.adblock.network.prevhash.0002",
                "sumi.adblock.nativeCSS.prevhash.0001",
            ]
        )
        let active = Self.manifest(
            generationId: "activehash",
            previousGenerationId: "prevhash",
            listIds: ["easylist"],
            nativeProfile: .balancedNative,
            identifiers: [
                "sumi.adblock.network.activehash.0001",
                "sumi.adblock.nativeCSS.activehash.0001",
            ]
        )
        try await archive(previous, in: manifestStore)
        try await archive(active, in: manifestStore)
        try await manifestStore.replaceActiveManifest(active)
        let ruleStore = FakeContentRuleListStore(identifiers: [
            "sumi.adblock.network.prevhash.0001",
            "sumi.adblock.network.prevhash.0002",
            "sumi.adblock.nativeCSS.prevhash.0001",
        ])
        let downloader = FakeAdblockDownloader(results: [:])
        let compiler = FakeAdblockCompiler()
        let publisher = FakeAdblockPublisher()
        let coordinator = Self.coordinator(
            downloader: downloader,
            manifestStore: manifestStore,
            compiler: compiler,
            publisher: publisher,
            contentRuleListStore: ruleStore
        )

        let report = await coordinator.rollbackIfActiveGenerationFailsSmokeCheck()

        XCTAssertTrue(report.rolledBack)
        let activeAfterRollback = try await manifestStore.activeManifest()?.activeGenerationId
        let requestedIdentifiers = await downloader.allRequestedIdentifiers()
        let compileCount = await compiler.currentCompileCount()
        let rolledBackManifest = try await manifestStore.activeManifest()
        XCTAssertEqual(activeAfterRollback, "prevhash")
        XCTAssertEqual(rolledBackManifest?.nativeProfile, .lightNative)
        XCTAssertEqual(publisher.publishedManifests.map(\.activeGenerationId), ["prevhash"])
        XCTAssertEqual(publisher.publishedManifests.map(\.nativeProfile), [.lightNative])
        XCTAssertTrue(requestedIdentifiers.isEmpty)
        XCTAssertEqual(compileCount, 0)
    }

    private static func coordinator(
        registry: AdblockFilterListRegistry = AdblockFilterListRegistry(descriptors: [descriptor("easylist", defaultEnabled: true)]),
        selection: SumiAdblockFilterListSelection = SumiAdblockFilterListSelection(identifiers: ["easylist"]),
        profile: AdblockFilterListProfileKind = .currentDefault,
        isEnabled: Bool = true,
        downloader: FakeAdblockDownloader,
        manifestStore: AdblockUpdateManifestStore,
        compiler: FakeAdblockCompiler,
        publisher: FakeAdblockPublisher,
        contentRuleListStore: (any SumiContentRuleListCompiling)? = nil,
        garbageCollector: AdblockGenerationGarbageCollector? = nil
    ) -> AdblockUpdateCoordinator {
        AdblockUpdateCoordinator(
            registry: registry,
            selection: { selection },
            nativeProfileSelection: { profile },
            isAdblockEnabled: { isEnabled },
            downloader: downloader,
            manifestStore: manifestStore,
            nativeCompiler: compiler,
            enhancedCompiler: compiler,
            publisher: publisher,
            contentRuleListStore: contentRuleListStore,
            garbageCollector: garbageCollector,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private static func manifest(
        generationId: String,
        previousGenerationId: String?,
        listIds: [String],
        nativeProfile: AdblockFilterListProfileKind? = nil,
        identifiers: [String]
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            selectedFilterLists: listIds.map {
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: $0,
                    displayName: $0,
                    contentHash: "\($0)-hash"
                )
            },
            networkShards: identifiers
                .filter { !$0.contains("nativeCSS") }
                .enumerated()
                .map { index, identifier in
                    Self.manifestShard(
                        identifier: identifier,
                        generationId: generationId,
                        kind: .network,
                        nativeProfile: nativeProfile,
                        index: index
                    )
                },
            nativeCSSShards: identifiers
                .filter { $0.contains("nativeCSS") }
                .enumerated()
                .map { index, identifier in
                    Self.manifestShard(
                        identifier: identifier,
                        generationId: generationId,
                        kind: .nativeCosmeticCSS,
                        nativeProfile: nativeProfile,
                        index: index
                    )
                },
            enhancedRuntimeBundle: nil,
            nativeProfile: nativeProfile,
            nativeCompiler: nil,
            nativeCompilerSourceLists: nil,
            compilerDiagnosticsSummary: "unsupported=0; ignored=0",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1_700_000_000),
            previousGenerationId: previousGenerationId
        )
    }

    private static func manifestShard(
        identifier: String,
        generationId: String,
        kind: AdblockCompiledRuleGroupKind,
        nativeProfile: AdblockFilterListProfileKind?,
        index: Int
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: "\(kind.rawValue)-\(String(format: "%04d", index + 1))",
            generationId: generationId,
            kind: kind,
            sourceListIdentifiers: [],
            sourceCategories: [],
            webKitIdentifier: identifier,
            contentHash: "\(identifier)-hash",
            approximateRuleCount: 1,
            jsonByteCount: 2,
            compilerIdentity: nil,
            profileIdentity: nativeProfile,
            diagnosticsSummary: "test"
        )
    }

    private func archive(
        _ manifest: AdblockCompiledGenerationManifest,
        in manifestStore: AdblockUpdateManifestStore
    ) async throws {
        let stagingDirectory = try await manifestStore.beginStaging()
        var stagedCompiledShardURLs = [String: URL]()
        for shard in manifest.allNativeShards {
            let url = stagingDirectory.appendingPathComponent("\(shard.id).json")
            try Data(Self.fixtureCompiledShardJSON.utf8).write(to: url)
            stagedCompiledShardURLs[shard.id] = url
        }
        try await manifestStore.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:],
            stagedCompiledShardURLs: stagedCompiledShardURLs
        )
    }

    private static func definitions(
        for manifest: AdblockCompiledGenerationManifest
    ) -> [SumiContentRuleListDefinition] {
        manifest.allNativeShards.map { shard in
            SumiContentRuleListDefinition(
                name: shard.webKitIdentifier,
                encodedContentRuleList: fixtureCompiledShardJSON,
                storeIdentifierOverride: shard.webKitIdentifier
            )
        }
    }

    private func writeRawList(_ id: String, root: URL) throws {
        let directory = root.appendingPathComponent("RawLists", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("||\(id).example^".utf8).write(to: directory.appendingPathComponent("\(id).txt"))
    }

    private func createStagingDirectory(root: URL, name: String) throws {
        let directory = root.appendingPathComponent("Staging/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("partial.txt"))
    }

    private static func descriptor(_ id: String, defaultEnabled: Bool = false) -> AdblockFilterListDescriptor {
        AdblockFilterListDescriptor(
            id: id,
            displayName: id,
            category: id.contains("regional") ? .regional : .baseAds,
            remoteURL: URL(string: "https://filters.example/\(id).txt")!,
            homepageURL: URL(string: "https://filters.example/"),
            defaultEnabled: defaultEnabled,
            localeTags: [],
            licenseNoticeHint: "test",
            variantOfListId: nil,
            exclusionGroup: id.contains("without") ? "easylist.base.variant" : nil,
            shortDescription: "test",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        )
    }

    private static func response(
        for id: String,
        statusCode: Int = 200,
        eTag: String? = nil
    ) -> HTTPURLResponse {
        var headers = [String: String]()
        if let eTag {
            headers["ETag"] = eTag
        }
        return HTTPURLResponse(
            url: URL(string: "https://filters.example/\(id).txt")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockUpdatePipelineTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static let fixtureCompiledShardJSON = "[]"
}

private actor FakeAdblockDownloader: AdblockFilterListDownloading {
    enum Result {
        case downloaded(Data, HTTPURLResponse)
        case notModified(HTTPURLResponse)
        case failure(Error)
    }

    private(set) var requestedIdentifiers = [String]()
    private let results: [String: Result]

    init(results: [String: Result]) {
        self.results = results
    }

    func allRequestedIdentifiers() -> [String] {
        requestedIdentifiers
    }

    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome {
        requestedIdentifiers.append(descriptor.id)
        switch results[descriptor.id] {
        case .downloaded(let data, let response):
            return .downloaded(data, response)
        case .notModified(let response):
            return .notModified(response)
        case .failure(let error):
            throw error
        case nil:
            throw AdblockUpdateDiagnostics(summary: "unexpected list")
        }
    }
}

private actor FakeAdblockCompiler: NativeContentBlockingCompiler, EnhancedCompatibilityCompiler {
    nonisolated let identity = NativeContentBlockingCompilerIdentity(
        name: "fake-native",
        version: "test"
    )

    private(set) var inputs = [AdblockCompilationInput]()
    private let error: Error?
    private let ruleCap: NativeContentBlockingRuleCapDiagnostics
    private let networkShardCount: Int
    private let nativeCSSShardCount: Int

    init(
        error: Error? = nil,
        ruleCap: NativeContentBlockingRuleCapDiagnostics = .none,
        networkShardCount: Int = 1,
        nativeCSSShardCount: Int = 1
    ) {
        self.error = error
        self.ruleCap = ruleCap
        self.networkShardCount = networkShardCount
        self.nativeCSSShardCount = nativeCSSShardCount
    }

    var compileCount: Int {
        inputs.count
    }

    func currentCompileCount() -> Int {
        inputs.count
    }

    func compileNativeContentBlocking(
        _ input: AdblockCompilationInput
    ) async throws -> NativeContentBlockingCompilationOutput {
        if let error {
            throw error
        }
        inputs.append(input)
        return NativeContentBlockingCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            networkShards: (0..<networkShardCount).map {
                Self.shard(
                    kind: .network,
                    generationId: input.generationId ?? input.sourceIdentifier,
                    sourceLists: input.sourceLists,
                    nativeProfile: input.nativeProfile,
                    identity: identity,
                    index: $0
                )
            },
            nativeCosmeticCSSShards: (0..<nativeCSSShardCount).map {
                Self.shard(
                    kind: .nativeCosmeticCSS,
                    generationId: input.generationId ?? input.sourceIdentifier,
                    sourceLists: input.sourceLists,
                    nativeProfile: input.nativeProfile,
                    identity: identity,
                    index: $0
                )
            },
            diagnostics: AdblockCompilationDiagnostics(
                nativeCosmeticRuleCount: nativeCSSShardCount,
                unsupportedCosmeticRuleCount: 0,
                ignoredScriptletOrProceduralRuleCount: 0,
                isNativeCosmeticGroupEmpty: false,
                ruleCap: ruleCap
            ),
            inputRuleCount: input.filterTexts.count,
            convertedNetworkRuleCount: networkShardCount,
            convertedNativeCosmeticRuleCount: nativeCSSShardCount,
            unsupportedOrIgnoredRuleCount: 0,
            contentHash: "compiled-hash",
            compilerIdentity: identity,
            sourceLists: input.sourceLists,
            nativeProfile: input.nativeProfile,
            shardStrategy: input.shardStrategy
        )
    }

    func compileEnhancedCompatibility(
        _ input: AdblockCompilationInput
    ) async throws -> EnhancedCompatibilityCompilationOutput {
        EnhancedCompatibilityCompilationOutput(
            enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle(
                resources: [],
                unsupportedDiagnostics: []
            ),
            capabilities: []
        )
    }

    private static func shard(
        kind: AdblockCompiledRuleGroupKind,
        generationId: String,
        sourceLists: [NativeContentBlockingSourceList],
        nativeProfile: AdblockFilterListProfileKind?,
        identity: NativeContentBlockingCompilerIdentity,
        index: Int
    ) -> NativeContentBlockingCompiledShard {
        let component = kind == .network ? "network" : "nativeCSS"
        let hash = kind == .network ? "network-hash-\(index)" : "css-hash-\(index)"
        return NativeContentBlockingCompiledShard(
            descriptor: NativeContentBlockingShardDescriptor(
                id: "\(component)-\(String(format: "%04d", index + 1))",
                generationId: generationId,
                kind: kind,
                sourceListIdentifiers: sourceLists.map(\.id).sorted(),
                sourceCategories: Array(Set(sourceLists.compactMap(\.category)))
                    .sorted { $0.rawValue < $1.rawValue },
                webKitIdentifier: "sumi.adblock.\(component).\(generationId).\(String(format: "%04d", index + 1)).\(hash)",
                contentHash: hash,
                approximateRuleCount: 1,
                jsonByteCount: 2,
                compilerIdentity: identity,
                profileIdentity: nativeProfile,
                diagnosticsSummary: "fake"
            ),
            encodedContentRuleList: "[]",
            convertedRuleCount: 1
        )
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }

    func recordedRequest() -> URLRequest? {
        request
    }
}

@MainActor
private final class FakeAdblockPublisher: AdblockRuleListPublishing {
    private(set) var publishedManifests = [AdblockCompiledGenerationManifest]()
    private let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws {
        if let error {
            throw error
        }
        publishedManifests.append(manifest)
    }
}

@MainActor
private final class FakeContentRuleListStore: SumiContentRuleListCompiling {
    private var storedIdentifiers: Set<String>
    private let removeFailures: Set<String>
    private var removed = [String]()

    init(
        identifiers: Set<String>,
        removeFailures: Set<String> = []
    ) {
        storedIdentifiers = identifiers
        self.removeFailures = removeFailures
    }

    func identifiers() -> Set<String> {
        storedIdentifiers
    }

    func removedIdentifiers() -> [String] {
        removed
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        nil
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        storedIdentifiers.contains(identifier)
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        throw AdblockUpdateDiagnostics(summary: "FakeContentRuleListStore does not compile")
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        storedIdentifiers.sorted()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        if removeFailures.contains(identifier) {
            throw AdblockUpdateDiagnostics(summary: "remove failed")
        }
        storedIdentifiers.remove(identifier)
        removed.append(identifier)
    }
}
