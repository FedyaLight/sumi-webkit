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
    case unsupportedNativeCSSSafetyPolicyVersion(String?)

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
        case .unsupportedNativeCSSSafetyPolicyVersion(let version):
            return "Embedded Adblock bundle native CSS safety policy is unsupported: \(version ?? "missing")"
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
    let nativeCSSSafetyPolicyVersion: String?
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
    static let requiredNativeCSSSafetyPolicyVersion = "sumi-native-css-safety/0.4"

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

    static func bundledDirectoryURL(
        for profileId: String,
        in bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let resourceURL = bundle.resourceURL else { return nil }
        let candidates = [
            resourceURL
                .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(directoryName, isDirectory: true),
        ]

        return candidates.first { candidate in
            let manifestURL = candidate.appendingPathComponent(manifestFileName)
            guard fileManager.fileExists(atPath: manifestURL.path),
                  let bundle = try? SumiAdblockNativeRuleBundle.load(directoryURL: candidate, fileManager: fileManager)
            else { return false }
            return bundle.manifest.profileId == profileId
        }
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
        guard manifest.nativeCSSSafetyPolicyVersion == requiredNativeCSSSafetyPolicyVersion else {
            throw SumiAdblockNativeRuleBundleError.unsupportedNativeCSSSafetyPolicyVersion(
                manifest.nativeCSSSafetyPolicyVersion
            )
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
        installedDate: Date,
        generationSource: AdblockRuleGenerationSource = .embeddedBundle
    ) -> AdblockCompiledGenerationManifest {
        let selectedFilterLists = manifest.lists.map {
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
            selectedFilterLists: selectedFilterLists.sorted { $0.id < $1.id },
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            nativeCompiler: compiler,
            nativeCompilerSourceLists: sourceLists.sorted { $0.id < $1.id },
            nativeCompilationSummary: summary,
            compilerDiagnosticsSummary: compilerDiagnosticsSummary(generationSource: generationSource),
            lastSuccessfulUpdateDate: installedDate,
            previousGenerationId: previousManifest?.activeGenerationId,
            generationSource: generationSource,
            nativeRuleBundleId: manifest.bundleId,
            bundleProfileId: manifest.profileId
        )
    }

    private var generatedDate: Date? {
        ISO8601DateFormatter().date(from: manifest.generatedDate)
    }

    func compilerDiagnosticsSummary(
        generationSource: AdblockRuleGenerationSource
    ) -> String {
        [
            "generationSource=\(generationSource.rawValue)",
            "bundleId=\(manifest.bundleId)",
            "bundleProfileId=\(manifest.profileId)",
            "nativeCSSSafetyPolicy=\(manifest.nativeCSSSafetyPolicyVersion ?? "missing")",
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

    private var compilerDiagnosticsSummary: String {
        compilerDiagnosticsSummary(generationSource: .embeddedBundle)
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
            diagnosticsSummary: "\(manifest.bundleId);\(shard.group)"
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

enum SumiAdblockBundleInstallSource: String, CaseIterable, Identifiable, Sendable {
    case appResource
    case developmentBundle
    case futureRemoteBundle

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .appResource:
            return "App Resource"
        case .developmentBundle:
            return "Development Build"
        case .futureRemoteBundle:
            return "Future Remote"
        }
    }

    var generationSource: AdblockRuleGenerationSource {
        switch self {
        case .appResource:
            return .embeddedBundle
        case .developmentBundle:
            return .developmentBundle
        case .futureRemoteBundle:
            return .futureRemoteBundle
        }
    }
}

struct SumiPreparedAdblockBundleSearchPath: Equatable, Sendable {
    let source: SumiAdblockBundleInstallSource
    let path: String
    let exists: Bool
    let rejectionReason: String?
}

struct SumiPreparedAdblockBundleDiscovery: Equatable, Sendable {
    struct ResolvedBundle: Equatable, Sendable {
        let source: SumiAdblockBundleInstallSource
        let bundleURL: URL
        let profileId: String
        let bundleId: String?
        let generationId: String?
    }

    let requiredProfileId: String
    let resolvedBundle: ResolvedBundle?
    let searchedPaths: [SumiPreparedAdblockBundleSearchPath]

    var isAvailable: Bool {
        resolvedBundle != nil
    }

    var source: SumiAdblockBundleInstallSource? {
        resolvedBundle?.source
    }

    var failureSummary: String {
        let details = searchedPaths.map { path in
            "\(path.source.rawValue) path=\(path.path) exists=\(path.exists) rejected=\(path.rejectionReason ?? "nil")"
        }.joined(separator: " | ")
        return "Searched prepared bundle sources for profile \(requiredProfileId): \(details)"
    }
}

enum SumiPreparedAdblockBundleResolver {
    static func discover(
        profileId: String,
        resourceURL: URL? = Bundle.main.resourceURL,
        generatedBundlesRootURL: URL? = defaultGeneratedBundlesRootURL(),
        fileManager: FileManager = .default
    ) -> SumiPreparedAdblockBundleDiscovery {
        var searchedPaths = [SumiPreparedAdblockBundleSearchPath]()

        let appResourcePath = (resourceURL ?? URL(fileURLWithPath: "<missing app resources>", isDirectory: true))
            .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        if let resolved = evaluate(
            source: .appResource,
            profileId: profileId,
            bundleURL: appResourcePath,
            resourceUnavailableReason: resourceURL == nil ? "Bundle resourceURL is unavailable." : nil,
            fileManager: fileManager,
            searchedPaths: &searchedPaths
        ) {
            return SumiPreparedAdblockBundleDiscovery(
                requiredProfileId: profileId,
                resolvedBundle: resolved,
                searchedPaths: searchedPaths
            )
        }

        let developmentRoot = generatedBundlesRootURL ?? defaultGeneratedBundlesRootURL()
        let developmentPath = developmentRoot
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
#if DEBUG
        if let resolved = evaluate(
            source: .developmentBundle,
            profileId: profileId,
            bundleURL: developmentPath,
            resourceUnavailableReason: nil,
            fileManager: fileManager,
            searchedPaths: &searchedPaths
        ) {
            return SumiPreparedAdblockBundleDiscovery(
                requiredProfileId: profileId,
                resolvedBundle: resolved,
                searchedPaths: searchedPaths
            )
        }
#else
        let developmentExists = bundleDirectoryExists(developmentPath, fileManager: fileManager)
        searchedPaths.append(
            SumiPreparedAdblockBundleSearchPath(
                source: .developmentBundle,
                path: developmentPath.path,
                exists: developmentExists,
                rejectionReason: developmentExists
                    ? "developmentBundle is only accepted in DEBUG builds."
                    : "Path does not exist."
            )
        )
#endif

        searchedPaths.append(
            SumiPreparedAdblockBundleSearchPath(
                source: .futureRemoteBundle,
                path: "<futureRemoteBundle>",
                exists: false,
                rejectionReason: "futureRemoteBundle discovery is not implemented."
            )
        )

        return SumiPreparedAdblockBundleDiscovery(
            requiredProfileId: profileId,
            resolvedBundle: nil,
            searchedPaths: searchedPaths
        )
    }

    static func defaultGeneratedBundlesRootURL() -> URL {
        repositoryRootURL().appendingPathComponent(".build/sumi-adblock-bundles", isDirectory: true)
    }

    static func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func evaluate(
        source: SumiAdblockBundleInstallSource,
        profileId: String,
        bundleURL: URL,
        resourceUnavailableReason: String?,
        fileManager: FileManager,
        searchedPaths: inout [SumiPreparedAdblockBundleSearchPath]
    ) -> SumiPreparedAdblockBundleDiscovery.ResolvedBundle? {
        if let resourceUnavailableReason {
            searchedPaths.append(
                SumiPreparedAdblockBundleSearchPath(
                    source: source,
                    path: bundleURL.path,
                    exists: false,
                    rejectionReason: resourceUnavailableReason
                )
            )
            return nil
        }

        let exists = bundleDirectoryExists(bundleURL, fileManager: fileManager)
        guard exists else {
            searchedPaths.append(
                SumiPreparedAdblockBundleSearchPath(
                    source: source,
                    path: bundleURL.path,
                    exists: false,
                    rejectionReason: "Path does not exist."
                )
            )
            return nil
        }

        do {
            let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL, fileManager: fileManager)
            guard bundle.manifest.profileId == profileId else {
                searchedPaths.append(
                    SumiPreparedAdblockBundleSearchPath(
                        source: source,
                        path: bundleURL.path,
                        exists: true,
                        rejectionReason: "Manifest profileId \(bundle.manifest.profileId) does not match required profile \(profileId)."
                    )
                )
                return nil
            }
            searchedPaths.append(
                SumiPreparedAdblockBundleSearchPath(
                    source: source,
                    path: bundleURL.path,
                    exists: true,
                    rejectionReason: nil
                )
            )
            return SumiPreparedAdblockBundleDiscovery.ResolvedBundle(
                source: source,
                bundleURL: bundleURL,
                profileId: bundle.manifest.profileId,
                bundleId: bundle.manifest.bundleId,
                generationId: bundle.manifest.generationId
            )
        } catch {
            searchedPaths.append(
                SumiPreparedAdblockBundleSearchPath(
                    source: source,
                    path: bundleURL.path,
                    exists: true,
                    rejectionReason: error.localizedDescription
                )
            )
            return nil
        }
    }

    private static func bundleDirectoryExists(
        _ bundleURL: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
}

#if DEBUG
struct SumiEmbeddedAdblockBundleProfile: Equatable, Identifiable, Sendable {
    let id: String
    let source: SumiAdblockBundleInstallSource
    let profileId: String
    let displayName: String
    let bundleURL: URL
    let bundleId: String?
    let generationId: String?
    let networkShardCount: Int
    let nativeCSSShardCount: Int
    let networkRuleCount: Int
    let nativeCSSRuleCount: Int
    let loadError: String?

    var isInstallable: Bool {
        loadError == nil
    }
}

struct SumiEmbeddedAdblockBundleSnapshot: Equatable, Sendable {
    let expectedResourcePath: String
    let expectedDevelopmentPath: String
    let generateCommand: String
    let generatedBundlesRootPath: String
    let generatedBundlesPresentOutsideAppResources: Bool
    let profiles: [SumiEmbeddedAdblockBundleProfile]

    var installableProfiles: [SumiEmbeddedAdblockBundleProfile] {
        profiles.filter(\.isInstallable)
    }

    func installableProfiles(
        source: SumiAdblockBundleInstallSource
    ) -> [SumiEmbeddedAdblockBundleProfile] {
        installableProfiles.filter { $0.source == source }
    }

    func profile(
        source: SumiAdblockBundleInstallSource,
        profileId: String
    ) -> SumiEmbeddedAdblockBundleProfile? {
        installableProfiles.first {
            $0.source == source && $0.profileId == profileId
        }
    }
}

enum SumiEmbeddedAdblockBundleCatalog {
    static let supportedProfileIds = [
        "adguardAdsPrivacy",
    ]

    static let generateCommand = "scripts/build_sumi_adblock_bundle.sh --all-profiles --output .build/sumi-adblock-bundles"

    static func snapshot(
        resourceURL: URL? = Bundle.main.resourceURL,
        generatedBundlesRootURL: URL? = defaultGeneratedBundlesRootURL(),
        fileManager: FileManager = .default
    ) -> SumiEmbeddedAdblockBundleSnapshot {
        let resourceRoot = resourceURL ?? URL(fileURLWithPath: "<missing app resources>")
        let generatedRoot = generatedBundlesRootURL ?? repositoryRootURL()
            .appendingPathComponent(".build/sumi-adblock-bundles", isDirectory: true)
        let profileURLs = supportedProfileIds.flatMap { profileId -> [SumiEmbeddedAdblockBundleProfile] in
            var profiles = [SumiEmbeddedAdblockBundleProfile]()
            if let bundleURL = embeddedBundleCandidateURL(
                for: profileId,
                resourceURL: resourceURL,
                fileManager: fileManager
            ) {
                profiles.append(
                    profile(
                        for: profileId,
                        source: .appResource,
                        bundleURL: bundleURL,
                        fileManager: fileManager
                    )
                )
            }
            if let bundleURL = developmentBundleURL(
                for: profileId,
                generatedBundlesRootURL: generatedRoot,
                fileManager: fileManager
            ) {
                profiles.append(
                    profile(
                        for: profileId,
                        source: .developmentBundle,
                        bundleURL: bundleURL,
                        fileManager: fileManager
                    )
                )
            }
            return profiles
        }

        return SumiEmbeddedAdblockBundleSnapshot(
            expectedResourcePath: resourceRoot
                .appendingPathComponent("SumiAdblockBundles/<profile>/\(SumiAdblockNativeRuleBundle.directoryName)", isDirectory: true)
                .path,
            expectedDevelopmentPath: generatedRoot
                .appendingPathComponent("<profile>", isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
                .path,
            generateCommand: generateCommand,
            generatedBundlesRootPath: generatedRoot.path,
            generatedBundlesPresentOutsideAppResources: generatedBundlesPresent(
                rootURL: generatedRoot,
                fileManager: fileManager
            ),
            profiles: profileURLs.sorted {
                if $0.profileId == $1.profileId {
                    return $0.source.rawValue < $1.source.rawValue
                }
                return $0.profileId < $1.profileId
            }
        )
    }

    static func embeddedBundleURL(
        for profileId: String,
        resourceURL: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let resourceURL else { return nil }
        let candidates = [
            resourceURL
                .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
        ]

        return candidates.first { candidate in
            let manifestURL = candidate.appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName)
            guard fileManager.fileExists(atPath: manifestURL.path),
                  let bundle = try? SumiAdblockNativeRuleBundle.load(directoryURL: candidate, fileManager: fileManager)
            else { return false }
            return bundle.manifest.profileId == profileId
        }
    }

    private static func embeddedBundleCandidateURL(
        for profileId: String,
        resourceURL: URL?,
        fileManager: FileManager
    ) -> URL? {
        guard let resourceURL else { return nil }
        let candidates = [
            resourceURL
                .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
            resourceURL
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true),
        ]
        return candidates.first {
            bundleDirectoryExists($0, fileManager: fileManager)
        }
    }

    static func developmentBundleURL(
        for profileId: String,
        generatedBundlesRootURL: URL? = defaultGeneratedBundlesRootURL(),
        fileManager: FileManager = .default
    ) -> URL? {
        guard let generatedBundlesRootURL else { return nil }
        let candidate = generatedBundlesRootURL
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        return bundleDirectoryExists(candidate, fileManager: fileManager) ? candidate : nil
    }

    private static func profile(
        for profileId: String,
        source: SumiAdblockBundleInstallSource,
        bundleURL: URL,
        fileManager: FileManager
    ) -> SumiEmbeddedAdblockBundleProfile {
        do {
            let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL, fileManager: fileManager)
            let networkShards = bundle.manifest.shards.filter { $0.kind == "network" }
            let nativeCSSShards = bundle.manifest.shards.filter { $0.kind == "nativeCSS" }
            return SumiEmbeddedAdblockBundleProfile(
                id: "\(source.rawValue):\(bundle.manifest.profileId)",
                source: source,
                profileId: bundle.manifest.profileId,
                displayName: displayName(for: bundle.manifest.profileId),
                bundleURL: bundleURL,
                bundleId: bundle.manifest.bundleId,
                generationId: bundle.manifest.generationId,
                networkShardCount: networkShards.count,
                nativeCSSShardCount: nativeCSSShards.count,
                networkRuleCount: networkShards.reduce(0) { $0 + $1.ruleCount },
                nativeCSSRuleCount: nativeCSSShards.reduce(0) { $0 + $1.ruleCount },
                loadError: nil
            )
        } catch {
            return SumiEmbeddedAdblockBundleProfile(
                id: "\(source.rawValue):\(profileId)",
                source: source,
                profileId: profileId,
                displayName: displayName(for: profileId),
                bundleURL: bundleURL,
                bundleId: nil,
                generationId: nil,
                networkShardCount: 0,
                nativeCSSShardCount: 0,
                networkRuleCount: 0,
                nativeCSSRuleCount: 0,
                loadError: error.localizedDescription
            )
        }
    }

    private static func generatedBundlesPresent(
        rootURL: URL,
        fileManager: FileManager
    ) -> Bool {
        supportedProfileIds.contains { profileId in
            let manifestURL = rootURL
                .appendingPathComponent(profileId, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
                .appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName)
            return fileManager.fileExists(atPath: manifestURL.path)
        }
    }

    private static func bundleDirectoryExists(
        _ bundleURL: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private static func displayName(for profileId: String) -> String {
        switch profileId {
        case "adguardAdsPrivacy":
            return "adguardAdsPrivacy"
        default:
            return profileId
        }
    }

    private static func defaultGeneratedBundlesRootURL() -> URL? {
        SumiPreparedAdblockBundleResolver.defaultGeneratedBundlesRootURL()
    }

    private static func repositoryRootURL() -> URL {
        SumiPreparedAdblockBundleResolver.repositoryRootURL()
    }
}
#endif

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
