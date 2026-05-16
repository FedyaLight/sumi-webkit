import CryptoKit
import Foundation

enum AdblockCompiledRuleGroupKind: String, Codable, CaseIterable, Hashable, Sendable {
    case network
    case nativeCosmeticCSS
}

enum AdblockRuntimeCapability: String, Codable, CaseIterable, Sendable {
    case webKitNativeNetwork
    case webKitNativeCSS
    case enhancedCosmeticCleanup
    case scriptletResourceCandidate
    case redirectResourceCandidate
}

struct AdblockNativeRuleGroups: Equatable, Sendable {
    let network: AdblockCompiledRuleGroup?
    let nativeCosmeticCSS: AdblockCompiledRuleGroup?
}

struct NativeContentBlockingShardStrategy: Codable, Equatable, Sendable {
    let maxRulesPerShard: Int
    let maxJSONBytesPerShard: Int

    static let conservativeDefault = NativeContentBlockingShardStrategy(
        maxRulesPerShard: 25_000,
        maxJSONBytesPerShard: 3_000_000
    )
}

struct AdblockEnhancedResource: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cosmeticCleanup
        case scriptlet
        case redirect
        case noopRedirect
    }

    let name: String
    let kind: Kind
    let sourceRule: String
}

enum AdblockRedirectResourceKind: String, Codable, Sendable {
    case script
    case stylesheet
    case image
    case document
    case text
    case unknown
    case unsupported
}

struct AdblockRedirectResourceCandidate: Codable, Equatable, Sendable {
    let requestedName: String
    let canonicalName: String
    let alias: String?
    let resourceKind: AdblockRedirectResourceKind
    let mimeType: String?
    let includeDomains: [String]
    let excludeDomains: [String]
    let sourceRule: String
    let diagnosticSource: String
    let unsupportedReason: String?
    let matchedTrustedBundledResource: Bool
}

struct AdblockScriptletInvocation: Codable, Equatable, Sendable {
    let resourceName: String
    let parameters: [String]
    let includeDomains: [String]
    let excludeDomains: [String]
    let sourceRule: String
    let diagnosticSource: String
}

struct AdblockUnsupportedRuleDiagnostic: Equatable, Sendable {
    let rule: String
    let reason: String
}

struct AdblockEnhancedRuntimeBundle: Codable, Equatable, Sendable {
    let resources: [AdblockEnhancedResource]
    let scriptletInvocations: [AdblockScriptletInvocation]
    let redirectResourceCandidates: [AdblockRedirectResourceCandidate]
    let unsupportedDiagnostics: [AdblockUnsupportedRuleDiagnostic]

    init(
        resources: [AdblockEnhancedResource],
        scriptletInvocations: [AdblockScriptletInvocation] = [],
        redirectResourceCandidates: [AdblockRedirectResourceCandidate] = [],
        unsupportedDiagnostics: [AdblockUnsupportedRuleDiagnostic]
    ) {
        self.resources = resources
        self.scriptletInvocations = scriptletInvocations
        self.redirectResourceCandidates = redirectResourceCandidates
        self.unsupportedDiagnostics = unsupportedDiagnostics
    }

    var isAvailable: Bool {
        !resources.isEmpty || !scriptletInvocations.isEmpty || !redirectResourceCandidates.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case resources
        case scriptletInvocations
        case redirectResourceCandidates
        case unsupportedDiagnostics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resources = try container.decode([AdblockEnhancedResource].self, forKey: .resources)
        scriptletInvocations = try container.decodeIfPresent(
            [AdblockScriptletInvocation].self,
            forKey: .scriptletInvocations
        ) ?? []
        redirectResourceCandidates = try container.decodeIfPresent(
            [AdblockRedirectResourceCandidate].self,
            forKey: .redirectResourceCandidates
        ) ?? []
        unsupportedDiagnostics = try container.decodeIfPresent(
            [AdblockUnsupportedRuleDiagnostic].self,
            forKey: .unsupportedDiagnostics
        ) ?? []
    }
}

extension AdblockEnhancedResource: Codable {}
extension AdblockUnsupportedRuleDiagnostic: Codable {}

struct AdblockHybridCompilationOutput: Equatable, Sendable {
    let nativeRuleGroups: AdblockNativeRuleGroups
    let enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle
    let capabilities: Set<AdblockRuntimeCapability>
}

struct NativeContentBlockingCompilerIdentity: Codable, Equatable, Sendable {
    let name: String
    let version: String
}

struct NativeContentBlockingSourceList: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let contentHash: String
    let category: AdblockFilterListCategory?
    let inputByteCount: Int?
    let approximateRuleCount: Int?

    init(
        id: String,
        displayName: String,
        contentHash: String,
        category: AdblockFilterListCategory? = nil,
        inputByteCount: Int? = nil,
        approximateRuleCount: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.contentHash = contentHash
        self.category = category
        self.inputByteCount = inputByteCount
        self.approximateRuleCount = approximateRuleCount
    }
}

struct AdblockCompilationInput: Equatable, Sendable {
    let sourceIdentifier: String
    let generationId: String?
    let nativeProfile: AdblockFilterListProfileKind?
    let filterTexts: [String]
    let selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>
    let sourceLists: [NativeContentBlockingSourceList]
    let shardStrategy: NativeContentBlockingShardStrategy

