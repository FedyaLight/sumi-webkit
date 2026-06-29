import Combine
import Foundation

enum AdblockFilterListCategory: String, Codable, CaseIterable, Sendable {
    case baseAds
    case nativeCosmeticCompatibleAds
    case annoyances
    case regional
    case privacyOverlap
}

enum AdblockUpdateFailureStage: String, Codable, CaseIterable, Sendable {
    case embeddedBundleManifestRead = "manifest read"
    case embeddedBundleHashVerification = "hash verification"
    case embeddedBundleMissingShard = "missing shard"
    case embeddedBundleJSONParse = "JSON parse"
    case embeddedBundleWebKitCompile = "WebKit compile"
    case embeddedBundleLookup = "lookup"
    case embeddedBundleManifestCommit = "manifest commit"
}

enum AdblockRuleGenerationSource: String, Codable, CaseIterable, Sendable {
    case embeddedBundle
    case developmentBundle
    case remoteReleaseBundle
}

struct SumiAdblockPreparedBundleRemoteMetadata: Codable, Equatable, Sendable {
    let releaseVersion: String
    let releaseTag: String
    let releaseURL: String?
    let publishedDate: Date?
    let manifestSignatureRequired: Bool?
    let manifestSignatureVerified: Bool?
    let signingKeyId: String?
    let signingKeyVersion: Int?

    init(
        releaseVersion: String,
        releaseTag: String,
        releaseURL: String? = nil,
        publishedDate: Date? = nil,
        manifestSignatureRequired: Bool? = nil,
        manifestSignatureVerified: Bool? = nil,
        signingKeyId: String? = nil,
        signingKeyVersion: Int? = nil
    ) {
        self.releaseVersion = releaseVersion
        self.releaseTag = releaseTag
        self.releaseURL = releaseURL
        self.publishedDate = publishedDate
        self.manifestSignatureRequired = manifestSignatureRequired
        self.manifestSignatureVerified = manifestSignatureVerified
        self.signingKeyId = signingKeyId
        self.signingKeyVersion = signingKeyVersion
    }
}

struct AdblockCompiledGenerationManifest: Codable, Equatable, Sendable {
    struct SelectedFilterList: Codable, Equatable, Sendable {
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

    let schemaVersion: Int
    let activeGenerationId: String
    let createdDate: Date
    let selectedFilterLists: [SelectedFilterList]
    let webKitRuleListIdentifiers: [String]
    let networkShards: [NativeContentBlockingShardDescriptor]
    let nativeCSSShards: [NativeContentBlockingShardDescriptor]
    let nativeCompiler: NativeContentBlockingCompilerIdentity?
    let nativeCompilerSourceLists: [NativeContentBlockingSourceList]?
    let nativeLogicalGroups: [NativeContentBlockingLogicalGroupDescriptor]?
    let nativeCompilationSummary: NativeContentBlockingCompilationSummary?
    let compilerDiagnosticsSummary: String
    let lastSuccessfulUpdateDate: Date
    let previousGenerationId: String?
    let generationSource: AdblockRuleGenerationSource
    let nativeRuleBundleId: String?
    let bundleProfileId: String?
    let remoteReleaseVersion: String?
    let remoteReleaseTag: String?
    let remoteReleaseURL: String?
    let remoteManifestSignatureRequired: Bool?
    let remoteManifestSignatureVerified: Bool?
    let remoteSigningKeyId: String?
    let remoteSigningKeyVersion: Int?

    var allNativeShards: [NativeContentBlockingShardDescriptor] {
        networkShards + nativeCSSShards
    }

