import XCTest

@testable import Sumi

@MainActor
final class SumiProtectionAttachmentOwnerTests: XCTestCase {
    func testOffPlanDoesNotTouchManifestRulesOrServiceFactory() async throws {
        let provider = FakeProtectionAttachmentRuleProvider()
        var serviceFactoryCallCount = 0
        let owner = SumiProtectionAttachmentOwner(
            ruleProvider: provider,
            contentBlockingServiceFactory: {
                serviceFactoryCallCount += 1
                return SumiContentBlockingService(policy: .disabled)
            }
        )

        let plan = owner.cachedRulePlan(
            for: URL(string: "https://example.com"),
            profileId: nil,
            requestedLevel: .off
        )
        try await owner.prepareCachedAttachmentService(for: .off)

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
            name: "sumi.test.tracking.1",
            encodedContentRuleList: Self.validRuleListJSON,
            storeIdentifierOverride: "sumi.test.tracking.1"
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
        let owner = SumiProtectionAttachmentOwner(
            ruleProvider: provider,
            contentBlockingServiceFactory: {
                SumiContentBlockingService(policy: .disabled, compiler: compiler)
            }
        )

        try await owner.prepareCachedAttachmentService(for: .protection)
        let decision = owner.normalTabDecision(
            for: URL(string: "https://example.com/article"),
            profileId: nil,
            requestedLevel: .protection
        )

        XCTAssertEqual(provider.ruleDefinitionCallCount, 0)
        XCTAssertEqual(decision.plan.activeGroups, [.trackingNetwork])
        XCTAssertEqual(decision.plan.expectedRuleListIdentifiers, [ruleList.webKitStoreIdentifier])
        XCTAssertEqual(
            decision.contentBlockingService?.latestRuleListIdentifiers,
            [ruleList.webKitStoreIdentifier]
        )
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
        let shard = NativeContentBlockingShardDescriptor(
            id: "tracking-0001",
            generationId: "generation-1",
            kind: .network,
            sourceListIdentifiers: ["tracking"],
            sourceCategories: [.privacyOverlap],
            protectionGroup: .trackingNetwork,
            webKitIdentifier: ruleList.webKitStoreIdentifier,
            contentHash: ruleList.contentHash,
            approximateRuleCount: 1,
            jsonByteCount: ruleList.encodedContentRuleList.utf8.count,
            compilerIdentity: nil,
            diagnosticsSummary: "test"
        )
        return AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: "generation-1",
            createdDate: Date(timeIntervalSince1970: 0),
            selectedFilterLists: [],
            networkShards: [shard],
            nativeCSSShards: [],
            nativeCompiler: nil,
            nativeCompilerSourceLists: nil,
            nativeLogicalGroups: nil,
            nativeCompilationSummary: nil,
            compilerDiagnosticsSummary: "test",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1),
            previousGenerationId: nil,
            generationSource: .embeddedBundle,
            nativeRuleBundleId: "bundle-\(SumiProtectionBundleProfile.adblock)",
            bundleProfileId: SumiProtectionBundleProfile.adblock
        )
    }
}

@MainActor
private final class FakeProtectionAttachmentRuleProvider: SumiProtectionAttachmentRuleProviding {
    var isEnabled = false
    var activeManifestCallCount = 0
    var ruleDefinitionCallCount = 0
    var siteOverrideCallCount = 0
    var enabledUpdates: [Bool] = []
    var preparedBundleRuntimeUpdates: [Bool] = []

    private let manifest: AdblockCompiledGenerationManifest?
    private let definitions: [SumiContentRuleListDefinition]

    init(
        manifest: AdblockCompiledGenerationManifest? = nil,
        definitions: [SumiContentRuleListDefinition] = []
    ) {
        self.manifest = manifest
        self.definitions = definitions
    }

    func setEnabled(_ isEnabled: Bool) {
        self.isEnabled = isEnabled
        enabledUpdates.append(isEnabled)
    }

    func setPreparedBundleRuntimeEnabled(_ isEnabled: Bool) {
        preparedBundleRuntimeUpdates.append(isEnabled)
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
