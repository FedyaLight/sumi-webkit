import CryptoKit
import Foundation

enum SumiAdblockNativeRuleBundleError: Error, LocalizedError, Equatable {
    case missingManifest(URL)
    case unsupportedSchemaVersion(Int)
    case missingShard(String)
    case emptyShard(String)
    case invalidShardPath(String)
    case shardHashMismatch(path: String, expected: String, actual: String)
    case shardSizeMismatch(path: String, expected: Int, actual: Int)
    case invalidShardJSON(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "Missing embedded Adblock bundle manifest: \(url.path)"
        case .unsupportedSchemaVersion(let version):
            return "Unsupported embedded Adblock bundle schema version: \(version)"
        case .missingShard(let path):
            return "Missing embedded Adblock bundle shard: \(path)"
        case .emptyShard(let path):
            return "Embedded Adblock bundle shard is empty: \(path)"
        case .invalidShardPath(let path):
            return "Embedded Adblock bundle shard path is invalid: \(path)"
        case .shardHashMismatch(let path, let expected, let actual):
            return "Embedded Adblock bundle shard hash mismatch for \(path): expected \(expected), got \(actual)"
        case .shardSizeMismatch(let path, let expected, let actual):
            return "Embedded Adblock bundle shard size mismatch for \(path): expected \(expected), got \(actual)"
        case .invalidShardJSON(let path):
            return "Embedded Adblock bundle shard JSON is invalid: \(path)"
        }
    }
}

struct SumiAdblockNativeRuleBundleManifest: Codable, Equatable, Sendable {
    struct Compiler: Codable, Equatable, Sendable {
        let name: String
        let version: String
    }

    struct SourceList: Codable, Equatable, Sendable {
        let id: String
        let displayName: String
        let url: String
        let hash: String
        let byteSize: Int
        let ruleCount: Int
        let category: AdblockFilterListCategory?
    }

    struct Shard: Codable, Equatable, Sendable {
        let kind: String
        let group: String
        let relativePath: String
        let hash: String
        let byteSize: Int
        let ruleCount: Int
        let webKitIdentifier: String
    }

    struct DedupeSummary: Codable, Equatable, Sendable {
        let inputRawRuleCount: Int
        let rawDuplicateCountRemoved: Int
        let nativeJSONDuplicateCountRemoved: Int
        let skippedDedupeCount: Int
        let skippedDedupeReasons: [String: Int]
        let finalRuleCount: Int
        let finalShardCount: Int
    }

    struct DiagnosticsSummary: Codable, Equatable, Sendable {
        let inputRuleCount: Int
        let finalRuleCount: Int
        let finalShardCount: Int
        let networkRuleCount: Int
        let nativeCSSRuleCount: Int
        let unsafeCSSFilteredCount: Int
        let warnings: [String]
    }

    let schemaVersion: Int
    let bundleId: String
    let generationId: String
    let profileId: String
    let compiler: Compiler
    let nativeCSSSafetyPolicyVersion: String
    let generatedDate: String
    let lists: [SourceList]
    let shards: [Shard]
    let diagnosticsSummary: DiagnosticsSummary
    let unsafeCSSFilteredCount: Int
    let deduplication: DedupeSummary
}

struct SumiAdblockNativeRuleBundle: Sendable {
    static let directoryName = "SumiAdblockBundle"
    static let manifestFileName = "manifest.json"

    let directoryURL: URL
    let manifest: SumiAdblockNativeRuleBundleManifest

    static func bundledDirectoryURL(
        in bundle: Bundle = .main
    ) -> URL? {
        bundle.url(
            forResource: directoryName,
            withExtension: nil
        )
    }