    init(
        sourceIdentifier: String,
        generationId: String? = nil,
        nativeProfile: AdblockFilterListProfileKind? = nil,
        filterTexts: [String],
        selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>,
        sourceLists: [NativeContentBlockingSourceList] = [],
        shardStrategy: NativeContentBlockingShardStrategy = .conservativeDefault
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.generationId = generationId
        self.nativeProfile = nativeProfile
        self.filterTexts = filterTexts
        self.selectedOutputGroups = selectedOutputGroups
        self.sourceLists = sourceLists
        self.shardStrategy = shardStrategy
    }
}

struct AdblockCompilationDiagnostics: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let rule: String
        let reason: String
    }

    var unsupportedRules: [Entry] = []
    var ignoredRules: [Entry] = []
    var filteredUnsafeNativeCosmeticSelectors: [Entry] = []
    var nativeCosmeticRuleCount = 0
    var unsupportedCosmeticRuleCount = 0
    var ignoredScriptletOrProceduralRuleCount = 0
    var isNativeCosmeticGroupEmpty = true
    var ruleCap = NativeContentBlockingRuleCapDiagnostics.none
}

struct NativeContentBlockingRuleCapDiagnostics: Codable, Equatable, Sendable {
    struct SourcePressure: Codable, Equatable, Sendable {
        let listIdentifier: String
        let approximateRuleCount: Int
        let inputByteCount: Int
    }

    let configuredRuleLimit: Int?
    let wasHit: Bool
    let discardedRuleCount: Int
    let sourcePressure: [SourcePressure]

    static let none = NativeContentBlockingRuleCapDiagnostics(
        configuredRuleLimit: nil,
        wasHit: false,
        discardedRuleCount: 0,
        sourcePressure: []
    )
}

struct NativeContentBlockingCompilationSummary: Codable, Equatable, Sendable {
    let inputRuleCount: Int
    let inputByteCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let networkJSONByteCount: Int
    let nativeCosmeticJSONByteCount: Int
    let totalJSONByteCount: Int
    let ruleCap: NativeContentBlockingRuleCapDiagnostics
}

struct AdblockCompiledRuleGroup: Equatable, Sendable {
    let kind: AdblockCompiledRuleGroupKind
    let name: String
    let encodedContentRuleList: String
    let convertedRuleCount: Int
    let contentHash: String

    var definition: SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: name,
            encodedContentRuleList: encodedContentRuleList
        )
    }
}

struct NativeContentBlockingShardDescriptor: Codable, Equatable, Sendable {
    let id: String
    let generationId: String
    let kind: AdblockCompiledRuleGroupKind
    let sourceListIdentifiers: [String]
    let sourceCategories: [AdblockFilterListCategory]
    let webKitIdentifier: String
    let contentHash: String
    let approximateRuleCount: Int
    let jsonByteCount: Int
    let compilerIdentity: NativeContentBlockingCompilerIdentity?
    let profileIdentity: AdblockFilterListProfileKind?
    let diagnosticsSummary: String
}

struct NativeContentBlockingCompiledShard: Equatable, Sendable {
    let descriptor: NativeContentBlockingShardDescriptor
    let encodedContentRuleList: String
    let convertedRuleCount: Int

    var kind: AdblockCompiledRuleGroupKind { descriptor.kind }

    var definition: SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: descriptor.webKitIdentifier,
            encodedContentRuleList: encodedContentRuleList,
            storeIdentifierOverride: descriptor.webKitIdentifier
        )
    }

    var legacyGroup: AdblockCompiledRuleGroup {
        AdblockCompiledRuleGroup(
            kind: descriptor.kind,
            name: descriptor.webKitIdentifier,
            encodedContentRuleList: encodedContentRuleList,
            convertedRuleCount: convertedRuleCount,
            contentHash: descriptor.contentHash
        )
    }
}

struct NativeContentBlockingCompilationOutput: Equatable, Sendable {
    let sourceIdentifier: String
    let networkShards: [NativeContentBlockingCompiledShard]
    let nativeCosmeticCSSShards: [NativeContentBlockingCompiledShard]
    let diagnostics: AdblockCompilationDiagnostics
    let inputRuleCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let contentHash: String
    let compilerIdentity: NativeContentBlockingCompilerIdentity
    let sourceLists: [NativeContentBlockingSourceList]
    let nativeProfile: AdblockFilterListProfileKind?
    let shardStrategy: NativeContentBlockingShardStrategy

    var shards: [NativeContentBlockingCompiledShard] {
        networkShards + nativeCosmeticCSSShards
    }

    var groups: [AdblockCompiledRuleGroup] {
        shards.map(\.legacyGroup)
    }

    var nativeRuleGroups: AdblockNativeRuleGroups {
        AdblockNativeRuleGroups(
            network: groups.first { $0.kind == .network },
            nativeCosmeticCSS: groups.first { $0.kind == .nativeCosmeticCSS }
        )
    }

    var ruleListDefinitions: [SumiContentRuleListDefinition] {
        shards.map(\.definition)
    }

    var networkJSONByteCount: Int {
        networkShards.reduce(0) { $0 + $1.descriptor.jsonByteCount }
    }

    var nativeCosmeticJSONByteCount: Int {
        nativeCosmeticCSSShards.reduce(0) { $0 + $1.descriptor.jsonByteCount }
    }

    var totalJSONByteCount: Int {
        networkJSONByteCount + nativeCosmeticJSONByteCount
    }
}

struct EnhancedCompatibilityCompilationOutput: Equatable, Sendable {
    let enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle
    let capabilities: Set<AdblockRuntimeCapability>
}

struct AdblockCompilationOutput: Equatable, Sendable {
    let sourceIdentifier: String
    let groups: [AdblockCompiledRuleGroup]
    let hybridOutput: AdblockHybridCompilationOutput
    let diagnostics: AdblockCompilationDiagnostics
    let inputRuleCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let contentHash: String

