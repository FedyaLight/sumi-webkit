import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdBlockingModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testCleanInstallDefaultsAdBlockingDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        XCTAssertFalse(registry.isEnabled(.adBlocking))
        XCTAssertNil(harness.defaults.object(forKey: store.key(for: .adBlocking)))
        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.status, .disabled)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testEnableDisablePersistsWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = SumiModuleSettingsStore(userDefaults: harness.defaults)
        let registry = SumiModuleRegistry(settingsStore: store)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        module.setEnabled(true)

        XCTAssertTrue(SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking))
        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
        XCTAssertFalse(module.hasLoadedRuntime)

        module.setEnabled(false)

        XCTAssertFalse(SumiModuleRegistry(settingsStore: store).isEnabled(.adBlocking))
        XCTAssertEqual(module.status, .disabled)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testAdBlockingStateIsIndependentFromTrackingProtectionState() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        registry.enable(.adBlocking)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertTrue(registry.isEnabled(.adBlocking))

        registry.disable(.trackingProtection)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertTrue(registry.isEnabled(.adBlocking))
    }

    func testDisabledAccessorsReturnEmptyNoOpState() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let decision = module.normalTabDecision(
            for: URL(string: "https://www.example.com/page")!
        )

        XCTAssertEqual(module.status, .disabled)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(decision.status, .disabled)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertTrue(decision.assets.isEmpty)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testEnabledNativeContentBlockingReportsCompiledRuleAssetsWithoutScripts() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let decision = module.normalTabDecision(
            for: URL(string: "https://ads.example.com/page")!
        )

        XCTAssertTrue(module.isEnabled)
        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.status, .enabledNativeContentBlocking)
        XCTAssertEqual(decision.assets.contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(decision.assets.scriptSources.count, 0)
        XCTAssertEqual(decision.assets.scriptMessageHandlerNames.count, 0)
        XCTAssertNotNil(decision.contentBlockingService)
        XCTAssertTrue(module.hasLoadedRuntime)
    }

    func testDisabledAdblockDoesNotCreateCompilerBoundary() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        XCTAssertEqual(module.normalTabDecision(for: URL(string: "https://example.com")).assets, SumiAdBlockingAssets.empty)
        XCTAssertEqual(module.assetsIfAvailable(), SumiAdBlockingAssets.empty)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testInternalSumiPagesAreAdblockIneligibleAndExpectNoShards() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )
        let settingsURL = SumiSurface.settingsSurfaceURL(paneQuery: "privacy")

        let decision = module.normalTabDecision(for: settingsURL)
        let diagnostics = module.attachmentDiagnostics(for: settingsURL)
        let currentTabDiagnostics = module.currentTabDiagnostics(
            for: settingsURL,
            appliedState: nil,
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: []
        )

        XCTAssertFalse(module.surfaceEligibility(for: settingsURL).isEligible)
        XCTAssertEqual(module.surfaceEligibility(for: settingsURL).ineligibleReason, "Internal Sumi surface")
        XCTAssertNil(module.normalizedSiteHost(for: settingsURL))
        XCTAssertFalse(module.effectivePolicy(for: settingsURL).isEnabled)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(diagnostics.isEnabled)
        XCTAssertEqual(diagnostics.ineligibleSurfaceReason, "Internal Sumi surface")
        XCTAssertTrue(diagnostics.expectedNetworkShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.expectedNativeCSSShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.missingShardIdentifiers.isEmpty)
        XCTAssertEqual(currentTabDiagnostics.suspectedBlankPageCategory, "D internal/ineligible surface")
        XCTAssertFalse(didCreateRuleListStore)
    }

    func testAboutBlankIsAdblockIneligibleAndReportsReason() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        let diagnostics = module.attachmentDiagnostics(for: SumiSurface.emptyTabURL)

        XCTAssertEqual(diagnostics.ineligibleSurfaceReason, "Sumi empty/new tab surface")
        XCTAssertTrue(diagnostics.expectedNetworkShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.expectedNativeCSSShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.missingShardIdentifiers.isEmpty)
    }

    func testSwiftCompilerBoundaryInvokesRustAdapter() async throws {
        let adapter = CountingAdblockRustAdapter(output: .tinyFixture)
        let compiler = AdblockRustCompiler(adapter: adapter)

        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "TestAdblock",
                filterTexts: AdblockWebKitRuleListStore.tinyFixtureFilters,
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        let callCount = await adapter.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(output.convertedNetworkRuleCount, 1)
        XCTAssertEqual(output.convertedNativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.nativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.ignoredScriptletOrProceduralRuleCount, 1)
        XCTAssertFalse(output.diagnostics.isNativeCosmeticGroupEmpty)
        XCTAssertTrue(output.groups.contains { $0.kind == .network })
        XCTAssertTrue(output.groups.contains { $0.kind == .nativeCosmeticCSS })
        XCTAssertNotNil(output.hybridOutput.nativeRuleGroups.network)
        XCTAssertNotNil(output.hybridOutput.nativeRuleGroups.nativeCosmeticCSS)
        XCTAssertEqual(output.hybridOutput.enhancedRuntimeBundle.resources.map(\.kind), [.scriptlet])
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.scriptletResourceCandidate))
    }

    func testNativeCompilerAbstractionWrapsRustOutputAndKeepsEnhancedMetadataSeparate() async throws {
        let adapter = CountingAdblockRustAdapter(output: .tinyFixture)
        let compiler = AdblockRustCompiler(adapter: adapter)
        let input = AdblockCompilationInput(
            sourceIdentifier: "TestAdblock",
            filterTexts: AdblockWebKitRuleListStore.tinyFixtureFilters,
            selectedOutputGroups: [.network, .nativeCosmeticCSS],
            sourceLists: [
                NativeContentBlockingSourceList(
                    id: "fixture",
                    displayName: "Fixture",
                    contentHash: "fixture-hash"
                ),
            ]
        )

        let combinedOutput = try await compiler.compileNativeAndEnhancedCompatibility(input)
        let nativeOutput = combinedOutput.nativeOutput
        let enhancedOutput = try XCTUnwrap(combinedOutput.enhancedOutput)

        let callCount = await adapter.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(nativeOutput.compilerIdentity.name, "adblock-rust")
        XCTAssertEqual(nativeOutput.sourceLists.map(\.id), ["fixture"])
        XCTAssertEqual(nativeOutput.convertedNetworkRuleCount, 1)
        XCTAssertEqual(nativeOutput.convertedNativeCosmeticRuleCount, 3)
        XCTAssertEqual(enhancedOutput.enhancedRuntimeBundle.resources.map(\.kind), [.scriptlet])
        XCTAssertTrue(enhancedOutput.capabilities.contains(.scriptletResourceCandidate))
    }

    func testTinyFixtureCompilesIntoSeparatedWebKitJSONGroups() async throws {
        let compiler = AdblockRustCompiler()
        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "TestAdblock",
                filterTexts: Self.tinyFixtureFiltersWithUnsupportedRule,
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertEqual(output.inputRuleCount, 5)
        XCTAssertEqual(output.convertedNetworkRuleCount, 1)
        XCTAssertEqual(output.convertedNativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.unsupportedOrIgnoredRuleCount, 1)
        XCTAssertEqual(output.diagnostics.nativeCosmeticRuleCount, 3)
        XCTAssertEqual(output.diagnostics.unsupportedCosmeticRuleCount, 1)
        XCTAssertEqual(output.diagnostics.ignoredScriptletOrProceduralRuleCount, 1)
        XCTAssertFalse(output.diagnostics.isNativeCosmeticGroupEmpty)
        XCTAssertEqual(output.groups.map(\.kind).sorted { $0.rawValue < $1.rawValue }, [.nativeCosmeticCSS, .network])
        XCTAssertEqual(output.diagnostics.unsupportedRules.count, 1)
        XCTAssertTrue(output.diagnostics.unsupportedRules[0].reason.localizedCaseInsensitiveContains("script"))
        XCTAssertFalse(output.contentHash.isEmpty)

        let networkGroup = try XCTUnwrap(output.groups.first { $0.kind == .network })
        let cosmeticGroup = try XCTUnwrap(output.groups.first { $0.kind == .nativeCosmeticCSS })
        let networkRules = try Self.decodedRuleList(networkGroup.encodedContentRuleList)
        let cosmeticRules = try Self.decodedRuleList(cosmeticGroup.encodedContentRuleList)

        let networkActionTypes = networkRules.compactMap { ($0["action"] as? [String: Any])?["type"] as? String }
        XCTAssertEqual(networkActionTypes.filter { $0 == "block" }.count, 1)
        XCTAssertTrue(networkActionTypes.contains("ignore-previous-rules"))
        XCTAssertEqual(cosmeticRules.count, 3)
        XCTAssertTrue(cosmeticRules.allSatisfy {
            ($0["action"] as? [String: Any])?["type"] as? String == "css-display-none"
        })
        let cosmeticSelectors = cosmeticRules.compactMap {
            ($0["action"] as? [String: Any])?["selector"] as? String
        }
        XCTAssertTrue(cosmeticSelectors.contains(".ad-banner"))
        XCTAssertTrue(cosmeticSelectors.contains(".sponsored"))
        XCTAssertTrue(cosmeticSelectors.contains("#sponsor.card[data-ad=\"1\"]"))
        XCTAssertTrue(cosmeticRules.contains { rule in
            ((rule["trigger"] as? [String: Any])?["if-domain"] as? [String]) == ["example.test"]
                && ((rule["action"] as? [String: Any])?["selector"] as? String) == ".sponsored"
        })
    }

    func testBadFilterIsReportedByRustAdapterWithoutCrashingNativeCompilation() async throws {
        let compiler = AdblockRustCompiler()
        let output = try await compiler.compileNativeContentBlocking(
            AdblockCompilationInput(
                sourceIdentifier: "BadFilter",
                filterTexts: [
                    "||ads.example.test^",
                    "||ads.example.test^$badfilter",
                ],
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertEqual(output.convertedNetworkRuleCount, 0)
        XCTAssertTrue(
            output.diagnostics.unsupportedRules.contains(where: {
                $0.reason.contains("NetworkBadFilterUnsupported")
            })
        )
    }

    func testHybridCompilerClassifiesRedirectAndProceduralCandidatesWithoutNativeParserBypass() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [],
                nativeCosmeticCSS: [],
                unsupportedOrIgnored: [
                    AdblockRustAdapterDiagnostic(
                        rule: "||cdn.example/script.js$redirect=noopjs",
                        reason: "unsupported by WebKit content-blocking conversion"
                    ),
                    AdblockRustAdapterDiagnostic(
                        rule: "example.com#?#.ad:has-text(Sponsored)",
                        reason: "unsupported procedural cosmetic rule"
                    ),
                ],
                enhancedResourceCandidates: [
                    AdblockRustEnhancedResourceCandidate(
                        kind: .noopRedirect,
                        resourceName: "noopjs",
                        canonicalResourceName: "noopjs",
                        resourceType: "script",
                        mimeType: "application/javascript",
                        parameters: [],
                        includeDomains: [],
                        excludeDomains: [],
                        sourceRule: "||cdn.example/script.js$redirect=noopjs",
                        diagnosticSource: "test adapter",
                        unsupportedReason: SumiAdblockEnhancedRuntime.webKitRedirectReplacementUnsupportedReason,
                        matchedTrustedBundledResource: true
                    ),
                    AdblockRustEnhancedResourceCandidate(
                        kind: .proceduralCosmetic,
                        resourceName: "procedural-cosmetic",
                        parameters: [],
                        includeDomains: ["example.com"],
                        excludeDomains: [],
                        sourceRule: "example.com#?#.ad:has-text(Sponsored)",
                        diagnosticSource: "test adapter"
                    ),
                ]
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)

        let output = try await compiler.compile(
            AdblockCompilationInput(
                sourceIdentifier: "Hybrid",
                filterTexts: [
                    "||cdn.example/script.js$redirect=noopjs",
                    "example.com#?#.ad:has-text(Sponsored)",
                ],
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertTrue(output.hybridOutput.nativeRuleGroups.network?.convertedRuleCount ?? 0 == 0)
        XCTAssertEqual(
            output.hybridOutput.enhancedRuntimeBundle.resources.map(\.kind).sorted { $0.rawValue < $1.rawValue },
            [.noopRedirect, .cosmeticCleanup]
                .sorted { $0.rawValue < $1.rawValue }
        )
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.redirectResourceCandidate))
        XCTAssertTrue(output.hybridOutput.capabilities.contains(.enhancedCosmeticCleanup))
        XCTAssertEqual(output.hybridOutput.enhancedRuntimeBundle.unsupportedDiagnostics.count, 2)
        XCTAssertEqual(output.hybridOutput.enhancedRuntimeBundle.redirectResourceCandidates.count, 1)
        let redirect = try XCTUnwrap(output.hybridOutput.enhancedRuntimeBundle.redirectResourceCandidates.first)
        XCTAssertEqual(redirect.requestedName, "noopjs")
        XCTAssertEqual(redirect.canonicalName, "noopjs")
        XCTAssertEqual(redirect.resourceKind, .script)
        XCTAssertEqual(redirect.mimeType, "application/javascript")
        XCTAssertTrue(redirect.matchedTrustedBundledResource)
        XCTAssertTrue(redirect.unsupportedReason?.contains("WKWebView") == true)
    }

    func testCompilerRejectsUnexpectedNativeCosmeticActionsFromAdapter() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [],
                nativeCosmeticCSS: [
                    AdblockRustContentRule(
                        action: .object(["type": .string("script"), "source": .string("alert(1)")]),
                        trigger: .object(["url-filter": .string(".*")])
                    ),
                ],
                unsupportedOrIgnored: []
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)

        do {
            _ = try await compiler.compile(
                AdblockCompilationInput(
                    sourceIdentifier: "TestAdblock",
                    filterTexts: ["##+js(sumi-future-scriptlet)"],
                    selectedOutputGroups: [.nativeCosmeticCSS]
                )
            )
            XCTFail("Expected invalid adapter output")
        } catch AdblockRustCompilerError.invalidAdapterOutput(let message) {
            XCTAssertTrue(message.contains("nativeCosmeticCSS"))
        }
    }

    func testNativeCompilerFiltersOnlyDocumentRootNativeCSSSelectorsWithDiagnostics() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [],
                nativeCosmeticCSS: [
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "body"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "HTML"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "html[class^=\"img_\"]"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "#app"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: ".ad-one, body, .ad-two"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "body > div[id][class*=\" \"]:first-child"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "body > div[id][class*=\" \"]:has(div.adblock_subtitle)"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "BODY > DIV[id][class*=\" \"]"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "body > .ad-three"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: "#root-ad"),
                ],
                unsupportedOrIgnored: []
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)

        let output = try await compiler.compileNativeContentBlocking(
            AdblockCompilationInput(
                sourceIdentifier: "UnsafeNativeCSS",
                filterTexts: ["fixture"],
                selectedOutputGroups: [.nativeCosmeticCSS]
            )
        )
        let shard = try XCTUnwrap(output.nativeCosmeticCSSShards.first)
        let rules = try Self.decodedRuleList(shard.encodedContentRuleList)
        let selectors = rules.compactMap {
            ($0["action"] as? [String: Any])?["selector"] as? String
        }

        XCTAssertEqual(output.diagnostics.filteredUnsafeNativeCosmeticSelectors.map(\.rule), [
            "body",
            "HTML",
            "html[class^=\"img_\"]",
            "#app",
            "body",
            "body > div[id][class*=\" \"]:first-child",
            "body > div[id][class*=\" \"]:has(div.adblock_subtitle)",
            "BODY > DIV[id][class*=\" \"]",
        ])
        XCTAssertEqual(
            output.diagnostics.filteredUnsafeNativeCosmeticSelectors.last?.reason,
            "unsafe native CSS root-child page shell selector"
        )
        XCTAssertEqual(selectors, [
            ".ad-one, .ad-two",
            "body > .ad-three",
            "#root-ad",
        ])
    }

    func testCompilerOutputHashesAreStableForIdenticalInput() async throws {
        let compiler = AdblockRustCompiler()
        let input = AdblockCompilationInput(
            sourceIdentifier: "TestAdblock",
            filterTexts: Self.tinyFixtureFiltersWithUnsupportedRule,
            selectedOutputGroups: [.network, .nativeCosmeticCSS]
        )

        let first = try await compiler.compile(input)
        let second = try await compiler.compile(input)

        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertEqual(first.groups.map(\.contentHash), second.groups.map(\.contentHash))
    }

    func testNativeCompilerDeterministicallyBuildsMultipleNetworkAndNativeCSSShards() async throws {
        let adapter = CountingAdblockRustAdapter(
            output: AdblockRustAdapterOutput(
                network: [
                    Self.contentRule(action: "block", urlFilter: "network-1"),
                    Self.contentRule(action: "block", urlFilter: "network-2"),
                    Self.contentRule(action: "block", urlFilter: "network-3"),
                ],
                nativeCosmeticCSS: [
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: ".ad-one"),
                    Self.contentRule(action: "css-display-none", urlFilter: ".*", selector: ".ad-two"),
                ],
                unsupportedOrIgnored: []
            )
        )
        let compiler = AdblockRustCompiler(adapter: adapter)
        let input = AdblockCompilationInput(
            sourceIdentifier: "ShardFixture",
            generationId: "20260516T120000Z-shardhash",
            nativeProfile: .balancedNative,
            filterTexts: ["fixture"],
            selectedOutputGroups: [.network, .nativeCosmeticCSS],
            shardStrategy: NativeContentBlockingShardStrategy(
                maxRulesPerShard: 1,
                maxJSONBytesPerShard: 1_000_000
            )
        )

        let first = try await compiler.compileNativeContentBlocking(input)
        let second = try await compiler.compileNativeContentBlocking(input)

        XCTAssertEqual(first.networkShards.count, 3)
        XCTAssertEqual(first.nativeCosmeticCSSShards.count, 2)
        XCTAssertEqual(first.networkShards.map(\.descriptor.id), ["network-0001", "network-0002", "network-0003"])
        XCTAssertEqual(first.nativeCosmeticCSSShards.map(\.descriptor.id), ["nativeCSS-0001", "nativeCSS-0002"])
        XCTAssertEqual(first.shards.map(\.descriptor.contentHash), second.shards.map(\.descriptor.contentHash))
        XCTAssertTrue(first.shards.allSatisfy {
            $0.descriptor.webKitIdentifier.hasPrefix("sumi.adblock.")
                && $0.descriptor.webKitIdentifier.contains("20260516T120000Z-shardhash")
                && $0.descriptor.profileIdentity == .balancedNative
        })
    }

    func testSingleLegacySizedCompilerOutputStillRepresentsOneShardPerKind() async throws {
        let output = try await AdblockRustCompiler(
            adapter: CountingAdblockRustAdapter(output: .tinyFixture)
        ).compileNativeContentBlocking(
            AdblockCompilationInput(
                sourceIdentifier: "SingleShard",
                generationId: "single-generation",
                filterTexts: AdblockWebKitRuleListStore.tinyFixtureFilters,
                selectedOutputGroups: [.network, .nativeCosmeticCSS]
            )
        )

        XCTAssertEqual(output.networkShards.count, 1)
        XCTAssertEqual(output.nativeCosmeticCSSShards.count, 1)
        XCTAssertEqual(output.networkShards[0].descriptor.generationId, "single-generation")
        XCTAssertEqual(output.nativeCosmeticCSSShards[0].descriptor.generationId, "single-generation")
    }

    func testBrowserManagerStartupWithAdBlockingDisabledDoesNotCreateRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )

        XCTAssertNotNil(browserManager.currentProfile)
        XCTAssertFalse(browserManager.adBlockingModule.isEnabled)
        XCTAssertFalse(browserManager.adBlockingModule.hasLoadedRuntime)
    }

    func testOpeningSettingsWithAdBlockingDisabledDoesNotReferenceRuntimeShell() throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let model = SumiSettingsModuleToggleModel(
            descriptor: .adBlocking,
            registry: registry
        )

        XCTAssertFalse(model.isEnabled)

        let togglesSource = try Self.source(named: "Sumi/Components/Settings/SumiSettingsModuleToggles.swift")

        XCTAssertFalse(togglesSource.contains("normalTabDecision("))
        XCTAssertFalse(togglesSource.contains("ruleListStoreIfEnabled("))
    }

    func testNormalTabCreationWithAdBlockingDisabledAttachesNoAdBlockingAssets() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/ad-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets, .empty)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testNormalTabCreationWithAdBlockingEnabledAttachesNativeRuleListsOnly() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/ad-enabled-shell",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let webView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(webView.configuration.userContentController.sumiNormalTabUserContentController)
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(module.status, .enabledNativeContentBlocking)
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
        XCTAssertEqual(module.normalTabDecision(for: tab.url).assets.scriptSources.count, 0)
        assertNoAdBlockingScriptsOrHandlers(in: webView.configuration.userContentController)
        XCTAssertTrue(module.hasLoadedRuntime)
    }

    func testAuxiliaryConfigurationsAttachNoAdBlockingAssets() {
        let browserConfiguration = BrowserConfiguration()
        let configurations = [
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .faviconDownload),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .glance),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .miniWindow),
            browserConfiguration.auxiliaryWebViewConfiguration(surface: .extensionOptions),
        ]

        for configuration in configurations {
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserContentController)
            XCTAssertNil(configuration.userContentController.sumiNormalTabUserScriptsProvider)
            XCTAssertTrue(configuration.userContentController.userScripts.isEmpty)
            assertNoAdBlockingScriptsOrHandlers(in: configuration.userContentController)
        }
    }

    func testTrackingProtectionEnabledAdBlockingDisabledPreservesTrackingRuleAttachment() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.trackingProtection)
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        trackingSettings.setGlobalMode(.enabled)
        let trackingService = SumiContentBlockingService(
            policy: .enabled(ruleLists: [Self.validRuleListDefinition()])
        )
        let trackingModule = SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: { trackingSettings },
            dataStoreFactory: { self.makeTrackingDataStore(defaults: harness.defaults) },
            contentBlockingServiceFactory: { _, _ in trackingService }
        )
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/tracking-enabled-ad-disabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 1 }

        XCTAssertFalse(adBlockingModule.isEnabled)
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 1)
    }

    func testTrackingProtectionDisabledAdBlockingEnabledShellAttachesNoRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let adBlockingModule = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: adBlockingModule
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/tracking-disabled-ad-enabled",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertEqual(adBlockingModule.status, .enabledNativeContentBlocking)
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
        XCTAssertEqual(
            tab.trackingProtectionAppliedAttachmentState,
            SumiTrackingProtectionAttachmentState(siteHost: "example.com", isEnabled: false)
        )
        assertNoAdBlockingScriptsOrHandlers(in: controller.wkUserContentController)
    }

    func testAdBlockingToggleDoesNotAffectTrackingProtectionSiteOverrides() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adBlockingModule = SumiAdBlockingModule(moduleRegistry: registry)
        let url = URL(string: "https://www.example.com/path")!

        trackingSettings.setGlobalMode(.enabled)
        trackingSettings.setSiteOverride(.disabled, for: url)
        adBlockingModule.setEnabled(true)

        XCTAssertTrue(registry.isEnabled(.adBlocking))
        XCTAssertEqual(trackingSettings.globalMode, .enabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))

        adBlockingModule.setEnabled(false)

        XCTAssertEqual(trackingSettings.globalMode, .enabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
    }

    func testTrackingProtectionToggleDoesNotEnableAdBlocking() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )

        registry.enable(.trackingProtection)
        XCTAssertTrue(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))

        registry.disable(.trackingProtection)
        XCTAssertFalse(registry.isEnabled(.trackingProtection))
        XCTAssertFalse(registry.isEnabled(.adBlocking))
    }

    func testAdblockSettingsPersistCosmeticModeAutoUpdateAndSelectedLists() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        XCTAssertTrue(settings.autoUpdateEnabled)
        XCTAssertEqual(settings.cosmeticMode, .nativeCSS)
        XCTAssertTrue(settings.regionalListSelection.identifiers.isEmpty)
        XCTAssertTrue(settings.selectedLists.usesDefaultSelection)
        XCTAssertEqual(settings.selectedNativeProfile, .currentDefault)
        XCTAssertFalse(settings.listSelectionRequiresUpdate)

        settings.autoUpdateEnabled = false
        settings.cosmeticMode = .enhancedRuntime
        settings.regionalListSelection = SumiAdblockRegionalListSelection(identifiers: ["de", "pl"])
        settings.selectedLists = SumiAdblockFilterListSelection(identifiers: ["easylist", "ru-adlist"])
        XCTAssertTrue(settings.setSelectedNativeProfile(.balancedNative, allowDeveloperOnly: true))

        let reloaded = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertFalse(reloaded.autoUpdateEnabled)
        XCTAssertEqual(reloaded.cosmeticMode, .enhancedRuntime)
        XCTAssertEqual(reloaded.regionalListSelection.identifiers, ["de", "pl"])
        XCTAssertEqual(reloaded.selectedLists.identifiers, ["easylist", "ru-adlist"])
        XCTAssertEqual(reloaded.selectedNativeProfile, .balancedNative)
        XCTAssertTrue(reloaded.listSelectionRequiresUpdate)
    }

    func testDeveloperOnlyNativeProfilesRequireExplicitDeveloperSelection() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        XCTAssertFalse(settings.setSelectedNativeProfile(.referenceAdGuardNative))
        XCTAssertEqual(settings.selectedNativeProfile, .currentDefault)

        XCTAssertTrue(settings.setSelectedNativeProfile(.referenceAdGuardNative, allowDeveloperOnly: true))
        XCTAssertEqual(settings.selectedNativeProfile, .referenceAdGuardNative)
        XCTAssertTrue(settings.listSelectionRequiresUpdate)
    }

    func testResetListsToSelectedProfileClearsManualCustomSelection() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertTrue(settings.setSelectedNativeProfile(.balancedNative, allowDeveloperOnly: true))
        settings.selectedLists = SumiAdblockFilterListSelection(
            identifiers: ["adguard-base", "easylist", "fanboy-social"]
        )
        let registry = AdblockFilterListRegistry()

        XCTAssertTrue(
            registry.effectiveSelectionDiagnostics(
                selection: settings.selectedLists,
                profileKind: settings.selectedNativeProfile
            ).isCustomListSelection
        )

        settings.resetListsToSelectedProfile()

        let diagnostics = registry.effectiveSelectionDiagnostics(
            selection: settings.selectedLists,
            profileKind: settings.selectedNativeProfile,
            locale: Locale(identifier: "en_US")
        )
        XCTAssertTrue(settings.selectedLists.usesDefaultSelection)
        XCTAssertEqual(diagnostics.finalEffectiveListIdentifiers, ["adguard-base", "adguard-mobile-ads"])
        XCTAssertFalse(diagnostics.isCustomListSelection)
        XCTAssertTrue(settings.listSelectionRequiresUpdate)
    }

    func testLegacyOraLikeNativeSettingsProfileLoadsAsReferenceAdGuardNative() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        harness.defaults.set("oraLikeNative", forKey: "settings.adblock.selectedNativeProfile")

        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        XCTAssertEqual(settings.selectedNativeProfile, .referenceAdGuardNative)
        XCTAssertTrue(settings.setSelectedNativeProfile(.referenceAdGuardNative, allowDeveloperOnly: true))
        XCTAssertEqual(harness.defaults.string(forKey: "settings.adblock.selectedNativeProfile"), "referenceAdGuardNative")
    }

    func testDisabledAdblockCanPersistListAndProfileSelectionWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.selectedLists = SumiAdblockFilterListSelection(identifiers: ["easylist", "ru-adlist"])
        XCTAssertTrue(settings.setSelectedNativeProfile(.balancedNative, allowDeveloperOnly: true))
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.assetsIfAvailable(), .empty)
        XCTAssertEqual(module.normalTabDecision(for: URL(string: "https://example.com")).assets, .empty)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
        let reloaded = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertEqual(reloaded.selectedLists.identifiers, ["easylist", "ru-adlist"])
        XCTAssertEqual(reloaded.selectedNativeProfile, .balancedNative)
    }

    func testCosmeticModesOnlySelectNativeRuleListsAndNeverScripts() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)

        settings.cosmeticMode = .off
        var module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 1)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])

        settings.cosmeticMode = .nativeCSS
        module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])

        settings.cosmeticMode = .enhancedRuntime
        module = SumiAdBlockingModule(moduleRegistry: registry, settingsFactory: { settings })
        XCTAssertEqual(module.assetsIfAvailable().contentRuleListIdentifiers.count, 2)
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptSources, [])
        XCTAssertEqual(module.normalTabDecision(for: nil).assets.scriptMessageHandlerNames, [])
    }

    func testEnhancedRuntimeInstallsOnlyAfterAllNormalTabGatesPass() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .enhancedRuntime
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )

        _ = module.normalTabDecision(for: URL(string: "https://example.com"))
        await capturedStore?.loadActiveManifestIfEnabled()

        let scripts = module.normalTabEnhancedRuntimeScripts(for: URL(string: "https://example.com"))
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].source.contains("SUMI_ADBLOCK_ENHANCED_RUNTIME"))
        XCTAssertTrue(scripts[0].source.contains("sumi.adblock.enhanced"))
        XCTAssertTrue(scripts[0].messageNames.isEmpty)
    }

    func testAttachmentDiagnosticsExposeCompilerListsGroupsAndStaleState() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        settings.selectedLists = SumiAdblockFilterListSelection(identifiers: ["easylist"])
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )
        _ = module.normalTabDecision(for: URL(string: "https://example.com"))
        await capturedStore?.loadActiveManifestIfEnabled()

        let diagnostics = module.attachmentDiagnostics(for: URL(string: "https://example.com/page"))

        XCTAssertEqual(diagnostics.siteHost, "example.com")
        XCTAssertTrue(diagnostics.globalAdblockEnabled)
        XCTAssertTrue(diagnostics.sitePolicyAllowsAdblock)
        XCTAssertEqual(diagnostics.siteOverride, .inherit)
        XCTAssertTrue(diagnostics.isEnabled)
        XCTAssertTrue(diagnostics.hasActiveGeneration)
        XCTAssertEqual(diagnostics.attachedNativeGroups, [.nativeCosmeticCSS, .network])
        XCTAssertEqual(diagnostics.attachedShardIdentifiers.count, 2)
        XCTAssertEqual(diagnostics.expectedNetworkShardIdentifiers, ["sumi.adblock.network.hybridtest"])
        XCTAssertEqual(diagnostics.expectedNativeCSSShardIdentifiers, ["sumi.adblock.nativeCSS.hybridtest"])
        XCTAssertTrue(diagnostics.missingShardIdentifiers.isEmpty)
        XCTAssertEqual(diagnostics.selectedListIdentifiers, ["easylist"])
        XCTAssertEqual(diagnostics.activeManifestListIdentifiers, ["easylist"])
        XCTAssertEqual(diagnostics.selectedNativeProfile, .currentDefault)
        XCTAssertEqual(diagnostics.activeCompiledNativeProfile, .currentDefault)
        XCTAssertFalse(diagnostics.selectedProfileDiffersFromActiveGeneration)
        XCTAssertEqual(diagnostics.activeGenerationId, "hybrid-test-generation")
        XCTAssertNil(diagnostics.previousGenerationId)
        XCTAssertFalse(diagnostics.previousGenerationRetained)
        XCTAssertNotNil(diagnostics.lastSuccessfulUpdateDate)
        XCTAssertEqual(diagnostics.nativeCompiler?.name, "adblock-rust")
        XCTAssertEqual(diagnostics.networkShardCount, 1)
        XCTAssertEqual(diagnostics.nativeCSSShardCount, 1)
        XCTAssertEqual(diagnostics.totalNetworkRuleCount, 1)
        XCTAssertEqual(diagnostics.totalNativeCSSRuleCount, 1)
        XCTAssertEqual(diagnostics.largestShardJSONByteCount, 2)
        XCTAssertEqual(diagnostics.unsafeNativeCSSFilteredRuleCount, 2)