    static func load(
        directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> SumiAdblockNativeRuleBundle {
        let manifestURL = directoryURL.appendingPathComponent(manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SumiAdblockNativeRuleBundleError.missingManifest(manifestURL)
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(SumiAdblockNativeRuleBundleManifest.self, from: data)
        guard manifest.schemaVersion == 1 else {
            throw SumiAdblockNativeRuleBundleError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        return SumiAdblockNativeRuleBundle(
            directoryURL: directoryURL,
            manifest: manifest
        )
    }

    func contentRuleListDefinitions(
        fileManager: FileManager = .default
    ) throws -> [SumiContentRuleListDefinition] {
        try manifest.shards
            .sorted(by: shardSort)
            .map { shard in
                let data = try shardData(for: shard, fileManager: fileManager)
                return SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: String(decoding: data, as: UTF8.self),
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.hash
                )
            }
    }

    func stagedShardURLs(
        fileManager: FileManager = .default
    ) throws -> [String: URL] {
        try Dictionary(
            uniqueKeysWithValues: manifest.shards.map { shard in
                _ = try shardData(for: shard, fileManager: fileManager)
                return (shardId(for: shard), try shardURL(for: shard, fileManager: fileManager))
            }
        )
    }

    func compiledGenerationManifest(
        previousManifest: AdblockCompiledGenerationManifest?,
        installedDate: Date
    ) -> AdblockCompiledGenerationManifest {
        let selectedLists = manifest.lists.map {
            AdblockCompiledGenerationManifest.SelectedFilterList(
                id: $0.id,
                displayName: $0.displayName,
                contentHash: $0.hash,
                category: $0.category,
                inputByteCount: $0.byteSize,
                approximateRuleCount: $0.ruleCount
            )
        }
        let compiler = NativeContentBlockingCompilerIdentity(
            name: manifest.compiler.name,
            version: manifest.compiler.version
        )
        let sourceLists = manifest.lists.map {
            NativeContentBlockingSourceList(
                id: $0.id,
                displayName: $0.displayName,
                contentHash: $0.hash,
                category: $0.category,
                inputByteCount: $0.byteSize,
                approximateRuleCount: $0.ruleCount
            )
        }
        let networkShards = manifest.shards
            .filter { $0.ruleGroupKind == .network }
            .map { descriptor(for: $0, compiler: compiler) }
        let nativeCSSShards = manifest.shards
            .filter { $0.ruleGroupKind == .nativeCosmeticCSS }
            .map { descriptor(for: $0, compiler: compiler) }
        let summary = NativeContentBlockingCompilationSummary(
            inputRuleCount: manifest.diagnosticsSummary.inputRuleCount,
            inputByteCount: manifest.lists.reduce(0) { $0 + $1.byteSize },
            convertedNetworkRuleCount: manifest.diagnosticsSummary.networkRuleCount,
            convertedNativeCosmeticRuleCount: manifest.diagnosticsSummary.nativeCSSRuleCount,
            unsupportedOrIgnoredRuleCount: 0,
            networkJSONByteCount: networkShards.reduce(0) { $0 + $1.jsonByteCount },
            nativeCosmeticJSONByteCount: nativeCSSShards.reduce(0) { $0 + $1.jsonByteCount },
            totalJSONByteCount: manifest.shards.reduce(0) { $0 + $1.byteSize },
            ruleCap: .none
        )

        return AdblockCompiledGenerationManifest(
            schemaVersion: 6,
            activeGenerationId: manifest.generationId,
            createdDate: generatedDate ?? installedDate,
            selectedFilterLists: selectedLists.sorted { $0.id < $1.id },
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            enhancedRuntimeBundle: nil,
            nativeProfile: AdblockFilterListProfileKind(rawValue: manifest.profileId),
            nativeCompiler: compiler,
            nativeCompilerSourceLists: sourceLists.sorted { $0.id < $1.id },
            nativeCompilationSummary: summary,
            compilerDiagnosticsSummary: compilerDiagnosticsSummary,
            lastSuccessfulUpdateDate: installedDate,
            previousGenerationId: previousManifest?.activeGenerationId,
            generationSource: .embeddedBundle,
            nativeRuleBundleId: manifest.bundleId
        )
    }

    private var generatedDate: Date? {
        ISO8601DateFormatter().date(from: manifest.generatedDate)
    }

    private var compilerDiagnosticsSummary: String {
        [
            "generationSource=embeddedBundle",
            "bundleId=\(manifest.bundleId)",
            "nativeCSSSafetyPolicy=\(manifest.nativeCSSSafetyPolicyVersion)",
            "nativeCSSConverted=\(manifest.diagnosticsSummary.nativeCSSRuleCount)",
            "unsafeNativeCSSRootSelectorsFiltered=\(manifest.unsafeCSSFilteredCount)",
            "nativeCSSEmpty=\(manifest.diagnosticsSummary.nativeCSSRuleCount == 0)",
            "rawDuplicatesRemoved=\(manifest.deduplication.rawDuplicateCountRemoved)",
            "nativeJSONDuplicatesRemoved=\(manifest.deduplication.nativeJSONDuplicateCountRemoved)",
            "dedupeSkipped=\(manifest.deduplication.skippedDedupeCount)",
            "networkShards=\(manifest.shards.filter { $0.ruleGroupKind == .network }.count)",
            "nativeCSSShards=\(manifest.shards.filter { $0.ruleGroupKind == .nativeCosmeticCSS }.count)",
            "largestShardBytes=\(manifest.shards.map(\.byteSize).max() ?? 0)",
        ].joined(separator: "; ")
    }

    private func descriptor(
        for shard: SumiAdblockNativeRuleBundleManifest.Shard,
        compiler: NativeContentBlockingCompilerIdentity
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: shardId(for: shard),
            generationId: manifest.generationId,
            kind: shard.ruleGroupKind,
            sourceListIdentifiers: manifest.lists.map(\.id).sorted(),
            sourceCategories: Array(Set(manifest.lists.compactMap(\.category)))
                .sorted { $0.rawValue < $1.rawValue },
            webKitIdentifier: shard.webKitIdentifier,
            contentHash: shard.hash,
            approximateRuleCount: shard.ruleCount,
            jsonByteCount: shard.byteSize,
            compilerIdentity: compiler,
            profileIdentity: AdblockFilterListProfileKind(rawValue: manifest.profileId),
            diagnosticsSummary: "embeddedBundle;\(manifest.bundleId);\(shard.group)"
        )
    }

    private func shardData(
        for shard: SumiAdblockNativeRuleBundleManifest.Shard,
        fileManager: FileManager
    ) throws -> Data {
        let url = try shardURL(for: shard, fileManager: fileManager)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SumiAdblockNativeRuleBundleError.missingShard(shard.relativePath)
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw SumiAdblockNativeRuleBundleError.emptyShard(shard.relativePath)
        }
        guard data.count == shard.byteSize else {
            throw SumiAdblockNativeRuleBundleError.shardSizeMismatch(
                path: shard.relativePath,
                expected: shard.byteSize,
                actual: data.count
            )
        }
        let actualHash = Self.sha256Hex(data)
        guard actualHash == shard.hash else {
            throw SumiAdblockNativeRuleBundleError.shardHashMismatch(
                path: shard.relativePath,
                expected: shard.hash,
                actual: actualHash
            )
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any],
              !json.isEmpty
        else {
            throw SumiAdblockNativeRuleBundleError.invalidShardJSON(shard.relativePath)
        }
        return data
    }