    var ruleListDefinitions: [SumiContentRuleListDefinition] {
        groups.map(\.definition)
    }
}

protocol NativeContentBlockingCompiler: AnyObject, Sendable {
    var identity: NativeContentBlockingCompilerIdentity { get }

    func compileNativeContentBlocking(
        _ input: AdblockCompilationInput
    ) async throws -> NativeContentBlockingCompilationOutput
}

protocol EnhancedCompatibilityCompiler: AnyObject, Sendable {
    func compileEnhancedCompatibility(
        _ input: AdblockCompilationInput
    ) async throws -> EnhancedCompatibilityCompilationOutput
}

protocol AdblockFilterCompiling: AnyObject, Sendable {
    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput
}

final class AdblockRustCompiler: AdblockFilterCompiling, NativeContentBlockingCompiler, EnhancedCompatibilityCompiler, Sendable {
    let identity = NativeContentBlockingCompilerIdentity(
        name: "adblock-rust",
        version: AdblockRustHelperExecutableAdapter.adapterVersion
    )

    private let adapter: any AdblockRustAdapterInvoking
    private let outputCache = AdblockRustAdapterOutputCache()

    init(adapter: any AdblockRustAdapterInvoking = AdblockRustHelperExecutableAdapter()) {
        self.adapter = adapter
    }

    func compile(_ input: AdblockCompilationInput) async throws -> AdblockCompilationOutput {
        let normalizedRules = Self.normalizedRules(from: input.filterTexts)
        let adapterOutput = try await adapterOutput(for: normalizedRules)
        let nativeOutput = try Self.makeNativeOutput(
            input: input,
            normalizedRules: normalizedRules,
            adapterOutput: adapterOutput,
            identity: identity
        )
        let enhancedOutput = Self.makeEnhancedOutput(adapterOutput: adapterOutput)
        return Self.makeOutput(
            nativeOutput: nativeOutput,
            enhancedOutput: enhancedOutput
        )
    }

    func compileNativeContentBlocking(
        _ input: AdblockCompilationInput
    ) async throws -> NativeContentBlockingCompilationOutput {
        let normalizedRules = Self.normalizedRules(from: input.filterTexts)
        let adapterOutput = try await adapterOutput(for: normalizedRules)
        return try Self.makeNativeOutput(
            input: input,
            normalizedRules: normalizedRules,
            adapterOutput: adapterOutput,
            identity: identity
        )
    }

    func compileEnhancedCompatibility(
        _ input: AdblockCompilationInput
    ) async throws -> EnhancedCompatibilityCompilationOutput {
        let normalizedRules = Self.normalizedRules(from: input.filterTexts)
        let adapterOutput = try await adapterOutput(for: normalizedRules)
        return Self.makeEnhancedOutput(adapterOutput: adapterOutput)
    }

    private func adapterOutput(for normalizedRules: [String]) async throws -> AdblockRustAdapterOutput {
        let cacheKey = Self.stableHash(normalizedRules.joined(separator: "\n"))
        if let cachedOutput = await outputCache.output(for: cacheKey) {
            return cachedOutput
        }
        let adapterOutput = try await adapter.compile(normalizedRules)
        await outputCache.store(adapterOutput, for: cacheKey)
        return adapterOutput
    }