    func withoutPreviousGeneration() -> AdblockCompiledGenerationManifest {
        let remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata?
        if let remoteReleaseVersion, let remoteReleaseTag {
            remoteMetadata = SumiAdblockPreparedBundleRemoteMetadata(
                releaseVersion: remoteReleaseVersion,
                releaseTag: remoteReleaseTag,
                releaseURL: remoteReleaseURL,
                manifestSignatureRequired: remoteManifestSignatureRequired,
                manifestSignatureVerified: remoteManifestSignatureVerified,
                signingKeyId: remoteSigningKeyId,
                signingKeyVersion: remoteSigningKeyVersion
            )
        } else {
            remoteMetadata = nil
        }

        return AdblockCompiledGenerationManifest(
            schemaVersion: schemaVersion,
            activeGenerationId: activeGenerationId,
            createdDate: createdDate,
            selectedFilterLists: selectedFilterLists,
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            nativeCompiler: nativeCompiler,
            nativeCompilerSourceLists: nativeCompilerSourceLists,
            nativeLogicalGroups: nativeLogicalGroups,
            nativeCompilationSummary: nativeCompilationSummary,
            compilerDiagnosticsSummary: compilerDiagnosticsSummary,
            lastSuccessfulUpdateDate: lastSuccessfulUpdateDate,
            previousGenerationId: nil,
            generationSource: generationSource,
            nativeRuleBundleId: nativeRuleBundleId,
            bundleProfileId: bundleProfileId,
            remoteMetadata: remoteMetadata
        )
    }

    init(
        schemaVersion: Int,
        activeGenerationId: String,
        createdDate: Date,
        selectedFilterLists: [SelectedFilterList],
        networkShards: [NativeContentBlockingShardDescriptor],
        nativeCSSShards: [NativeContentBlockingShardDescriptor],
        nativeCompiler: NativeContentBlockingCompilerIdentity?,
        nativeCompilerSourceLists: [NativeContentBlockingSourceList]?,
        nativeLogicalGroups: [NativeContentBlockingLogicalGroupDescriptor]? = nil,
        nativeCompilationSummary: NativeContentBlockingCompilationSummary? = nil,
        compilerDiagnosticsSummary: String,
        lastSuccessfulUpdateDate: Date,
        previousGenerationId: String?,
        generationSource: AdblockRuleGenerationSource,
        nativeRuleBundleId: String? = nil,
        bundleProfileId: String? = nil,
        remoteMetadata: SumiAdblockPreparedBundleRemoteMetadata? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.activeGenerationId = activeGenerationId
        self.createdDate = createdDate
        self.selectedFilterLists = selectedFilterLists
        self.networkShards = networkShards
        self.nativeCSSShards = nativeCSSShards
        self.webKitRuleListIdentifiers = networkShards
            .map(\.webKitIdentifier)
            .sorted()
        self.nativeCompiler = nativeCompiler
        self.nativeCompilerSourceLists = nativeCompilerSourceLists
        self.nativeLogicalGroups = nativeLogicalGroups
        self.nativeCompilationSummary = nativeCompilationSummary
        self.compilerDiagnosticsSummary = compilerDiagnosticsSummary
        self.lastSuccessfulUpdateDate = lastSuccessfulUpdateDate
        self.previousGenerationId = previousGenerationId
        self.generationSource = generationSource
        self.nativeRuleBundleId = nativeRuleBundleId
        self.bundleProfileId = bundleProfileId
        self.remoteReleaseVersion = remoteMetadata?.releaseVersion
        self.remoteReleaseTag = remoteMetadata?.releaseTag
        self.remoteReleaseURL = remoteMetadata?.releaseURL
        self.remoteManifestSignatureRequired = remoteMetadata?.manifestSignatureRequired
        self.remoteManifestSignatureVerified = remoteMetadata?.manifestSignatureVerified
        self.remoteSigningKeyId = remoteMetadata?.signingKeyId
        self.remoteSigningKeyVersion = remoteMetadata?.signingKeyVersion
    }
}

struct AdblockGenerationCleanupReport: Equatable, Sendable {
    var removedWebKitIdentifiers: [String] = []
    var removedFilePaths: [String] = []
    var diagnostics: [String] = []
}

struct AdblockGenerationRollbackReport: Equatable, Sendable {
    let rolledBack: Bool
    let activeGenerationId: String?
    let restoredGenerationId: String?
    let diagnostics: [String]
}

struct AdblockUpdateDiagnostics: Error, LocalizedError, Equatable, Sendable {
    let summary: String
    let stage: AdblockUpdateFailureStage?
    let failedShardIdentifier: String?
    let generationSource: AdblockRuleGenerationSource?
    let bundleProfileId: String?
    let bundlePath: String?
    let nativeRuleBundleId: String?