    private func shardURL(
        for shard: SumiAdblockNativeRuleBundleManifest.Shard,
        fileManager: FileManager
    ) throws -> URL {
        let url = directoryURL.appendingPathComponent(shard.relativePath)
        let rootPath = directoryURL.standardizedFileURL.path
        let shardPath = url.standardizedFileURL.path
        guard shardPath.hasPrefix(rootPath + "/") else {
            throw SumiAdblockNativeRuleBundleError.invalidShardPath(shard.relativePath)
        }
        return url
    }

    private func shardId(for shard: SumiAdblockNativeRuleBundleManifest.Shard) -> String {
        URL(fileURLWithPath: shard.relativePath)
            .deletingPathExtension()
            .lastPathComponent
    }

    private func shardSort(
        lhs: SumiAdblockNativeRuleBundleManifest.Shard,
        rhs: SumiAdblockNativeRuleBundleManifest.Shard
    ) -> Bool {
        if lhs.ruleGroupKind == rhs.ruleGroupKind {
            return lhs.relativePath < rhs.relativePath
        }
        return lhs.ruleGroupKind.rawValue < rhs.ruleGroupKind.rawValue
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private extension SumiAdblockNativeRuleBundleManifest.Shard {
    var ruleGroupKind: AdblockCompiledRuleGroupKind {
        switch kind {
        case "nativeCSS":
            return .nativeCosmeticCSS
        default:
            return .network
        }
    }
}