    private static func makeNativeOutput(
        input: AdblockCompilationInput,
        normalizedRules: [String],
        adapterOutput: AdblockRustAdapterOutput,
        identity: NativeContentBlockingCompilerIdentity
    ) throws -> NativeContentBlockingCompilationOutput {
        try validateAdapterOutput(adapterOutput)
        let networkBlockCount = adapterOutput.network.countActions(named: "block")
        let sanitizedNativeCosmeticCSS = sanitizeNativeCosmeticCSSRules(adapterOutput.nativeCosmeticCSS)
        let nativeCosmeticCount = sanitizedNativeCosmeticCSS.rules.countActions(named: "css-display-none")
        let generationId = input.generationId ?? input.sourceIdentifier
        let networkShards = input.selectedOutputGroups.contains(.network)
            ? try makeCompiledShards(
                kind: .network,
                rules: adapterOutput.network,
                convertedActionName: "block",
                generationId: generationId,
                input: input,
                identity: identity
            )
            : []
        let nativeCosmeticCSSShards = input.selectedOutputGroups.contains(.nativeCosmeticCSS)
            ? try makeCompiledShards(
                kind: .nativeCosmeticCSS,
                rules: sanitizedNativeCosmeticCSS.rules,
                convertedActionName: "css-display-none",
                generationId: generationId,
                input: input,
                identity: identity
            )
            : []

        let unsupportedDiagnostics = adapterOutput.unsupportedOrIgnored.map {
            AdblockCompilationDiagnostics.Entry(rule: $0.rule, reason: $0.reason)
        }
        let unsupportedCosmeticCount = adapterOutput.unsupportedOrIgnored.filter {
            isCosmeticRule($0.rule)
        }.count
        let scriptletOrProceduralCount = adapterOutput.unsupportedOrIgnored.filter {
            isScriptletOrProceduralCosmeticRule($0.rule) || isScriptletOrProceduralReason($0.reason)
        }.count
        let ignoredRules = normalizedRules
            .filter { $0.hasPrefix("!") || $0.hasPrefix("[") }
            .map { AdblockCompilationDiagnostics.Entry(rule: $0, reason: "metadata or comment") }
        let diagnostics = AdblockCompilationDiagnostics(
            unsupportedRules: unsupportedDiagnostics,
            ignoredRules: ignoredRules,
            filteredUnsafeNativeCosmeticSelectors: sanitizedNativeCosmeticCSS.filteredSelectors,
            nativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedCosmeticRuleCount: unsupportedCosmeticCount,
            ignoredScriptletOrProceduralRuleCount: scriptletOrProceduralCount,
            isNativeCosmeticGroupEmpty: nativeCosmeticCount == 0,
            ruleCap: NativeContentBlockingRuleCapDiagnostics(
                configuredRuleLimit: nil,
                wasHit: false,
                discardedRuleCount: 0,
                sourcePressure: input.sourceLists.compactMap { source in
                    guard let approximateRuleCount = source.approximateRuleCount,
                          let inputByteCount = source.inputByteCount
                    else { return nil }
                    return NativeContentBlockingRuleCapDiagnostics.SourcePressure(
                        listIdentifier: source.id,
                        approximateRuleCount: approximateRuleCount,
                        inputByteCount: inputByteCount
                    )
                }
                .sorted { lhs, rhs in
                    lhs.approximateRuleCount == rhs.approximateRuleCount
                        ? lhs.listIdentifier < rhs.listIdentifier
                        : lhs.approximateRuleCount > rhs.approximateRuleCount
                }
            )
        )
        let contentHash = stableHash(
            (networkShards + nativeCosmeticCSSShards)
                .map(\.descriptor.contentHash)
                .joined(separator: ":")
        )

        return NativeContentBlockingCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            networkShards: networkShards,
            nativeCosmeticCSSShards: nativeCosmeticCSSShards,
            diagnostics: diagnostics,
            inputRuleCount: normalizedRules.count,
            convertedNetworkRuleCount: networkBlockCount,
            convertedNativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedOrIgnoredRuleCount: diagnostics.unsupportedRules.count + diagnostics.ignoredRules.count,
            contentHash: contentHash,
            compilerIdentity: identity,
            sourceLists: input.sourceLists,
            nativeProfile: input.nativeProfile,
            shardStrategy: input.shardStrategy
        )
    }

    private static func makeOutput(
        nativeOutput: NativeContentBlockingCompilationOutput,
        enhancedOutput: EnhancedCompatibilityCompilationOutput
    ) -> AdblockCompilationOutput {
        let hybridOutput = AdblockHybridCompilationOutput(
            nativeRuleGroups: nativeOutput.nativeRuleGroups,
            enhancedRuntimeBundle: enhancedOutput.enhancedRuntimeBundle,
            capabilities: enhancedOutput.capabilities.union(
                [
                    nativeOutput.convertedNetworkRuleCount > 0 ? .webKitNativeNetwork : nil,
                    nativeOutput.convertedNativeCosmeticRuleCount > 0 ? .webKitNativeCSS : nil,
                ].compactMap { $0 }
            )
        )

        return AdblockCompilationOutput(
            sourceIdentifier: nativeOutput.sourceIdentifier,
            groups: nativeOutput.groups,
            hybridOutput: hybridOutput,
            diagnostics: nativeOutput.diagnostics,
            inputRuleCount: nativeOutput.inputRuleCount,
            convertedNetworkRuleCount: nativeOutput.convertedNetworkRuleCount,
            convertedNativeCosmeticRuleCount: nativeOutput.convertedNativeCosmeticRuleCount,
            unsupportedOrIgnoredRuleCount: nativeOutput.unsupportedOrIgnoredRuleCount,
            contentHash: nativeOutput.contentHash
        )
    }

    private static func makeEnhancedOutput(
        adapterOutput: AdblockRustAdapterOutput
    ) -> EnhancedCompatibilityCompilationOutput {
        let enhancedResources = Array(
            adapterOutput.enhancedResourceCandidates
                .map(AdblockEnhancedResource.init(candidate:))
                .reduce(into: [String: AdblockEnhancedResource]()) { result, resource in
                    result["\(resource.kind.rawValue):\(resource.name):\(resource.sourceRule)"] = resource
                }
                .values
                .sorted { lhs, rhs in
                    lhs.sourceRule == rhs.sourceRule
                        ? lhs.name < rhs.name
                        : lhs.sourceRule < rhs.sourceRule
                }
        )
        let scriptletCandidates = adapterOutput.enhancedResourceCandidates.filter { candidate in
            candidate.kind == .scriptlet
        }
        let redirectCandidates = adapterOutput.enhancedResourceCandidates.filter { candidate in
            candidate.kind == .redirect || candidate.kind == .noopRedirect
        }
        let scriptletInvocations = scriptletCandidates
            .map(AdblockScriptletInvocation.init(candidate:))
            .sorted { lhs, rhs in
                if lhs.sourceRule == rhs.sourceRule {
                    return lhs.resourceName < rhs.resourceName
                }
                return lhs.sourceRule < rhs.sourceRule
            }
        let enhancedUnsupported = adapterOutput.unsupportedOrIgnored
            .filter { diagnostic in
                adapterOutput.enhancedResourceCandidates.contains { candidate in
                    candidate.sourceRule == diagnostic.rule
                } || isScriptletOrProceduralReason(diagnostic.reason)
            }
            .map { AdblockUnsupportedRuleDiagnostic(rule: $0.rule, reason: $0.reason) }
        let bundle = AdblockEnhancedRuntimeBundle(
            resources: enhancedResources,
            scriptletInvocations: scriptletInvocations,
            redirectResourceCandidates: redirectCandidates
                .map(AdblockRedirectResourceCandidate.init(candidate:))
                .sorted { lhs, rhs in
                    lhs.sourceRule == rhs.sourceRule
                        ? lhs.requestedName < rhs.requestedName
                        : lhs.sourceRule < rhs.sourceRule
                },
            unsupportedDiagnostics: enhancedUnsupported
        )
        let capabilities = Set(
            enhancedResources.map { resource in
                switch resource.kind {
                case .cosmeticCleanup:
                    return AdblockRuntimeCapability.enhancedCosmeticCleanup
                case .scriptlet:
                    return AdblockRuntimeCapability.scriptletResourceCandidate
                case .redirect, .noopRedirect:
                    return AdblockRuntimeCapability.redirectResourceCandidate
                }
            }
        )

        return EnhancedCompatibilityCompilationOutput(
            enhancedRuntimeBundle: bundle,
            capabilities: capabilities
        )
    }

    private static func normalizedRules(from filterTexts: [String]) -> [String] {
        filterTexts
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func encodedJSON(_ rules: [AdblockRustContentRule]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(rules)
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodedRuleJSON(_ rule: AdblockRustContentRule) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(rule)
        return String(decoding: data, as: UTF8.self)
    }

    private static func makeCompiledShards(
        kind: AdblockCompiledRuleGroupKind,
        rules: [AdblockRustContentRule],
        convertedActionName: String,
        generationId: String,
        input: AdblockCompilationInput,
        identity: NativeContentBlockingCompilerIdentity
    ) throws -> [NativeContentBlockingCompiledShard] {
        let ruleChunks = try deterministicChunks(
            from: rules,
            strategy: input.shardStrategy
        )
        let sourceListIdentifiers = input.sourceLists.map(\.id).sorted()
        let sourceCategories = Array(Set(input.sourceLists.compactMap(\.category)))
            .sorted { $0.rawValue < $1.rawValue }

        return try ruleChunks.enumerated().map { index, chunk in
            let encodedContentRuleList = try encodedJSON(chunk)
            let contentHash = stableHash(encodedContentRuleList)
            let shardIndex = index + 1
            let jsonByteCount = encodedContentRuleList.utf8.count
            let softLimitExceeded = jsonByteCount > input.shardStrategy.maxJSONBytesPerShard
            let descriptor = NativeContentBlockingShardDescriptor(
                id: shardId(kind: kind, index: shardIndex),
                generationId: generationId,
                kind: kind,
                sourceListIdentifiers: sourceListIdentifiers,
                sourceCategories: sourceCategories,
                webKitIdentifier: shardWebKitIdentifier(
                    kind: kind,
                    generationId: generationId,
                    shardIndex: shardIndex,
                    contentHash: contentHash
                ),
                contentHash: contentHash,
                approximateRuleCount: chunk.count,
                jsonByteCount: jsonByteCount,
                compilerIdentity: identity,
                profileIdentity: input.nativeProfile,
                diagnosticsSummary: [
                    "deterministicChunk",
                    "rules=\(chunk.count)",
                    "bytes=\(jsonByteCount)",
                    "softByteLimitExceeded=\(softLimitExceeded)",
                ].joined(separator: ";")
            )
            return NativeContentBlockingCompiledShard(
                descriptor: descriptor,
                encodedContentRuleList: encodedContentRuleList,
                convertedRuleCount: chunk.countActions(named: convertedActionName)
            )
        }
    }

    private static func deterministicChunks(
        from rules: [AdblockRustContentRule],
        strategy: NativeContentBlockingShardStrategy
    ) throws -> [[AdblockRustContentRule]] {
        guard !rules.isEmpty else { return [[]] }

        var chunks = [[AdblockRustContentRule]]()
        var currentChunk = [AdblockRustContentRule]()
        var currentEstimatedByteCount = 2

        for rule in rules {
            let encodedRuleByteCount = try encodedRuleJSON(rule).utf8.count
            let separatorByteCount = currentChunk.isEmpty ? 0 : 1
            let wouldExceedRuleLimit = currentChunk.count >= strategy.maxRulesPerShard
            let wouldExceedByteLimit = !currentChunk.isEmpty
                && currentEstimatedByteCount + separatorByteCount + encodedRuleByteCount > strategy.maxJSONBytesPerShard

            if wouldExceedRuleLimit || wouldExceedByteLimit {
                chunks.append(currentChunk)
                currentChunk = []
                currentEstimatedByteCount = 2
            }

            let actualSeparatorByteCount = currentChunk.isEmpty ? 0 : 1
            currentChunk.append(rule)
            currentEstimatedByteCount += actualSeparatorByteCount + encodedRuleByteCount
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return try chunks.flatMap { try splitChunkIfNeeded($0, strategy: strategy) }
    }

    private static func splitChunkIfNeeded(
        _ chunk: [AdblockRustContentRule],
        strategy: NativeContentBlockingShardStrategy
    ) throws -> [[AdblockRustContentRule]] {
        let encodedByteCount = try encodedJSON(chunk).utf8.count
        guard encodedByteCount > strategy.maxJSONBytesPerShard, chunk.count > 1 else {
            return [chunk]
        }
        let midpoint = chunk.count / 2
        let firstHalf = Array(chunk[..<midpoint])
        let secondHalf = Array(chunk[midpoint...])
        return try splitChunkIfNeeded(firstHalf, strategy: strategy)
            + splitChunkIfNeeded(secondHalf, strategy: strategy)
    }

    private static func shardId(kind: AdblockCompiledRuleGroupKind, index: Int) -> String {
        "\(kind.identifierComponent)-\(String(format: "%04d", index))"
    }

    private static func shardWebKitIdentifier(
        kind: AdblockCompiledRuleGroupKind,
        generationId: String,
        shardIndex: Int,
        contentHash: String
    ) -> String {
        "sumi.adblock.\(kind.identifierComponent).\(generationId).\(String(format: "%04d", shardIndex)).\(contentHash)"
    }

    private static func validateAdapterOutput(_ output: AdblockRustAdapterOutput) throws {
        try validateContentRules(output.network, groupName: "network") { actionType, _ in
            Set([
                "block",
                "block-cookies",
                "ignore-previous-rules",
                "make-https",
            ]).contains(actionType)
        }
        try validateContentRules(output.nativeCosmeticCSS, groupName: "nativeCosmeticCSS") { actionType, action in
            actionType == "css-display-none"
                && action["selector"]?.stringValue?.isEmpty == false
        }
    }

    private static func validateContentRules(
        _ rules: [AdblockRustContentRule],
        groupName: String,
        allowsAction: (String, [String: JSONObject]) -> Bool
    ) throws {
        for rule in rules {
            guard let action = rule.action.objectValue,
                  let actionType = action["type"]?.stringValue,
                  allowsAction(actionType, action)
            else {
                throw AdblockRustCompilerError.invalidAdapterOutput(
                    "\(groupName) contains unsupported WebKit action"
                )
            }
            guard let trigger = rule.trigger.objectValue,
                  trigger["url-filter"]?.stringValue?.isEmpty == false
            else {
                throw AdblockRustCompilerError.invalidAdapterOutput(
                    "\(groupName) contains a content rule without url-filter"
                )
            }
        }
    }

    private static func sanitizeNativeCosmeticCSSRules(
        _ rules: [AdblockRustContentRule]
    ) -> (rules: [AdblockRustContentRule], filteredSelectors: [AdblockCompilationDiagnostics.Entry]) {
        var sanitizedRules = [AdblockRustContentRule]()
        var filteredSelectors = [AdblockCompilationDiagnostics.Entry]()
        sanitizedRules.reserveCapacity(rules.count)

        for rule in rules {
            guard var action = rule.action.objectValue,
                  action["type"]?.stringValue == "css-display-none",
                  let selector = action["selector"]?.stringValue
            else {
                sanitizedRules.append(rule)
                continue
            }

            let selectorComponents = splitSelectorList(selector)
            let retainedSelectors = selectorComponents.filter { component in
                if targetsDocumentRootOrAppContainer(component) {
                    filteredSelectors.append(
                        AdblockCompilationDiagnostics.Entry(
                            rule: component,
                            reason: "unsafe native CSS root-container selector"
                        )
                    )
                    return false
                }
                return true
            }

            guard !retainedSelectors.isEmpty else {
                continue
            }

            if retainedSelectors.count == selectorComponents.count {
                sanitizedRules.append(rule)
            } else {
                action["selector"] = .string(retainedSelectors.joined(separator: ", "))
                sanitizedRules.append(
                    AdblockRustContentRule(
                        action: .object(action),
                        trigger: rule.trigger
                    )
                )
            }
        }

        return (sanitizedRules, filteredSelectors)
    }

    private static func targetsDocumentRootOrAppContainer(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let subject = rightmostSelectorCompound(in: trimmed)
        guard !subject.isEmpty else { return false }

        if isUnsafeRootSelectorSubject(subject, root: "html")
            || isUnsafeRootSelectorSubject(subject, root: "body")
            || isUnsafeRootSelectorSubject(subject, root: ":root") {
            return true
        }

        for appRoot in ["#app", "#root", "#__next", "#__nuxt"] {
            if subject == appRoot
                || subject.hasPrefix(appRoot + ".")
                || subject.hasPrefix(appRoot + "[")
                || (subject.hasPrefix(appRoot + ":") && !subject.hasPrefix(appRoot + "::")) {
                return true
            }
        }

        return false
    }

    private static func isUnsafeRootSelectorSubject(_ subject: String, root: String) -> Bool {
        guard subject.hasPrefix(root) else { return false }
        let suffix = subject.dropFirst(root.count)
        if suffix.isEmpty {
            return true
        }
        if suffix.hasPrefix("::") {
            return false
        }
        return suffix.hasPrefix(".")
            || suffix.hasPrefix("[")
            || suffix.hasPrefix(":")
    }

    private static func rightmostSelectorCompound(in selector: String) -> String {
        var depth = 0
        var quote: Character?
        var lastBoundary = selector.startIndex
        var index = selector.startIndex

        while index < selector.endIndex {
            let character = selector[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" {
                    index = selector.index(after: index)
                }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "(":
                    depth += 1
                case "]", ")":
                    depth = max(0, depth - 1)
                case ">", "+", "~":
                    if depth == 0 {
                        lastBoundary = selector.index(after: index)
                    }
                default:
                    if depth == 0, character.isWhitespace {
                        lastBoundary = selector.index(after: index)
                    }
                }
            }
            index = selector.index(after: index)
        }

        return String(selector[lastBoundary...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitSelectorList(_ selector: String) -> [String] {
        var parts = [String]()
        var depth = 0
        var quote: Character?
        var start = selector.startIndex
        var index = selector.startIndex

        while index < selector.endIndex {
            let character = selector[index]
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else if character == "\\" {
                    index = selector.index(after: index)
                }
            } else {
                switch character {
                case "\"", "'":
                    quote = character
                case "[", "(":
                    depth += 1
                case "]", ")":
                    depth = max(0, depth - 1)
                case "," where depth == 0:
                    let part = selector[start..<index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !part.isEmpty {
                        parts.append(part)
                    }
                    start = selector.index(after: index)
                default:
                    break
                }
            }
            index = selector.index(after: index)
        }

        let finalPart = selector[start..<selector.endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalPart.isEmpty {
            parts.append(finalPart)
        }
        return parts
    }

    private static func isCosmeticRule(_ rule: String) -> Bool {
        rule.contains("##") || rule.contains("#@#") || rule.contains("#?#") || rule.contains("#%#")
    }

    private static func isScriptletOrProceduralCosmeticRule(_ rule: String) -> Bool {
        rule.contains("##+js(")
            || rule.contains("#%#")
            || rule.contains(":has(")
            || rule.contains(":has-text(")
            || rule.contains(":matches-css(")
            || rule.contains(":xpath(")
            || rule.contains(":-abp-")
    }

    private static func isScriptletOrProceduralReason(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("scriptlet")
            || reason.localizedCaseInsensitiveContains("procedural")
            || reason.localizedCaseInsensitiveContains("generic script inject")
    }

    private static func stableHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

private extension AdblockCompiledRuleGroupKind {
    var identifierComponent: String {
        switch self {
        case .network:
            return "network"
        case .nativeCosmeticCSS:
            return "nativeCSS"
        }
    }
}

protocol AdblockRustAdapterInvoking: Sendable {
    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput
}

private actor AdblockRustAdapterOutputCache {
    private var cacheKey: String?
    private var cachedOutput: AdblockRustAdapterOutput?

    func output(for cacheKey: String) -> AdblockRustAdapterOutput? {
        guard self.cacheKey == cacheKey else { return nil }
        return cachedOutput
    }

    func store(_ output: AdblockRustAdapterOutput, for cacheKey: String) {
        self.cacheKey = cacheKey
        cachedOutput = output
    }
}

struct AdblockRustHelperExecutableAdapter: AdblockRustAdapterInvoking {
    static let adapterVersion = "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5"

    func compile(_ normalizedRules: [String]) async throws -> AdblockRustAdapterOutput {
        let helperURL = try Self.helperExecutableURL()
        return try await Task.detached(priority: .utility) {
            try Self.runHelper(at: helperURL, normalizedRules: normalizedRules)
        }.value
    }

    private static func runHelper(
        at helperURL: URL,
        normalizedRules: [String]
    ) throws -> AdblockRustAdapterOutput {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = helperURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(normalizedRules.joined(separator: "\n").utf8))
        try? inputPipe.fileHandleForWriting.close()

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errorOutput, as: UTF8.self)
            throw AdblockRustCompilerError.adapterFailed(status: process.terminationStatus, stderr: stderr)
        }

        return try JSONDecoder().decode(AdblockRustAdapterOutput.self, from: output)
    }

    private static func helperExecutableURL() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["SUMI_ADBLOCK_RUST_ADAPTER"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        let candidateBundles = [Bundle.main, Bundle(for: BundleMarker.self)]
        for bundle in candidateBundles {
            if let url = bundle.url(forAuxiliaryExecutable: "sumi-adblock-rust-adapter") {
                return url
            }
            if let executableURL = bundle.executableURL {
                let adjacentURL = executableURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("sumi-adblock-rust-adapter")
                if FileManager.default.isExecutableFile(atPath: adjacentURL.path) {
                    return adjacentURL
                }
            }
        }

        throw AdblockRustCompilerError.adapterNotFound
    }

    private final class BundleMarker {}
}

struct AdblockRustAdapterOutput: Decodable, Equatable, Sendable {
    let network: [AdblockRustContentRule]
    let nativeCosmeticCSS: [AdblockRustContentRule]
    let unsupportedOrIgnored: [AdblockRustAdapterDiagnostic]
    let enhancedResourceCandidates: [AdblockRustEnhancedResourceCandidate]

    private enum CodingKeys: String, CodingKey {
        case network
        case nativeCosmeticCSS = "native_cosmetic_css"
        case unsupportedOrIgnored = "unsupported_or_ignored"
        case enhancedResourceCandidates = "enhanced_resource_candidates"
    }

    init(
        network: [AdblockRustContentRule],
        nativeCosmeticCSS: [AdblockRustContentRule],
        unsupportedOrIgnored: [AdblockRustAdapterDiagnostic],
        enhancedResourceCandidates: [AdblockRustEnhancedResourceCandidate] = []
    ) {
        self.network = network
        self.nativeCosmeticCSS = nativeCosmeticCSS
        self.unsupportedOrIgnored = unsupportedOrIgnored
        self.enhancedResourceCandidates = enhancedResourceCandidates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        network = try container.decode([AdblockRustContentRule].self, forKey: .network)
        nativeCosmeticCSS = try container.decode([AdblockRustContentRule].self, forKey: .nativeCosmeticCSS)
        unsupportedOrIgnored = try container.decode([AdblockRustAdapterDiagnostic].self, forKey: .unsupportedOrIgnored)
        enhancedResourceCandidates = try container.decodeIfPresent(
            [AdblockRustEnhancedResourceCandidate].self,
            forKey: .enhancedResourceCandidates
        ) ?? []
    }
}

struct AdblockRustAdapterDiagnostic: Decodable, Equatable, Sendable {
    let rule: String
    let reason: String
}

struct AdblockRustEnhancedResourceCandidate: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case scriptlet
        case redirect
        case noopRedirect = "noop_redirect"
        case proceduralCosmetic = "procedural_cosmetic"
    }

    let kind: Kind
    let resourceName: String
    let canonicalResourceName: String
    let alias: String?
    let resourceType: String
    let mimeType: String?
    let parameters: [String]
    let includeDomains: [String]
    let excludeDomains: [String]
    let sourceRule: String
    let diagnosticSource: String
    let unsupportedReason: String?
    let matchedTrustedBundledResource: Bool

    private enum CodingKeys: String, CodingKey {
        case kind
        case resourceName = "resource_name"
        case canonicalResourceName = "canonical_resource_name"
        case alias
        case resourceType = "resource_type"
        case mimeType = "mime_type"
        case parameters
        case includeDomains = "include_domains"
        case excludeDomains = "exclude_domains"
        case sourceRule = "source_rule"
        case diagnosticSource = "diagnostic_source"
        case unsupportedReason = "unsupported_reason"
        case matchedTrustedBundledResource = "matched_trusted_bundled_resource"
    }

    init(
        kind: Kind,
        resourceName: String,
        canonicalResourceName: String? = nil,
        alias: String? = nil,
        resourceType: String = "unknown",
        mimeType: String? = nil,
        parameters: [String],
        includeDomains: [String],
        excludeDomains: [String],
        sourceRule: String,
        diagnosticSource: String,
        unsupportedReason: String? = nil,
        matchedTrustedBundledResource: Bool = false
    ) {
        self.kind = kind
        self.resourceName = resourceName
        self.canonicalResourceName = canonicalResourceName ?? resourceName
        self.alias = alias
        self.resourceType = resourceType
        self.mimeType = mimeType
        self.parameters = parameters
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.sourceRule = sourceRule
        self.diagnosticSource = diagnosticSource
        self.unsupportedReason = unsupportedReason
        self.matchedTrustedBundledResource = matchedTrustedBundledResource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        resourceName = try container.decode(String.self, forKey: .resourceName)
        canonicalResourceName = try container.decodeIfPresent(
            String.self,
            forKey: .canonicalResourceName
        ) ?? resourceName
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        resourceType = try container.decodeIfPresent(String.self, forKey: .resourceType) ?? "unknown"
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        parameters = try container.decodeIfPresent([String].self, forKey: .parameters) ?? []
        includeDomains = try container.decodeIfPresent([String].self, forKey: .includeDomains) ?? []
        excludeDomains = try container.decodeIfPresent([String].self, forKey: .excludeDomains) ?? []
        sourceRule = try container.decode(String.self, forKey: .sourceRule)
        diagnosticSource = try container.decodeIfPresent(
            String.self,
            forKey: .diagnosticSource
        ) ?? "adblock-rust adapter"
        unsupportedReason = try container.decodeIfPresent(String.self, forKey: .unsupportedReason)
        matchedTrustedBundledResource = try container.decodeIfPresent(
            Bool.self,
            forKey: .matchedTrustedBundledResource
        ) ?? false
    }
}