    init(
        summary: String,
        stage: AdblockUpdateFailureStage? = nil,
        failedShardIdentifier: String? = nil,
        generationSource: AdblockRuleGenerationSource? = nil,
        bundleProfileId: String? = nil,
        bundlePath: String? = nil,
        nativeRuleBundleId: String? = nil
    ) {
        self.summary = summary
        self.stage = stage
        self.failedShardIdentifier = failedShardIdentifier
        self.generationSource = generationSource
        self.bundleProfileId = bundleProfileId
        self.bundlePath = bundlePath
        self.nativeRuleBundleId = nativeRuleBundleId
    }

    var errorDescription: String? { summary }
}

actor AdblockUpdateManifestStore {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let manifestURL: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
        manifestURL = self.rootDirectory.appendingPathComponent("active-generation.json")
    }

    nonisolated var storageRoot: URL { rootDirectory }

    func activeManifest() throws -> AdblockCompiledGenerationManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: data)
    }

    func archivedManifest(generationId: String) throws -> AdblockCompiledGenerationManifest? {
        let url = generationDirectory(for: generationId)
            .appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: data)
    }

    func compiledShardDefinitions(
        for manifest: AdblockCompiledGenerationManifest,
        includingRuleKinds ruleKinds: Set<AdblockCompiledRuleGroupKind> = [.network]
    ) throws -> [SumiContentRuleListDefinition] {
        try manifest.allNativeShards
            .filter { ruleKinds.contains($0.kind) }
            .sorted(by: Self.shardSort)
            .map { shard in
                let url = generationDirectory(for: shard.generationId)
                    .appendingPathComponent("\(shard.id).json")
                guard fileManager.fileExists(atPath: url.path) else {
                    throw AdblockUpdateDiagnostics(
                        summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                        failedShardIdentifier: shard.webKitIdentifier
                    )
                }
                let data = try Data(contentsOf: url)
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordShardJSONRead(
                    identifier: shard.webKitIdentifier,
                    path: url.path,
                    byteCount: data.count,
                    reason: "payload-backed manifest repair loaded persisted shard JSON"
                )
#endif
                guard !data.isEmpty else {
                    throw AdblockUpdateDiagnostics(
                        summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                        failedShardIdentifier: shard.webKitIdentifier
                    )
                }
                return SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: String(decoding: data, as: UTF8.self),
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.contentHash
                )
            }
    }

    func validateCompiledShardFiles(for manifest: AdblockCompiledGenerationManifest) throws {
        for shard in manifest.allNativeShards {
            let url = generationDirectory(for: shard.generationId)
                .appendingPathComponent("\(shard.id).json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else {
                throw AdblockUpdateDiagnostics(
                    summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
        }
    }

    func beginStaging() throws -> URL {
        let stagingRoot = rootDirectory.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stagingURL = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        return stagingURL
    }

    func commit(
        manifest: AdblockCompiledGenerationManifest,
        stagedCompiledShardURLs: [String: URL]
    ) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let generationDirectory = generationDirectory(for: manifest.activeGenerationId)
        try fileManager.createDirectory(at: generationDirectory, withIntermediateDirectories: true)

        for (shardId, stagedURL) in stagedCompiledShardURLs {
            let destination = generationDirectory.appendingPathComponent("\(shardId).json")
            try copyReplacingItem(at: destination, withItemAt: stagedURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(manifest), to: generationDirectory.appendingPathComponent("manifest.json"))
        try atomicWrite(encoder.encode(manifest), to: manifestURL)
    }

    func replaceActiveManifest(_ manifest: AdblockCompiledGenerationManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(manifest), to: manifestURL)
    }

    func archivedGenerationIds() throws -> [String] {
        let generatedRoot = rootDirectory.appendingPathComponent("Generated", isDirectory: true)
        guard fileManager.fileExists(atPath: generatedRoot.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: generatedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return url.lastPathComponent
        }
    }

    func generationDirectoryURL(generationId: String) -> URL {
        generationDirectory(for: generationId)
    }

    func stagingDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("Staging", isDirectory: true)
    }

    private func generationDirectory(for generationId: String) -> URL {
        rootDirectory
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent(generationId, isDirectory: true)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: url)
        }
    }

    private func copyReplacingItem(at destination: URL, withItemAt source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func shardSort(
        lhs: NativeContentBlockingShardDescriptor,
        rhs: NativeContentBlockingShardDescriptor
    ) -> Bool {
        if lhs.kind == rhs.kind { return lhs.id < rhs.id }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sumi/Adblock", isDirectory: true)
    }
}

