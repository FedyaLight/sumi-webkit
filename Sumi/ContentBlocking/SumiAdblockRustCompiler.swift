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
}

struct AdblockCompilationInput: Equatable, Sendable {
    let sourceIdentifier: String
    let filterTexts: [String]
    let selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>
    let sourceLists: [NativeContentBlockingSourceList]

    init(
        sourceIdentifier: String,
        filterTexts: [String],
        selectedOutputGroups: Set<AdblockCompiledRuleGroupKind>,
        sourceLists: [NativeContentBlockingSourceList] = []
    ) {
        self.sourceIdentifier = sourceIdentifier
        self.filterTexts = filterTexts
        self.selectedOutputGroups = selectedOutputGroups
        self.sourceLists = sourceLists
    }
}

struct AdblockCompilationDiagnostics: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let rule: String
        let reason: String
    }

    var unsupportedRules: [Entry] = []
    var ignoredRules: [Entry] = []
    var nativeCosmeticRuleCount = 0
    var unsupportedCosmeticRuleCount = 0
    var ignoredScriptletOrProceduralRuleCount = 0
    var isNativeCosmeticGroupEmpty = true
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

struct NativeContentBlockingCompilationOutput: Equatable, Sendable {
    let sourceIdentifier: String
    let groups: [AdblockCompiledRuleGroup]
    let diagnostics: AdblockCompilationDiagnostics
    let inputRuleCount: Int
    let convertedNetworkRuleCount: Int
    let convertedNativeCosmeticRuleCount: Int
    let unsupportedOrIgnoredRuleCount: Int
    let contentHash: String
    let compilerIdentity: NativeContentBlockingCompilerIdentity
    let sourceLists: [NativeContentBlockingSourceList]

    var nativeRuleGroups: AdblockNativeRuleGroups {
        AdblockNativeRuleGroups(
            network: groups.first { $0.kind == .network },
            nativeCosmeticCSS: groups.first { $0.kind == .nativeCosmeticCSS }
        )
    }

    var ruleListDefinitions: [SumiContentRuleListDefinition] {
        groups.map(\.definition)
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
        var groups = [AdblockCompiledRuleGroup]()
        let networkJSON = try encodedJSON(adapterOutput.network)
        let cosmeticJSON = try encodedJSON(adapterOutput.nativeCosmeticCSS)
        let networkBlockCount = adapterOutput.network.countActions(named: "block")
        let nativeCosmeticCount = adapterOutput.nativeCosmeticCSS.countActions(named: "css-display-none")

        if input.selectedOutputGroups.contains(.network) {
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .network,
                    name: "\(input.sourceIdentifier).network",
                    encodedContentRuleList: networkJSON,
                    convertedRuleCount: networkBlockCount,
                    contentHash: stableHash(networkJSON)
                )
            )
        }

        if input.selectedOutputGroups.contains(.nativeCosmeticCSS) {
            groups.append(
                AdblockCompiledRuleGroup(
                    kind: .nativeCosmeticCSS,
                    name: "\(input.sourceIdentifier).native-css",
                    encodedContentRuleList: cosmeticJSON,
                    convertedRuleCount: nativeCosmeticCount,
                    contentHash: stableHash(cosmeticJSON)
                )
            )
        }

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
            nativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedCosmeticRuleCount: unsupportedCosmeticCount,
            ignoredScriptletOrProceduralRuleCount: scriptletOrProceduralCount,
            isNativeCosmeticGroupEmpty: nativeCosmeticCount == 0
        )
        let contentHash = stableHash(groups.map(\.contentHash).joined(separator: ":"))

        return NativeContentBlockingCompilationOutput(
            sourceIdentifier: input.sourceIdentifier,
            groups: groups,
            diagnostics: diagnostics,
            inputRuleCount: normalizedRules.count,
            convertedNetworkRuleCount: networkBlockCount,
            convertedNativeCosmeticRuleCount: nativeCosmeticCount,
            unsupportedOrIgnoredRuleCount: diagnostics.unsupportedRules.count + diagnostics.ignoredRules.count,
            contentHash: contentHash,
            compilerIdentity: identity,
            sourceLists: input.sourceLists
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
