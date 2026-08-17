import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ProtectionAttachmentServiceTests: XCTestCase {
    func testRuntimeLevelSynchronizationIsOneAtomicTransition() {
        let provider = FakeProtectionAttachmentRuleProvider()
        let service = ProtectionAttachmentService(
            ruleProvider: provider,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
        )

        service.syncRuntime(for: .adblock)
        service.syncRuntime(for: .off)

        XCTAssertEqual(provider.runtimeLevelUpdates, [.adblock, .off])
    }

    func testOffPlanDoesNotTouchManifestRulesOrServiceFactory() async throws {
        let provider = FakeProtectionAttachmentRuleProvider()
        var serviceFactoryCallCount = 0
        let service = ProtectionAttachmentService(
            ruleProvider: provider,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog(),
            contentBlockingServiceFactory: {
                serviceFactoryCallCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )

        let plan = service.cachedRulePlan(
            for: URL(string: "https://example.com"),
            requestedLevel: .off
        )
        try await service.prepareCachedAttachmentService(for: .off)

        XCTAssertEqual(plan.requestedLevel, .off)
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertTrue(plan.activeGroups.isEmpty)
        XCTAssertEqual(provider.activeManifestCallCount, 0)
        XCTAssertEqual(provider.ruleDefinitionCallCount, 0)
        XCTAssertEqual(provider.siteOverrideCallCount, 0)
        XCTAssertEqual(serviceFactoryCallCount, 0)
    }

    func testPrepareCachedAttachmentServiceUsesMetadataOnlyRestoreWhenCompiledRuleListExists() async throws {
        let ruleList = SumiContentRuleListDefinition(
            name: "sumi.test.adblock.1",
            encodedContentRuleList: Self.validRuleListJSON,
            storeIdentifierOverride: "sumi.test.adblock.1"
        )
        let provider = FakeProtectionAttachmentRuleProvider(
            manifest: Self.makeManifest(ruleList: ruleList),
            definitions: [ruleList]
        )
        let compiler = SumiWKContentRuleListCompiler()
        _ = try await compiler.compileContentRuleList(
            forIdentifier: ruleList.webKitStoreIdentifier,
            encodedContentRuleList: ruleList.encodedContentRuleList
        )
        let service = ProtectionAttachmentService(
            ruleProvider: provider,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog(),
            contentBlockingServiceFactory: {
                SumiContentBlockingService(policy: .disabled, compiler: compiler)
            }
        )

        try await service.prepareCachedAttachmentService(for: .adblock)
        let decision = service.normalTabDecision(
            for: URL(string: "https://example.com/article"),
            requestedLevel: .adblock
        )

        XCTAssertEqual(provider.ruleDefinitionCallCount, 0)
        XCTAssertEqual(decision.plan.activeGroups, [.adblockAdsPrivacyNetwork])
        XCTAssertEqual(decision.plan.expectedRuleListIdentifiers, [ruleList.webKitStoreIdentifier])
        XCTAssertEqual(
            decision.contentBlockingService?.latestRuleListIdentifiers,
            [ruleList.webKitStoreIdentifier]
        )
    }

    func testAdblockReadinessDoesNotRequireSeparateTrackingGroup() {
        let ruleList = SumiContentRuleListDefinition(
            name: "sumi.test.adblock.1",
            encodedContentRuleList: Self.validRuleListJSON,
            storeIdentifierOverride: "sumi.test.adblock.1"
        )
        let provider = FakeProtectionAttachmentRuleProvider(
            manifest: Self.makeManifest(
                ruleLists: [(ruleList, .adblockAdsPrivacyNetwork)]
            ),
            definitions: [ruleList]
        )
        let service = ProtectionAttachmentService(
            ruleProvider: provider,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
        )
        let plan = service.globalAttachmentPlan(
            for: .adblock,
            loadRuleDefinitions: false
        )

        XCTAssertEqual(plan.activeGroups, [.adblockAdsPrivacyNetwork])
        XCTAssertNoThrow(try service.validateRequiredGroupsReady(in: plan))
    }

    private static var validRuleListJSON: String {
        """
        [
          {
            "trigger": {
              "url-filter": ".*example\\\\.com/.*"
            },
            "action": {
              "type": "block"
            }
          }
        ]
        """
    }

    private static func makeManifest(
        ruleList: SumiContentRuleListDefinition
    ) -> AdblockCompiledGenerationManifest {
        makeManifest(ruleLists: [(ruleList, .adblockAdsPrivacyNetwork)])
    }

    private static func makeManifest(
        ruleLists: [(definition: SumiContentRuleListDefinition, group: SumiProtectionGroupKind)]
    ) -> AdblockCompiledGenerationManifest {
        let shards = ruleLists.enumerated().map { index, entry in
            NativeContentBlockingShardDescriptor(
                id: "\(entry.group.rawValue)-\(String(format: "%04d", index + 1))",
                generationId: "generation-1",
                kind: .network,
                protectionGroup: entry.group,
                webKitIdentifier: entry.definition.webKitStoreIdentifier,
                contentHash: entry.definition.contentHash,
                approximateRuleCount: 1,
                jsonByteCount: entry.definition.encodedContentRuleList.utf8.count
            )
        }
        return AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: "generation-1",
            selectedFilterLists: [],
            networkShards: shards,
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1),
            previousGenerationId: nil,
            bundleProfileId: SumiProtectionBundleProfile.adblock
        )
    }
}

@MainActor
private final class FakeProtectionAttachmentRuleProvider: ProtectionAttachmentRuleProviding {
    var activeManifestCallCount = 0
    var ruleDefinitionCallCount = 0
    var siteOverrideCallCount = 0
    var runtimeLevelUpdates: [SumiProtectionLevel] = []

    private let manifest: AdblockCompiledGenerationManifest?
    private let definitions: [SumiContentRuleListDefinition]

    init(
        manifest: AdblockCompiledGenerationManifest? = nil,
        definitions: [SumiContentRuleListDefinition] = []
    ) {
        self.manifest = manifest
        self.definitions = definitions
    }

    func setRuntimeLevel(_ level: SumiProtectionLevel) {
        runtimeLevelUpdates.append(level)
    }

    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest? {
        activeManifestCallCount += 1
        return manifest
    }

    func contentRuleListDefinitions(
        for protectionGroups: Set<SumiProtectionGroupKind>
    ) -> [SumiContentRuleListDefinition] {
        ruleDefinitionCallCount += 1
        return definitions.filter { definition in
            guard let shard = manifest?.networkShards.first(where: {
                $0.webKitIdentifier == definition.webKitStoreIdentifier
            }) else { return false }
            return shard.protectionGroup.map { protectionGroups.contains($0) } ?? false
        }
    }

    func siteOverride(for _: URL?) -> SumiAdblockSiteOverride {
        siteOverrideCallCount += 1
        return .inherit
    }
}