#if DEBUG
        XCTAssertNotNil(diagnostics.currentProcessResidentMemoryBytes)
#endif
        XCTAssertEqual(diagnostics.cosmeticMode, .nativeCSS)
        XCTAssertFalse(diagnostics.enhancedRuntimeIsEnabled)
        XCTAssertFalse(diagnostics.trackingProtectionModuleEnabled)
        XCTAssertTrue(diagnostics.generationIsStale)
        XCTAssertTrue(module.attachmentDiagnosticsReport(for: URL(string: "https://example.com/page")).contains("selectedNativeProfile=currentDefault"))
        XCTAssertTrue(module.attachmentDiagnosticsReport(for: URL(string: "https://example.com/page")).contains("activeCompiledNativeProfile=currentDefault"))
    }

    func testAttachmentDiagnosticsShowDisabledStateWithoutCreatingRuleListRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        XCTAssertTrue(settings.setSelectedNativeProfile(.balancedNative, allowDeveloperOnly: true))
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        let diagnostics = module.attachmentDiagnostics(for: URL(string: "https://example.com"))

        XCTAssertFalse(diagnostics.globalAdblockEnabled)
        XCTAssertFalse(diagnostics.sitePolicyAllowsAdblock)
        XCTAssertFalse(diagnostics.isEnabled)
        XCTAssertEqual(diagnostics.selectedNativeProfile, .balancedNative)
        XCTAssertNil(diagnostics.activeCompiledNativeProfile)
        XCTAssertEqual(diagnostics.selectedListIdentifiers, ["adguard-base", "adguard-mobile-ads", "ru-adlist"])
        XCTAssertTrue(diagnostics.attachedShardIdentifiers.isEmpty)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testAttachmentDiagnosticsRespectPerSiteDisabledWithoutAttachingShards() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/page")!
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        let diagnostics = module.attachmentDiagnostics(for: url)

        XCTAssertTrue(diagnostics.globalAdblockEnabled)
        XCTAssertFalse(diagnostics.sitePolicyAllowsAdblock)
        XCTAssertEqual(diagnostics.siteOverride, .disabled)
        XCTAssertTrue(diagnostics.attachedNativeGroups.isEmpty)
        XCTAssertTrue(diagnostics.attachedShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.expectedNetworkShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.expectedNativeCSSShardIdentifiers.isEmpty)
        XCTAssertFalse(didCreateRuleListStore)
    }

    func testAttachmentDiagnosticsTrackShardAttachmentByCosmeticMode() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )
        _ = module.normalTabDecision(for: URL(string: "https://example.com"))
        await capturedStore?.loadActiveManifestIfEnabled()

        settings.cosmeticMode = .off
        let offDiagnostics = module.attachmentDiagnostics(for: URL(string: "https://example.com"))
        XCTAssertEqual(offDiagnostics.attachedNativeGroups, [.network])
        XCTAssertEqual(offDiagnostics.attachedShardIdentifiers.count, 1)
        XCTAssertFalse(offDiagnostics.enhancedRuntimeIsEnabled)

        settings.cosmeticMode = .nativeCSS
        let nativeDiagnostics = module.attachmentDiagnostics(for: URL(string: "https://example.com"))
        XCTAssertEqual(nativeDiagnostics.attachedNativeGroups, [.nativeCosmeticCSS, .network])
        XCTAssertEqual(nativeDiagnostics.attachedShardIdentifiers.count, 2)
        XCTAssertFalse(nativeDiagnostics.enhancedRuntimeIsEnabled)

        settings.cosmeticMode = .enhancedRuntime
        let enhancedDiagnostics = module.attachmentDiagnostics(for: URL(string: "https://example.com"))
        XCTAssertEqual(enhancedDiagnostics.attachedNativeGroups, [.nativeCosmeticCSS, .network])
        XCTAssertEqual(enhancedDiagnostics.attachedShardIdentifiers.count, 2)
        XCTAssertTrue(enhancedDiagnostics.enhancedRuntimeIsEnabled)
    }

    func testCurrentTabDiagnosticsShowExpectedAttachedAndMissingShards() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/current-tab-diagnostics",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()
        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }

        let diagnostics = try XCTUnwrap(tab.adblockCurrentTabDiagnostics())

        XCTAssertEqual(diagnostics.normalizedSiteKey, "example.com")
        XCTAssertTrue(diagnostics.globalAdblockEnabled)
        XCTAssertTrue(diagnostics.perSiteAdblockEnabled)
        XCTAssertFalse(diagnostics.reloadRequired)
        XCTAssertEqual(diagnostics.selectedNativeProfile, .currentDefault)
        XCTAssertEqual(diagnostics.activeCompiledNativeProfile, .currentDefault)
        XCTAssertEqual(diagnostics.expectedNetworkShardIdentifiers, ["sumi.adblock.network.hybridtest"])
        XCTAssertEqual(diagnostics.expectedNativeCSSShardIdentifiers, ["sumi.adblock.nativeCSS.hybridtest"])
        XCTAssertEqual(diagnostics.attachedNetworkShardIdentifiers, ["sumi.adblock.network.hybridtest"])
        XCTAssertEqual(diagnostics.attachedNativeCSSShardIdentifiers, ["sumi.adblock.nativeCSS.hybridtest"])
        XCTAssertTrue(diagnostics.missingShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.unexpectedOldShardIdentifiers.isEmpty)
        XCTAssertTrue(diagnostics.tabUsesActiveGeneration)
        XCTAssertFalse(diagnostics.hasMixedGenerationAttachment)
        XCTAssertEqual(diagnostics.attachmentAssessment, "active generation attached")
        XCTAssertEqual(
            diagnostics.suspectedBlankPageCategory,
            "A possible native CSS over-hiding; compare cosmeticMode.off"
        )

        let appliedDiagnostics = module.currentTabDiagnostics(
            for: tab.url,
            appliedState: SumiAdblockAttachmentState(
                siteHost: "example.com",
                isEnabled: true,
                attachedShardIdentifiers: [
                    "sumi.adblock.network.hybridtest",
                    "sumi.adblock.nativeCSS.hybridtest",
                ]
            ),
            reloadRequired: false
        )
        XCTAssertEqual(appliedDiagnostics.attachedNetworkShardIdentifiers, ["sumi.adblock.network.hybridtest"])
        XCTAssertEqual(appliedDiagnostics.attachedNativeCSSShardIdentifiers, ["sumi.adblock.nativeCSS.hybridtest"])
        XCTAssertTrue(appliedDiagnostics.missingShardIdentifiers.isEmpty)

        let missingDiagnostics = module.currentTabDiagnostics(
            for: tab.url,
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: ["sumi.adblock.network.hybridtest"]
        )
        XCTAssertEqual(missingDiagnostics.missingShardIdentifiers, ["sumi.adblock.nativeCSS.hybridtest"])
        XCTAssertTrue(missingDiagnostics.reloadRequiredForActiveGeneration)
        XCTAssertEqual(
            missingDiagnostics.suspectedBlankPageCategory,
            "C mixed/stale/reload-required attachment"
        )
    }

    func testCurrentTabDiagnosticsDetectMixedAndOldShardAttachment() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: AdblockSitePolicyStore(userDefaults: harness.defaults)
        )
        try await waitForActiveAdblockGeneration(in: module)
        let oldIdentifier = "sumi.adblock.network.old-generation.0001.oldhash"

        let diagnostics = module.currentTabDiagnostics(
            for: URL(string: "https://example.com/mixed"),
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: [
                "sumi.adblock.network.hybridtest",
                "sumi.adblock.nativeCSS.hybridtest",
                oldIdentifier,
            ]
        )

        XCTAssertTrue(diagnostics.hasMixedGenerationAttachment)
        XCTAssertEqual(diagnostics.unexpectedOldShardIdentifiers, [oldIdentifier])
        XCTAssertTrue(diagnostics.reloadRequiredForActiveGeneration)
        XCTAssertEqual(diagnostics.attachmentAssessment, "mixed old and active Adblock generations attached")
        XCTAssertEqual(diagnostics.suspectedBlankPageCategory, "C mixed/stale/reload-required attachment")
    }

    func testCurrentTabDiagnosticsDetectAttachedGenerationDifferentFromActiveGeneration() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: AdblockSitePolicyStore(userDefaults: harness.defaults)
        )
        try await waitForActiveAdblockGeneration(in: module)

        let diagnostics = module.currentTabDiagnostics(
            for: URL(string: "https://example.com/old-generation"),
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: [
                "sumi.adblock.network.old-generation.0001.oldhash",
                "sumi.adblock.nativeCSS.old-generation.0001.oldhash",
            ]
        )

        XCTAssertEqual(diagnostics.attachedGenerationId, "old-generation")
        XCTAssertFalse(diagnostics.tabUsesActiveGeneration)
        XCTAssertTrue(diagnostics.tabAppearsToUseOlderGeneration)
        XCTAssertEqual(diagnostics.missingShardIdentifiers.count, 2)
        XCTAssertEqual(diagnostics.unexpectedOldShardIdentifiers.count, 2)
        XCTAssertTrue(diagnostics.reloadRequiredForActiveGeneration)
        XCTAssertEqual(diagnostics.suspectedBlankPageCategory, "C mixed/stale/reload-required attachment")
    }

    func testCurrentTabDiagnosticsDetectAttachedShardsWhenPerSiteDisabled() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/disabled")!
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )

        let diagnostics = module.currentTabDiagnostics(
            for: url,
            appliedState: SumiAdblockAttachmentState.disabled(siteHost: "example.com"),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: ["sumi.adblock.network.old-generation.0001.hash"]
        )

        XCTAssertTrue(diagnostics.attachedWhilePerSiteAdblockDisabled)
        XCTAssertTrue(diagnostics.reloadRequiredForActiveGeneration)
        XCTAssertEqual(diagnostics.attachmentAssessment, "attached while per-site Adblock is disabled")
    }

    func testCurrentTabDiagnosticsDetectNativeCSSAttachedWhileCosmeticModeOff() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .off
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: AdblockSitePolicyStore(userDefaults: harness.defaults)
        )
        try await waitForActiveAdblockGeneration(in: module)

        let diagnostics = module.currentTabDiagnostics(
            for: URL(string: "https://example.com/off"),
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: [
                "sumi.adblock.network.hybridtest",
                "sumi.adblock.nativeCSS.hybridtest",
            ]
        )

        XCTAssertTrue(diagnostics.nativeCSSAttachedWhileCosmeticModeOff)
        XCTAssertEqual(diagnostics.expectedNativeCSSShardIdentifiers, [])
        XCTAssertTrue(diagnostics.reloadRequiredForActiveGeneration)
        XCTAssertEqual(diagnostics.attachmentAssessment, "native CSS attached while cosmetic mode is off")

        let networkOnlyDiagnostics = module.currentTabDiagnostics(
            for: URL(string: "https://example.com/off"),
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: ["sumi.adblock.network.hybridtest"]
        )
        XCTAssertEqual(
            networkOnlyDiagnostics.suspectedBlankPageCategory,
            "B possible network overblocking; compare Adblock disabled"
        )
    }

    func testSettingsDiagnosticsCanTargetLastActiveEligibleWebTab() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let module = SumiAdBlockingModule(moduleRegistry: registry)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let windowState = BrowserWindowState()
        let space = browserManager.tabManager.currentSpace
        windowState.currentSpaceId = space?.id
        let webTab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/failing-page",
            in: space,
            activate: false
        )
        let settingsTab = browserManager.tabManager.createNewTab(
            url: SumiSurface.settingsSurfaceURL(paneQuery: "privacy").absoluteString,
            in: space,
            activate: false
        )
        windowState.currentTabId = settingsTab.id
        if let spaceId = space?.id {
            windowState.recentRegularTabIdsBySpace[spaceId] = [settingsTab.id, webTab.id]
        }

        let target = browserManager.lastActiveAdblockEligibleNormalWebTab(
            in: windowState,
            excluding: settingsTab
        )
        let report = module.copyDiagnosticsReport(
            for: target?.url,
            currentTabDiagnostics: nil,
            targetDescription: "last eligible web tab (current tab ineligible: Internal Sumi surface)"
        )

        XCTAssertEqual(target?.id, webTab.id)
        XCTAssertTrue(report.contains("targetSource=last eligible web tab"))
        XCTAssertTrue(report.contains("targetURL=https://www.example.com/failing-page"))
        XCTAssertTrue(report.contains("diagnosticsTargetURL=https://www.example.com/failing-page"))
        XCTAssertTrue(report.contains("requestingURL=nil"))
        XCTAssertFalse(report.contains("targetURL=sumi://settings"))
    }

    func testCopyDiagnosticsReportIncludesActionableAttachmentAndSelectionFields() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: AdblockSitePolicyStore(userDefaults: harness.defaults)
        )
        let url = URL(string: "https://example.com/report")!
        try await waitForActiveAdblockGeneration(in: module, url: url)
        let tabDiagnostics = module.currentTabDiagnostics(
            for: url,
            appliedState: SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: true),
            reloadRequired: true,
            actualAttachedRuleListIdentifiers: [
                "sumi.adblock.network.hybridtest",
                "sumi.adblock.nativeCSS.hybridtest",
            ]
        )

        let report = module.copyDiagnosticsReport(
            for: url,
            currentTabDiagnostics: tabDiagnostics,
            targetDescription: "current tab",
            requestingURL: SumiSurface.settingsSurfaceURL(paneQuery: "privacy")
        )

        for required in [
            "Sumi Adblock Copy Diagnostics",
            "timestamp=",
            "targetSource=current tab",
            "targetURL=https://example.com/report",
            "diagnosticsTargetURL=https://example.com/report",
            "requestingURL=sumi://settings?pane=privacy",
            "currentURL=https://example.com/report",
            "normalizedSiteKey=example.com",
            "selectedNativeProfile=currentDefault",
            "activeCompiledNativeProfile=currentDefault",
            "expectedNetworkShardIdentifiers=sumi.adblock.network.hybridtest",
            "actualAttachedShardIdentifiers=sumi.adblock.nativeCSS.hybridtest,sumi.adblock.network.hybridtest",
            "reloadRequired=true",
            "trackingProtectionEnabled=false",
            "unsafeNativeCSSFilteredRuleCount=2",
            "suspectedBlankPageCategory=C mixed/stale/reload-required attachment",
            "blankPageComparisonHint=",
        ] {
            XCTAssertTrue(report.contains(required), required)
        }
    }

    func testBlankPageClassifierDistinguishesNativeCSSAndNetworkOverblocking() {
        XCTAssertEqual(
            SumiAdblockBlankPageDiagnosticClassifier.classify(
                adblockOffVisible: true,
                networkOnlyVisible: true,
                nativeCSSVisible: false
            ),
            "suspected native CSS over-hide"
        )
        XCTAssertEqual(
            SumiAdblockBlankPageDiagnosticClassifier.classify(
                adblockOffVisible: true,
                networkOnlyVisible: false,
                nativeCSSVisible: false
            ),
            "suspected network overblocking"
        )
    }

    func testEnhancedRuntimeFirstSliceIsLocalBoundedAndHasNoEvalObserverTimerOrBridge() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockEnhancedRuntime.swift")

        XCTAssertTrue(source.contains("SUMI_ADBLOCK_ENHANCED_RUNTIME"))
        XCTAssertTrue(source.contains("sumi.adblock.enhanced"))
        XCTAssertTrue(source.contains("maxElements = 50"))
        XCTAssertTrue(source.contains("data-sumi-adblock-enhanced-cleanup"))
        for forbidden in [
            "eval(",
            "new Function",
            "MutationObserver",
            "setInterval",
            "setTimeout",
            "addScriptMessageHandler",
            "WKWebExtension",
            "URLSession",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    func testTrustedResourceBundleAllowsOnlyKnownAliases() throws {
        let bundle = SumiAdblockEnhancedRuntime.makeTrustedResourceBundle()

        XCTAssertEqual(bundle.trustedScriptlet(for: "sumi-hide")?.canonicalName, "sumi-hide.js")
        XCTAssertEqual(bundle.trustedScriptlet(for: "sumi-hide.js")?.canonicalName, "sumi-hide.js")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "noopjs")?.canonicalName, "noopjs")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "noop.js")?.canonicalName, "noopjs")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "noop.css")?.canonicalName, "noopcss")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "1x1.gif")?.canonicalName, "1x1-transparent.gif")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "noop.html")?.canonicalName, "noopframe")
        XCTAssertEqual(bundle.trustedRedirectResource(for: "nooptext")?.canonicalName, "noop.txt")
        XCTAssertFalse(try XCTUnwrap(bundle.trustedRedirectResource(for: "noopjs")).canBeDeliveredInWebKit)
        XCTAssertNil(bundle.trustedScriptlet(for: "abort-on-property-read"))
        XCTAssertNil(bundle.trustedScriptlet(for: "remote-script"))
        XCTAssertNil(bundle.trustedRedirectResource(for: "noop"))
        XCTAssertNil(bundle.trustedRedirectResource(for: "custom-resource"))
    }

    func testPageApplicabilityResolverSelectsOnlyMatchingTrustedScriptlets() throws {
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [
                AdblockEnhancedResource(
                    name: "sumi-hide",
                    kind: .scriptlet,
                    sourceRule: "example.com##+js(sumi-hide, .ad-one)"
                ),
                AdblockEnhancedResource(
                    name: "unknown-scriptlet",
                    kind: .scriptlet,
                    sourceRule: "example.com##+js(unknown-scriptlet, .ad-two)"
                ),
                AdblockEnhancedResource(
                    name: "sumi-hide",
                    kind: .scriptlet,
                    sourceRule: "other.test##+js(sumi-hide, .ad-three)"
                ),
            ],
            scriptletInvocations: [
                AdblockScriptletInvocation(
                    resourceName: "sumi-hide",
                    parameters: [".ad-one"],
                    includeDomains: ["example.com"],
                    excludeDomains: [],
                    sourceRule: "example.com##+js(sumi-hide, .ad-one)",
                    diagnosticSource: "test"
                ),
                AdblockScriptletInvocation(
                    resourceName: "unknown-scriptlet",
                    parameters: [".ad-two"],
                    includeDomains: ["example.com"],
                    excludeDomains: [],
                    sourceRule: "example.com##+js(unknown-scriptlet, .ad-two)",
                    diagnosticSource: "test"
                ),
                AdblockScriptletInvocation(
                    resourceName: "sumi-hide",
                    parameters: [".ad-three"],
                    includeDomains: ["other.test"],
                    excludeDomains: [],
                    sourceRule: "other.test##+js(sumi-hide, .ad-three)",
                    diagnosticSource: "test"
                ),
            ],
            unsupportedDiagnostics: []
        )
        let resolver = AdblockEnhancedRuntimeResolver()

        let script = resolver.resolve(
            runtimeBundle: runtimeBundle,
            pageURL: URL(string: "https://www.example.com/page")
        )

        let source = try XCTUnwrap(script?.source)
        XCTAssertTrue(source.contains(".ad-one"))
        XCTAssertFalse(source.contains(".ad-two"))
        XCTAssertFalse(source.contains(".ad-three"))
        XCTAssertFalse(script?.requiresPageWorld == true)
    }

    func testRedirectNoopResolverDiagnosesKnownResourcesAsUnsupportedInWebKit() throws {
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [
                AdblockEnhancedResource(
                    name: "noopjs",
                    kind: .noopRedirect,
                    sourceRule: "||cdn.example/script.js$script,redirect=noopjs,domain=example.com"
                ),
            ],
            redirectResourceCandidates: [
                AdblockRedirectResourceCandidate(
                    requestedName: "noop.js",
                    canonicalName: "noopjs",
                    alias: "noop.js",
                    resourceKind: .script,
                    mimeType: "application/javascript",
                    includeDomains: ["example.com"],
                    excludeDomains: [],
                    sourceRule: "||cdn.example/script.js$script,redirect=noop.js,domain=example.com",
                    diagnosticSource: "test",
                    unsupportedReason: SumiAdblockEnhancedRuntime.webKitRedirectReplacementUnsupportedReason,
                    matchedTrustedBundledResource: true
                ),
            ],
            unsupportedDiagnostics: []
        )

        let resolution = AdblockEnhancedRuntimeResolver().resolveDetailed(
            runtimeBundle: runtimeBundle,
            pageURL: URL(string: "https://www.example.com/page")
        )

        XCTAssertNil(resolution.script)
        XCTAssertTrue(resolution.redirectResources.isEmpty)
        XCTAssertEqual(resolution.diagnostics.count, 1)
        XCTAssertTrue(resolution.diagnostics[0].reason.contains("cannot replace http/https response bodies"))
    }

    func testRedirectNoopResolverRejectsUnknownResourcesAndRespectsDomains() {
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [
                AdblockEnhancedResource(
                    name: "unknown-resource",
                    kind: .redirect,
                    sourceRule: "||cdn.example/custom.js$script,redirect=unknown-resource,domain=example.com"
                ),
                AdblockEnhancedResource(
                    name: "noopcss",
                    kind: .noopRedirect,
                    sourceRule: "||cdn.example/ad.css$stylesheet,redirect=noopcss,domain=other.test"
                ),
            ],
            redirectResourceCandidates: [
                AdblockRedirectResourceCandidate(
                    requestedName: "unknown-resource",
                    canonicalName: "unknown-resource",
                    alias: nil,
                    resourceKind: .unknown,
                    mimeType: nil,
                    includeDomains: ["example.com"],
                    excludeDomains: [],
                    sourceRule: "||cdn.example/custom.js$script,redirect=unknown-resource,domain=example.com",
                    diagnosticSource: "test",
                    unsupportedReason: "unknown redirect resource",
                    matchedTrustedBundledResource: false
                ),
                AdblockRedirectResourceCandidate(
                    requestedName: "noopcss",
                    canonicalName: "noopcss",
                    alias: nil,
                    resourceKind: .stylesheet,
                    mimeType: "text/css",
                    includeDomains: ["other.test"],
                    excludeDomains: [],
                    sourceRule: "||cdn.example/ad.css$stylesheet,redirect=noopcss,domain=other.test",
                    diagnosticSource: "test",
                    unsupportedReason: SumiAdblockEnhancedRuntime.webKitRedirectReplacementUnsupportedReason,
                    matchedTrustedBundledResource: true
                ),
            ],
            unsupportedDiagnostics: []
        )

        let resolution = AdblockEnhancedRuntimeResolver().resolveDetailed(
            runtimeBundle: runtimeBundle,
            pageURL: URL(string: "https://example.com/")
        )

        XCTAssertTrue(resolution.redirectResources.isEmpty)
        XCTAssertEqual(resolution.diagnostics.count, 1)
        XCTAssertTrue(resolution.diagnostics[0].reason.contains("unknown redirect/noop resource"))
        XCTAssertFalse(resolution.diagnostics[0].rule.contains("ad.css"))
    }

    func testRedirectNoopResolverCapsResourcesPerPage() {
        let candidates = (0..<3).map { index in
            AdblockRedirectResourceCandidate(
                requestedName: "unknown-\(index)",
                canonicalName: "unknown-\(index)",
                alias: nil,
                resourceKind: .unknown,
                mimeType: nil,
                includeDomains: ["example.com"],
                excludeDomains: [],
                sourceRule: "||cdn.example/\(index).js$script,redirect=unknown-\(index),domain=example.com",
                diagnosticSource: "test",
                unsupportedReason: "unknown redirect resource",
                matchedTrustedBundledResource: false
            )
        }
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [],
            redirectResourceCandidates: candidates,
            unsupportedDiagnostics: []
        )

        let resolution = AdblockEnhancedRuntimeResolver(maxRedirectResourcesPerPage: 1).resolveDetailed(
            runtimeBundle: runtimeBundle,
            pageURL: URL(string: "https://example.com/")
        )

        XCTAssertEqual(resolution.diagnostics.filter { $0.reason == "redirect/noop resource cap reached" }.count, 2)
    }

    func testPageApplicabilityResolverDoesNotInstallAllResourcesGlobally() {
        let runtimeBundle = AdblockEnhancedRuntimeBundle(
            resources: [
                AdblockEnhancedResource(
                    name: "sumi-hide",
                    kind: .scriptlet,
                    sourceRule: "example.com##+js(sumi-hide, .ad-one)"
                ),
            ],
            scriptletInvocations: [
                AdblockScriptletInvocation(
                    resourceName: "sumi-hide",
                    parameters: [".ad-one"],
                    includeDomains: ["example.com"],
                    excludeDomains: [],
                    sourceRule: "example.com##+js(sumi-hide, .ad-one)",
                    diagnosticSource: "test"
                ),
            ],
            unsupportedDiagnostics: []
        )

        XCTAssertNil(
            AdblockEnhancedRuntimeResolver().resolve(
                runtimeBundle: runtimeBundle,
                pageURL: URL(string: "https://unrelated.test/")
            )
        )
    }

    func testNativeCSSAndDisabledModesRemainAdblockRuntimeScriptFreeInTabProvider() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/native-css-free",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        settings.cosmeticMode = .nativeCSS
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )

        settings.cosmeticMode = .off
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )

        module.setEnabled(false)
        XCTAssertFalse(
            tab.normalTabUserScriptsProvider(for: tab.url)
                .userScripts
                .map(\.source)
                .joined(separator: "\n")
                .contains("SUMI_ADBLOCK_ENHANCED_RUNTIME")
        )
    }

    func testEnhancedRuntimeGatesKeepDisabledNativeCSSOffAndPerSiteDisabledScriptFree() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        var capturedStore: AdblockWebKitRuleListStore?
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                let store = AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
                capturedStore = store
                return store
            }
        )
        let url = URL(string: "https://example.com")!
        _ = module.normalTabDecision(for: url)
        await capturedStore?.loadActiveManifestIfEnabled()

        settings.cosmeticMode = .off
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        settings.cosmeticMode = .nativeCSS
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        settings.cosmeticMode = .enhancedRuntime
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)

        module.setEnabled(false)
        sitePolicyStore.setSiteOverride(.allowed, for: url)
        XCTAssertTrue(module.normalTabEnhancedRuntimeScripts(for: url).isEmpty)
    }

    func testCosmeticModeChangeUpdatesEnabledNativeRuleListPolicy() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        settings.cosmeticMode = .nativeCSS
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let decision = module.normalTabDecision(for: URL(string: "https://example.com"))
        let service = try XCTUnwrap(decision.contentBlockingService)
        let controller: WKUserContentController = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingServices: [service]
        )
        let normalTabController = try XCTUnwrap(controller.sumiNormalTabUserContentController)

        try await waitForAssets(on: normalTabController) { $0.globalRuleListCount == 2 }

        settings.cosmeticMode = .off

        let summary = try await waitForAssets(on: normalTabController) { $0.globalRuleListCount == 1 }
        XCTAssertEqual(summary.updateRuleCount, 1)
    }

    func testPerSiteDisabledPolicyPreventsRuleListAttachment() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/page"))
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )

        let decision = module.normalTabDecision(for: URL(string: "https://example.com/other"))

        XCTAssertEqual(decision.status, .enabledNativeContentBlocking)
        XCTAssertEqual(decision.assets, .empty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSitePolicyNormalizesHostWithoutPathOrQuery() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)

        sitePolicyStore.setSiteOverride(
            .disabled,
            for: URL(string: "https://www.example.com/path/to/page?ad=1#fragment")
        )

        XCTAssertEqual(sitePolicyStore.sortedSiteOverrides.map(\.host), ["example.com"])
        XCTAssertEqual(
            sitePolicyStore.effectivePolicy(
                for: URL(string: "https://example.com/other"),
                globalEnabled: true
            ),
            SumiAdblockEffectivePolicy(host: "example.com", isEnabled: false)
        )
    }

    func testSettingsOverrideChangesAreReflectedByModuleEffectivePolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let url = URL(string: "https://www.example.com/path")!

        XCTAssertTrue(module.effectivePolicy(for: url).isEnabled)

        sitePolicyStore.setSiteOverride(.disabled, for: url)
        XCTAssertFalse(module.effectivePolicy(for: url).isEnabled)

        sitePolicyStore.removeSiteOverride(forNormalizedHost: "example.com")
        XCTAssertTrue(module.effectivePolicy(for: url).isEnabled)
    }

    func testAdblockSitePolicyDoesNotModifyTrackingProtectionPolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adblockSitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!

        trackingSettings.setGlobalMode(.enabled)
        trackingSettings.setSiteOverride(.enabled, for: url)
        adblockSitePolicyStore.setSiteOverride(.disabled, for: url)

        XCTAssertEqual(trackingSettings.override(for: url), .enabled)
        XCTAssertEqual(adblockSitePolicyStore.override(for: url), .disabled)
    }

    func testTrackingProtectionSitePolicyDoesNotModifyAdblockPolicy() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let trackingSettings = SumiTrackingProtectionSettings(userDefaults: harness.defaults)
        let adblockSitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!

        adblockSitePolicyStore.setSiteOverride(.disabled, for: url)
        trackingSettings.setSiteOverride(.disabled, for: url)

        XCTAssertEqual(adblockSitePolicyStore.override(for: url), .disabled)
        XCTAssertEqual(trackingSettings.override(for: url), .disabled)
    }

    func testGlobalDisabledIgnoresPerSiteAllowedWithoutCreatingRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.allowed, for: URL(string: "https://www.example.com"))
        var didCreateRuleListStore = false
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateRuleListStore = true
                return AdblockWebKitRuleListStore(settingsStore: settings, isAdblockEnabled: isEnabled)
            }
        )

        let decision = module.normalTabDecision(for: URL(string: "https://example.com"))

        XCTAssertEqual(decision.status, .disabled)
        XCTAssertFalse(decision.effectivePolicy.isEnabled)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertFalse(didCreateRuleListStore)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSiteDisabledPolicyPreventsRuleListAttachmentOnNormalTab() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        sitePolicyStore.setSiteOverride(.disabled, for: URL(string: "https://www.example.com/path"))
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: { sitePolicyStore }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/reload",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )

        tab.setupWebView()

        let controller = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        await controller.waitForContentBlockingAssetsInstalled()

        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 0)
        XCTAssertEqual(tab.adblockAppliedAttachmentState, SumiAdblockAttachmentState(siteHost: "example.com", isEnabled: false))
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPerSiteReEnabledPolicyAllowsRuleListAttachmentAfterManualReload() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let url = URL(string: "https://www.example.com/path")!
        sitePolicyStore.setSiteOverride(.disabled, for: url)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: url.absoluteString,
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let originalWebView = try XCTUnwrap(tab.existingWebView)
        let originalController = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        await originalController.waitForContentBlockingAssetsInstalled()
        XCTAssertEqual(originalController.contentBlockingAssetSummary.globalRuleListCount, 0)

        sitePolicyStore.setSiteOverride(.allowed, for: url)
        tab.markAdblockReloadRequiredIfNeeded(afterChangingOverrideFor: url)

        XCTAssertTrue(tab.isAdblockReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)

        XCTAssertTrue(
            tab.rebuildNormalWebViewForAdblockIfNeeded(
                targetURL: tab.url,
                reason: "SumiAdBlockingModuleTests.manualReload"
            )
        )
        let rebuiltController = try XCTUnwrap(
            tab.existingWebView?.configuration.userContentController.sumiNormalTabUserContentController
        )
        try await waitForAssets(on: rebuiltController) { $0.globalRuleListCount == 2 }
        tab.clearAdblockReloadRequirementIfResolved(for: tab.url)
        XCTAssertFalse(tab.isAdblockReloadRequired)
    }

    func testChangingAdblockPolicyMarksReloadRequiredWithoutAutoReload() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            adBlockingModule: module
        )
        let tab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/no-auto-reload",
            in: browserManager.tabManager.currentSpace,
            activate: false
        )
        tab.setupWebView()
        let originalWebView = try XCTUnwrap(tab.existingWebView)
        let controller = try XCTUnwrap(
            originalWebView.configuration.userContentController.sumiNormalTabUserContentController
        )
        try await waitForAssets(on: controller) { $0.globalRuleListCount == 2 }

        sitePolicyStore.setSiteOverride(.disabled, for: tab.url)
        tab.markAdblockReloadRequiredIfNeeded(afterChangingOverrideFor: tab.url)

        XCTAssertTrue(tab.isAdblockReloadRequired)
        XCTAssertTrue(tab.existingWebView === originalWebView)
        XCTAssertEqual(controller.contentBlockingAssetSummary.globalRuleListCount, 2)
    }

    func testDisablingAdblockRemovesRuleListsFromExistingController() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.adBlocking)
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let sitePolicyStore = AdblockSitePolicyStore(userDefaults: harness.defaults)
        let module = try await makeModuleWithSeededManifest(
            registry: registry,
            settings: settings,
            sitePolicyStore: sitePolicyStore
        )
        let service = try XCTUnwrap(
            module.normalTabDecision(for: URL(string: "https://example.com")).contentBlockingService
        )
        let controller = SumiNormalTabUserContentControllerFactory.makeController(
            contentBlockingServices: [service]
        )
        let normalController = try XCTUnwrap(controller.sumiNormalTabUserContentController)
        try await waitForAssets(on: normalController) { $0.globalRuleListCount == 2 }

        module.setEnabled(false)
        try await waitForAssets(on: normalController) { $0.globalRuleListCount == 0 }

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(normalController.contentBlockingAssetSummary.globalRuleListCount, 0)
    }

    func testAdBlockingModuleSourceHasNoRustWebExtensionUpdaterOrRuntimeScriptIntegration() throws {
        let source = try Self.source(named: "Sumi/ContentBlocking/SumiAdBlockingModule.swift")
        let compilerSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift")

        XCTAssertTrue(source.contains("SumiAdBlockingModuleStatus"))
        XCTAssertTrue(source.contains("enabledNativeContentBlocking"))
        XCTAssertTrue(source.contains("moduleRegistry.isEnabled(.adBlocking)"))

        for forbiddenPattern in [
            "adblock_rust",
            "adblock-rust",
            "EasyList",
            "EasyPrivacy",
            "SumiContentBlockingService.shared",
            "SumiTrackingProtectionModule",
            "SumiTrackingRuleListProvider",
            "SumiTrackingRuleListPipeline",
            "SumiTrackingContentBlockingAssets",
            "SumiTrackingProtectionSettings",
            "SumiTrackingProtectionDataStore",
            "SumiTrackerDataUpdater",
            "WKUserScript",
            "addUserScript",
            "addScriptMessageHandler",
            "URLSession",
            "Timer",
            "scheduledTimer",
        ] {
            XCTAssertFalse(source.contains(forbiddenPattern), forbiddenPattern)
        }

        XCTAssertTrue(compilerSource.contains("AdblockRustHelperExecutableAdapter"))
        XCTAssertTrue(compilerSource.contains("SUMI_ADBLOCK_RUST_ADAPTER"))
        XCTAssertTrue(compilerSource.contains("compileNativeAndEnhancedCompatibility"))
        XCTAssertFalse(compilerSource.contains("AdblockRustAdapterOutputCache"))
        XCTAssertFalse(compilerSource.contains("cachedOutput"))
        XCTAssertFalse(compilerSource.contains("networkContentRule(from:"))
        XCTAssertFalse(compilerSource.contains("cosmeticContentRule(from:"))
        XCTAssertFalse(compilerSource.contains("escapedLooseURLFilter"))
    }

    func testAdblockRustUsageIsIsolatedToCompilerBoundaryAndVendorAdapter() throws {
        let allowedPaths: Set<String> = [
            "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift",
            "Vendor/Brave/README.md",
            "Vendor/Brave/AdblockRustAdapter/Cargo.toml",
            "Vendor/Brave/AdblockRustAdapter/Cargo.lock",
            "Vendor/Brave/AdblockRustAdapter/src/main.rs",
            "LICENSE_NOTES.md",
        ]
        let output = try Self.runSourceSearch(
            pattern: "adblock-rust|adblock::|sumi-adblock-rust-adapter|SUMI_ADBLOCK_RUST_ADAPTER"
        )
        let unexpected = output
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line -> String? in
                guard let path = line.split(separator: ":", maxSplits: 1).first.map(String.init),
                      !allowedPaths.contains(path),
                      !path.hasPrefix("SumiTests/")
                else { return nil }
                return line
            }

        XCTAssertTrue(unexpected.isEmpty, unexpected.joined(separator: "\n"))
    }

    func testSafariConverterIsNotPresentedAsInAppCompilerWhileIntegrationIsDeferred() throws {
        let compilerSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockRustCompiler.swift")
        let updateSource = try Self.source(named: "Sumi/ContentBlocking/SumiAdblockUpdatePipeline.swift")
        let harnessSource = try Self.source(named: "scripts/compare_native_adblock_compilers.sh")

        XCTAssertFalse(compilerSource.contains("AdGuardSafariNativeContentBlockingCompiler"))
        XCTAssertTrue(updateSource.contains("externalHarnessOnly"))
        XCTAssertTrue(harnessSource.contains("\"external-harness-only\""))
    }

    func testNativeScoreProcedureDocumentsRequiredMeasurementState() throws {
        let readme = try Self.source(named: "SumiTests/Fixtures/Adblock/README.md")

        for required in [
            "https://d3ward.github.io/toolz/adblock.html",
            "https://adblock-tester.com/",
            "currentDefault",
            "balancedNative",
            "highBlockingNative",
            "referenceAdGuardNative",
            "Tracking Protection: disabled",
            "Enhanced runtime: disabled",
            "Active generation: present and not stale",
            "selected profile must match the active compiled profile",
            "attached network shard identifiers",
            "attached native CSS shard identifiers",
            "https://adblock.turtlecute.org/",
            "do not use adblock-tester.com as the primary score page",
            "Rule cap/discard state",
            "Date and local time of measurement",
            "attachmentDiagnosticsReport(for:)",
            "Do not claim an improved score",
        ] {
            XCTAssertTrue(readme.contains(required), required)
        }
    }

    func testAuxiliarySourcesDoNotConsultAdBlockingModule() throws {
        for relativePath in [
            "Sumi/UserScripts/SumiNormalTabUserScripts.swift",
            "Sumi/Managers/GlanceManager/GlanceWebView.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Favicons/DDG/Model/FaviconDownloader.swift",
        ] {
            let source = try Self.source(named: relativePath)
            XCTAssertFalse(source.contains("adBlockingModule"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingModule"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingAssets"), relativePath)
            XCTAssertFalse(source.contains("SumiAdBlockingNormalTabDecision"), relativePath)
        }
    }

    private func assertNoAdBlockingScriptsOrHandlers(
        in userContentController: WKUserContentController,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let wkSources = userContentController.userScripts
            .map(\.source)
            .joined(separator: "\n")
        let providerSources = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .map(\.source)
            .joined(separator: "\n") ?? ""
        let messageNames = userContentController.sumiNormalTabUserScriptsProvider?
            .userScripts
            .flatMap(\.messageNames)
            .joined(separator: "\n") ?? ""

        for marker in [
            "SumiAdBlocking",
            "sumiAdBlocking",
            "adBlocking",
            "ad-block",
            "adblock",
        ] {
            XCTAssertFalse(wkSources.contains(marker), marker, file: file, line: line)
            XCTAssertFalse(providerSources.contains(marker), marker, file: file, line: line)
            XCTAssertFalse(messageNames.contains(marker), marker, file: file, line: line)
        }
    }

    private func makeTrackingDataStore(defaults: UserDefaults) -> SumiTrackingProtectionDataStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiAdBlockingTrackingData-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return SumiTrackingProtectionDataStore(
            userDefaults: defaults,
            storageDirectory: directory
        )
    }

    private func temporaryAdblockDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiAdBlockingHybrid-\(UUID().uuidString)",
                isDirectory: true
            )
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeModuleWithSeededManifest(
        registry: SumiModuleRegistry,
        settings: AdblockSettingsStore,
        sitePolicyStore: AdblockSitePolicyStore
    ) async throws -> SumiAdBlockingModule {
        let manifestStore = AdblockUpdateManifestStore(
            rootDirectory: temporaryAdblockDirectory()
        )
        try await seedActiveManifest(in: manifestStore)
        return SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { settings },
            sitePolicyFactory: { sitePolicyStore },
            ruleListStoreFactory: { settings, isEnabled in
                AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler()
                )
            }
        )
    }

    private func seedActiveManifest(in store: AdblockUpdateManifestStore) async throws {
        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: "hybrid-test-generation",
            createdDate: Date(),
            selectedFilterLists: [
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: "easylist",
                    displayName: "EasyList",
                    contentHash: "easylist-hash"
                ),
            ],
            networkShards: [
                NativeContentBlockingShardDescriptor(
                    id: "network-0001",
                    generationId: "hybrid-test-generation",
                    kind: .network,
                    sourceListIdentifiers: ["easylist"],
                    sourceCategories: [.baseAds],
                    webKitIdentifier: "sumi.adblock.network.hybridtest",
                    contentHash: "network",
                    approximateRuleCount: 1,
                    jsonByteCount: 2,
                    compilerIdentity: NativeContentBlockingCompilerIdentity(
                        name: "adblock-rust",
                        version: "test"
                    ),
                    profileIdentity: nil,
                    diagnosticsSummary: "test"
                ),
            ],
            nativeCSSShards: [
                NativeContentBlockingShardDescriptor(
                    id: "nativeCSS-0001",
                    generationId: "hybrid-test-generation",
                    kind: .nativeCosmeticCSS,
                    sourceListIdentifiers: ["easylist"],
                    sourceCategories: [.baseAds],
                    webKitIdentifier: "sumi.adblock.nativeCSS.hybridtest",
                    contentHash: "css",
                    approximateRuleCount: 1,
                    jsonByteCount: 2,
                    compilerIdentity: NativeContentBlockingCompilerIdentity(
                        name: "adblock-rust",
                        version: "test"
                    ),
                    profileIdentity: nil,
                    diagnosticsSummary: "test"
                ),
            ],
            enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle(
                resources: [
                    AdblockEnhancedResource(
                        name: "sumi-hide",
                        kind: .scriptlet,
                        sourceRule: "example.com##+js(sumi-hide, .enhanced-ad)"
                    ),
                ],
                scriptletInvocations: [
                    AdblockScriptletInvocation(
                        resourceName: "sumi-hide",
                        parameters: [".enhanced-ad"],
                        includeDomains: ["example.com"],
                        excludeDomains: [],
                        sourceRule: "example.com##+js(sumi-hide, .enhanced-ad)",
                        diagnosticSource: "test manifest"
                    ),
                ],
                unsupportedDiagnostics: []
            ),
            nativeProfile: .currentDefault,
            nativeCompiler: NativeContentBlockingCompilerIdentity(
                name: "adblock-rust",
                version: "test"
            ),
            nativeCompilerSourceLists: [
                NativeContentBlockingSourceList(
                    id: "easylist",
                    displayName: "EasyList",
                    contentHash: "easylist-hash"
                ),
            ],
            compilerDiagnosticsSummary: "nativeCSSConverted=1; unsafeNativeCSSRootSelectorsFiltered=2; ruleCapHit=false; discarded=0",
            lastSuccessfulUpdateDate: Date(),
            previousGenerationId: nil
        )
        let stagingDirectory = try await store.beginStaging()
        var stagedCompiledShardURLs = [String: URL]()
        for shard in manifest.allNativeShards {
            let url = stagingDirectory.appendingPathComponent("\(shard.id).json")
            try Data(Self.fixtureCompiledShardJSON.utf8).write(to: url)
            stagedCompiledShardURLs[shard.id] = url
        }
        try await store.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:],
            stagedCompiledShardURLs: stagedCompiledShardURLs
        )
    }

    private static func contentRule(
        action: String,
        urlFilter: String,
        selector: String? = nil
    ) -> AdblockRustContentRule {
        var actionPayload: [String: JSONObject] = ["type": .string(action)]
        if let selector {
            actionPayload["selector"] = .string(selector)
        }
        return AdblockRustContentRule(
            action: .object(actionPayload),
            trigger: .object(["url-filter": .string(urlFilter)])
        )
    }

    private static func validRuleListDefinition() -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: "SumiAdBlockingSeparationTrackingRules-\(UUID().uuidString)",
            encodedContentRuleList: """
            [
              {
                "trigger": {
                  "url-filter": ".*tracking-separation-blocked\\\\.example/.*"
                },
                "action": {
                  "type": "block"
                }
              }
            ]
            """
        )
    }

    @discardableResult
    private func waitForAssets(
        on controller: SumiNormalTabUserContentControlling,
        where predicate: @escaping (SumiNormalTabContentBlockingAssetSummary) -> Bool
    ) async throws -> SumiNormalTabContentBlockingAssetSummary {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let summary = controller.contentBlockingAssetSummary
            if summary.isInstalled, predicate(summary) {
                return summary
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for content-blocking assets")
        return controller.contentBlockingAssetSummary
    }

    private func waitForActiveAdblockGeneration(
        in module: SumiAdBlockingModule,
        url: URL? = URL(string: "https://example.com")
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if module.attachmentDiagnostics(for: url).hasActiveGeneration {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for active Adblock generation")
    }

    private static func source(named relativePath: String) throws -> String {
        let sourceURL = repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func runSourceSearch(pattern: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["rg", "-n", "--glob", "!Vendor/Brave/AdblockRustAdapter/target/**", pattern]
        process.currentDirectoryURL = repoRoot()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodedRuleList(_ encoded: String) throws -> [[String: Any]] {
        let data = Data(encoded.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    private static let tinyFixtureFiltersWithUnsupportedRule =
        AdblockWebKitRuleListStore.tinyFixtureFilters + ["example.com##+js(sumi-future-scriptlet)"]

    private static let fixtureCompiledShardJSON = """
    [
      {
        "trigger": {
          "url-filter": ".*ads\\\\.example/.*"
        },
        "action": {
          "type": "block"
        }
      },
      {
        "trigger": {
          "url-filter": ".*"
        },
        "action": {
          "type": "css-display-none",
          "selector": ".ad-banner"
        }
      }
    ]
    """
}

private actor CountingAdblockRustAdapter: AdblockRustAdapterInvoking {
    private(set) var callCount = 0
    private let output: AdblockRustAdapterOutput

    init(output: AdblockRustAdapterOutput) {
        self.output = output
    }

    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput {
        callCount += 1
        return output
    }
}

private extension AdblockRustAdapterOutput {
    static let tinyFixture = AdblockRustAdapterOutput(
        network: [
            AdblockRustContentRule(
                action: .object(["type": .string("block")]),
                trigger: .object(["url-filter": .string("^[^:]+:(//)?([^/]+\\\\.)?ads\\\\.example\\\\.test")])
            ),
        ],
        nativeCosmeticCSS: [
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string(".ad-banner"),
                ]),
                trigger: .object(["url-filter": .string(".*")])
            ),
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string(".sponsored"),
                ]),
                trigger: .object([
                    "url-filter": .string(".*"),
                    "if-domain": .array([.string("example.test")]),
                ])
            ),
            AdblockRustContentRule(
                action: .object([
                    "type": .string("css-display-none"),
                    "selector": .string("#sponsor.card[data-ad=\"1\"]"),
                ]),
                trigger: .object([
                    "url-filter": .string(".*"),
                    "if-domain": .array([.string("example.test")]),
                ])
            ),
        ],
        unsupportedOrIgnored: [
            AdblockRustAdapterDiagnostic(
                rule: "example.com##+js(sumi-future-scriptlet)",
                reason: "unsupported by adblock-rust content-blocking conversion: ScriptletInjectionsNotSupported"
            ),
        ],
        enhancedResourceCandidates: [
            AdblockRustEnhancedResourceCandidate(
                kind: .scriptlet,
                resourceName: "sumi-future-scriptlet",
                parameters: [],
                includeDomains: ["example.com"],
                excludeDomains: [],
                sourceRule: "example.com##+js(sumi-future-scriptlet)",
                diagnosticSource: "test adapter"
            ),
        ]
    )
}