extension AdblockEnhancedResource {
    init(candidate: AdblockRustEnhancedResourceCandidate) {
        let kind: Kind
        switch candidate.kind {
        case .scriptlet:
            kind = .scriptlet
        case .redirect:
            kind = .redirect
        case .noopRedirect:
            kind = .noopRedirect
        case .proceduralCosmetic:
            kind = .cosmeticCleanup
        }
        self.init(
            name: candidate.resourceName,
            kind: kind,
            sourceRule: candidate.sourceRule
        )
    }
}

extension AdblockRedirectResourceKind {
    init(adapterResourceType: String) {
        switch adapterResourceType {
        case "script":
            self = .script
        case "stylesheet":
            self = .stylesheet
        case "image":
            self = .image
        case "document":
            self = .document
        case "text":
            self = .text
        default:
            self = .unknown
        }
    }
}

extension AdblockRedirectResourceCandidate {
    init(candidate: AdblockRustEnhancedResourceCandidate) {
        self.init(
            requestedName: candidate.resourceName,
            canonicalName: candidate.canonicalResourceName,
            alias: candidate.alias,
            resourceKind: AdblockRedirectResourceKind(adapterResourceType: candidate.resourceType),
            mimeType: candidate.mimeType,
            includeDomains: candidate.includeDomains,
            excludeDomains: candidate.excludeDomains,
            sourceRule: candidate.sourceRule,
            diagnosticSource: candidate.diagnosticSource,
            unsupportedReason: candidate.unsupportedReason,
            matchedTrustedBundledResource: candidate.matchedTrustedBundledResource
        )
    }
}

extension AdblockScriptletInvocation {
    init(candidate: AdblockRustEnhancedResourceCandidate) {
        self.init(
            resourceName: candidate.resourceName,
            parameters: candidate.parameters,
            includeDomains: candidate.includeDomains,
            excludeDomains: candidate.excludeDomains,
            sourceRule: candidate.sourceRule,
            diagnosticSource: candidate.diagnosticSource
        )
    }
}

struct AdblockRustContentRule: Codable, Equatable, Sendable {
    let action: JSONObject
    let trigger: JSONObject
}

extension [AdblockRustContentRule] {
    fileprivate func countActions(named actionName: String) -> Int {
        filter { rule in
            rule.action.objectValue?["type"]?.stringValue == actionName
        }.count
    }
}

enum JSONObject: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case array([JSONObject])
    case object([String: JSONObject])
    case null

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var objectValue: [String: JSONObject]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([JSONObject].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONObject].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

enum AdblockRustCompilerError: Error, Equatable {
    case adapterNotFound
    case adapterFailed(status: Int32, stderr: String)
    case invalidAdapterOutput(String)
}
