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
    static let currentSchemaVersion = 6

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
        webKitRuleListIdentifiers = networkShards.map(\.webKitIdentifier).sorted()
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
        remoteReleaseVersion = remoteMetadata?.releaseVersion
        remoteReleaseTag = remoteMetadata?.releaseTag
        remoteReleaseURL = remoteMetadata?.releaseURL
        remoteManifestSignatureRequired = remoteMetadata?.manifestSignatureRequired
        remoteManifestSignatureVerified = remoteMetadata?.manifestSignatureVerified
        remoteSigningKeyId = remoteMetadata?.signingKeyId
        remoteSigningKeyVersion = remoteMetadata?.signingKeyVersion
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