@MainActor
final class AdblockManifestRuleListProvider: SumiContentRuleListSetProviding {
    private var manifest: AdblockCompiledGenerationManifest?
    private var compiledDefinitionsByIdentifier: [String: SumiContentRuleListDefinition]
    private let compiledDefinitionLoader: (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition
    private let changesSubject = PassthroughSubject<Void, Never>()

    init(
        manifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = [],
        compiledDefinitionLoader: @escaping (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition = {
            throw AdblockUpdateDiagnostics(
                summary: "Missing compiled Adblock shard definition: \($0.webKitIdentifier)",
                failedShardIdentifier: $0.webKitIdentifier
            )
        }
    ) {
        self.manifest = manifest
        self.compiledDefinitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map { ($0.storeIdentifierOverride ?? $0.name, $0) }
        )
        self.compiledDefinitionLoader = compiledDefinitionLoader
    }

    var changesPublisher: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }
    var hasProfileSpecificRuleLists: Bool { false }
    var activeManifest: AdblockCompiledGenerationManifest? { manifest }

    func updateManifest(
        _ manifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = []
    ) {
        let definitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map { ($0.storeIdentifierOverride ?? $0.name, $0) }
        )
        guard self.manifest != manifest || compiledDefinitionsByIdentifier != definitionsByIdentifier else { return }
        self.manifest = manifest
        compiledDefinitionsByIdentifier = definitionsByIdentifier
        changesSubject.send(())
    }

    func ruleListSet(profileId: UUID?) throws -> SumiContentRuleListSet {
        guard let manifest else { return SumiContentRuleListSet() }
        let definitions = try manifest.networkShards.map { shard in
            if let definition = compiledDefinitionsByIdentifier[shard.webKitIdentifier] {
                return definition
            }
            return try compiledDefinitionLoader(shard)
        }
        return SumiContentRuleListSet(definitions: definitions)
    }

    static func diskBackedDefinitionLoader(
        storageRoot: URL,
        fileManager: FileManager = .default
    ) -> (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition {
        { shard in
            let url = storageRoot
                .appendingPathComponent("Generated", isDirectory: true)
                .appendingPathComponent(shard.generationId, isDirectory: true)
                .appendingPathComponent("\(shard.id).json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            let data = try Data(contentsOf: url)
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordShardJSONRead(
                identifier: shard.webKitIdentifier,
                path: url.path,
                byteCount: data.count,
                reason: "disk-backed provider loaded persisted shard JSON"
            )
#endif
            guard !data.isEmpty else {
                throw AdblockUpdateDiagnostics(
                    summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            return SumiContentRuleListDefinition(
                name: shard.webKitIdentifier,
                encodedContentRuleList: String(decoding: data, as: UTF8.self),
                storeIdentifierOverride: shard.webKitIdentifier,
                contentHashOverride: shard.contentHash
            )
        }
    }
}

struct PreparedAdblockRuleListPublication {
    let manifest: AdblockCompiledGenerationManifest
    let definitions: [SumiContentRuleListDefinition]
    let preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate
}

@MainActor
protocol AdblockRuleListPublishing: AnyObject, Sendable {
    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication
    func commitPublication(_ publication: PreparedAdblockRuleListPublication)
}

@MainActor
final class AdblockRuleListPublisher: AdblockRuleListPublishing {
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let contentBlockingService: SumiContentBlockingService

    init(ruleListProvider: AdblockManifestRuleListProvider, contentBlockingService: SumiContentBlockingService) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = contentBlockingService
    }

    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        let prepared = try await contentBlockingService.prepareRuleListUpdate(
            ruleLists: definitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        return PreparedAdblockRuleListPublication(
            manifest: manifest,
            definitions: definitions.map { $0.metadataOnly() },
            preparedContentBlockingUpdate: prepared
        )
    }

    func commitPublication(_ publication: PreparedAdblockRuleListPublication) {
        ruleListProvider.updateManifest(
            publication.manifest,
            compiledDefinitions: publication.definitions
        )
        contentBlockingService.commitPreparedContentBlockingUpdate(publication.preparedContentBlockingUpdate)
    }
}

actor AdblockGenerationGarbageCollector {
    private let manifestStore: AdblockUpdateManifestStore
    private let contentRuleListStore: any SumiContentRuleListCompiling
    private let fileManager: FileManager

    init(
        manifestStore: AdblockUpdateManifestStore,
        contentRuleListStore: any SumiContentRuleListCompiling,
        fileManager: FileManager = .default
    ) {
        self.manifestStore = manifestStore
        self.contentRuleListStore = contentRuleListStore
        self.fileManager = fileManager
    }

    func cleanupAfterSuccessfulUpdate() async -> AdblockGenerationCleanupReport {
        var report = AdblockGenerationCleanupReport()
        do {
            guard let activeManifest = try await manifestStore.activeManifest() else { return report }
            let preservedGenerationIds = Set([activeManifest.activeGenerationId])
            let preservedIdentifiers = Set(activeManifest.webKitRuleListIdentifiers)
            let identifiers = await contentRuleListStore.availableContentRuleListIdentifiers()
            for identifier in identifiers
                where AdblockUpdateCoordinator.isAdblockGeneratedWebKitIdentifier(identifier)
                    && !preservedIdentifiers.contains(identifier) {
                do {
                    try await contentRuleListStore.removeContentRuleList(forIdentifier: identifier)
                    report.removedWebKitIdentifiers.append(identifier)
#if DEBUG
                    SumiProtectionStartupRestoreDiagnostics.shared.recordCompiledRuleListRemoval(
                        identifiers: [identifier],
                        reason: "Adblock generation garbage collector removed stale WebKit rule list"
                    )
#endif
                } catch {
                    report.diagnostics.append("Failed to remove WebKit rule list \(identifier): \(error.localizedDescription)")
                }
            }
            let generationIdsOnDisk = try await manifestStore.archivedGenerationIds()
            for generationId in generationIdsOnDisk where !preservedGenerationIds.contains(generationId) {
                let url = await manifestStore.generationDirectoryURL(generationId: generationId)
                if isInsideAdblockRoot(url) {
                    removeItemIfPresent(at: url, report: &report)
                }
            }
            if activeManifest.previousGenerationId != nil {
                try await manifestStore.replaceActiveManifest(activeManifest.withoutPreviousGeneration())
            }
            let stagingRoot = await manifestStore.stagingDirectoryURL()
            if fileManager.fileExists(atPath: stagingRoot.path) {
                for url in try fileManager.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil) {
                    if isInsideAdblockRoot(url) {
                        removeItemIfPresent(at: url, report: &report)
                    }
                }
            }
        } catch {
            report.diagnostics.append("Cleanup failed before deletion: \(error.localizedDescription)")
        }
        report.removedWebKitIdentifiers.sort()
        report.removedFilePaths.sort()
        return report
    }

    private func isInsideAdblockRoot(_ url: URL) -> Bool {
        let root = manifestStore.storageRoot.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private func removeItemIfPresent(at url: URL, report: inout AdblockGenerationCleanupReport) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            report.removedFilePaths.append(url.path)
        } catch {
            report.diagnostics.append("Failed to remove \(url.path): \(error.localizedDescription)")
        }
    }
}

actor AdblockUpdateCoordinator {
    private let manifestStore: AdblockUpdateManifestStore
    private let publisher: any AdblockRuleListPublishing
    private let contentRuleListStore: (any SumiContentRuleListCompiling)?
    private let garbageCollector: AdblockGenerationGarbageCollector?
    private(set) var latestDiagnostics: AdblockUpdateDiagnostics?

    init(
        manifestStore: AdblockUpdateManifestStore,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: (any SumiContentRuleListCompiling)? = nil,
        garbageCollector: AdblockGenerationGarbageCollector? = nil
    ) {
        self.manifestStore = manifestStore
        self.publisher = publisher
        self.contentRuleListStore = contentRuleListStore
        self.garbageCollector = garbageCollector
    }

    static func production(
        manifestStore: AdblockUpdateManifestStore,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: (any SumiContentRuleListCompiling)?,
        garbageCollector: AdblockGenerationGarbageCollector?
    ) -> AdblockUpdateCoordinator {
        AdblockUpdateCoordinator(
            manifestStore: manifestStore,
            publisher: publisher,
            contentRuleListStore: contentRuleListStore,
            garbageCollector: garbageCollector
        )
    }

    func prepareEmbeddedBundlePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        try await publisher.preparePublication(manifest: manifest, definitions: definitions)
    }

    func commitEmbeddedBundlePublication(_ publication: PreparedAdblockRuleListPublication) async {
        await publisher.commitPublication(publication)
        latestDiagnostics = AdblockUpdateDiagnostics(
            summary: "Prepared Adblock bundle installed",
            generationSource: publication.manifest.generationSource,
            bundleProfileId: publication.manifest.bundleProfileId,
            nativeRuleBundleId: publication.manifest.nativeRuleBundleId
        )
        _ = await garbageCollector?.cleanupAfterSuccessfulUpdate()
    }

    func rollbackIfActiveGenerationFailsSmokeCheck() async -> AdblockGenerationRollbackReport {
        do {
            guard let activeManifest = try await manifestStore.activeManifest() else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: nil,
                    restoredGenerationId: nil,
                    diagnostics: ["No active Adblock manifest"]
                )
            }
            let activeMissingIdentifiers = await missingIdentifiers(in: activeManifest)
            guard !activeMissingIdentifiers.isEmpty else {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordGenerationStaleCheck(
                    consideredStale: false,
                    reason: "Active generation WebKit smoke lookup succeeded"
                )
#endif
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: []
                )
            }
            guard let previousGenerationId = activeManifest.previousGenerationId,
                  let previousManifest = try await manifestStore.archivedManifest(generationId: previousGenerationId)
            else {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordGenerationStaleCheck(
                    consideredStale: true,
                    reason: "Active generation smoke lookup failed; no previous generation is available"
                )
#endif
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active generation smoke lookup failed; no previous generation is available"]
                )
            }
            let previousMissing = await missingIdentifiers(in: previousManifest)
            guard previousMissing.isEmpty else {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordGenerationStaleCheck(
                    consideredStale: true,
                    reason: "Active and previous Adblock generations failed smoke lookup"
                )
#endif
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active and previous Adblock generations failed smoke lookup"]
                )
            }
            try await manifestStore.replaceActiveManifest(previousManifest)
#if DEBUG
            let rollbackReason = "Active generation smoke lookup failed; rolled back after missing identifiers: \(activeMissingIdentifiers.joined(separator: ","))"
            SumiProtectionStartupRestoreDiagnostics.shared.recordGenerationStaleCheck(
                consideredStale: true,
                reason: rollbackReason
            )
            SumiProtectionStartupRestoreDiagnostics.shared.recordFallback(reason: rollbackReason)
            SumiProtectionStartupRestoreDiagnostics.shared.recordPayloadBackedRestoreUsed(reason: rollbackReason)
            SumiProtectionStartupRestoreDiagnostics.shared.recordRepairCompileUsed(reason: rollbackReason)
#endif
            let previousDefinitions = try await manifestStore.compiledShardDefinitions(for: previousManifest)
            let publication = try await publisher.preparePublication(
                manifest: previousManifest,
                definitions: previousDefinitions
            )
            await publisher.commitPublication(publication)
            return AdblockGenerationRollbackReport(
                rolledBack: true,
                activeGenerationId: activeManifest.activeGenerationId,
                restoredGenerationId: previousManifest.activeGenerationId,
                diagnostics: ["Rolled back after missing identifiers: \(activeMissingIdentifiers.joined(separator: ","))"]
            )
        } catch {
            return AdblockGenerationRollbackReport(
                rolledBack: false,
                activeGenerationId: nil,
                restoredGenerationId: nil,
                diagnostics: ["Rollback smoke check failed: \(error.localizedDescription)"]
            )
        }
    }

    private func missingIdentifiers(in manifest: AdblockCompiledGenerationManifest) async -> [String] {
        guard let contentRuleListStore else { return [] }
        var missing = [String]()
        for identifier in manifest.webKitRuleListIdentifiers {
#if DEBUG
            SumiProtectionStartupRestoreDiagnostics.shared.recordLookupAttempt(identifiers: [identifier])
#endif
            if await contentRuleListStore.canLookUpContentRuleList(forIdentifier: identifier) == false {
                missing.append(identifier)
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordLookupMiss(identifier)
#endif
            } else {
#if DEBUG
                SumiProtectionStartupRestoreDiagnostics.shared.recordLookupHit(identifier)
#endif
            }
        }
        return missing
    }

    static func isAdblockGeneratedWebKitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
            || identifier.hasPrefix("sumi.tracking.network.")
    }
}
