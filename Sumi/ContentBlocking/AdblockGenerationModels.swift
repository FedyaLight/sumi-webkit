import Foundation

enum AdblockFilterListCategory: String, Codable, CaseIterable, Sendable {
    case baseAds
    case nativeCosmeticCompatibleAds
    case annoyances
    case regional
    case privacyOverlap
}

enum AdblockUpdateFailureStage: String, Codable, CaseIterable, Sendable {
    case manifestRead = "manifest read"
    case hashVerification = "hash verification"
    case missingShard = "missing shard"
    case jsonParse = "JSON parse"
    case webKitCompile = "WebKit compile"
    case lookup = "lookup"
    case manifestCommit = "manifest commit"
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
    let selectedFilterLists: [SelectedFilterList]
    let networkShards: [NativeContentBlockingShardDescriptor]
    let advancedBlocking: AdvancedBlockingGenerationDescriptor?
    let lastSuccessfulUpdateDate: Date
    let previousGenerationId: String?
    let bundleProfileId: String?

    var webKitRuleListIdentifiers: [String] {
        networkShards.map(\.webKitIdentifier).sorted()
    }

    init(
        schemaVersion: Int,
        activeGenerationId: String,
        selectedFilterLists: [SelectedFilterList],
        networkShards: [NativeContentBlockingShardDescriptor],
        advancedBlocking: AdvancedBlockingGenerationDescriptor? = nil,
        lastSuccessfulUpdateDate: Date,
        previousGenerationId: String?,
        bundleProfileId: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.activeGenerationId = activeGenerationId
        self.selectedFilterLists = selectedFilterLists
        self.networkShards = networkShards
        self.advancedBlocking = advancedBlocking
        self.lastSuccessfulUpdateDate = lastSuccessfulUpdateDate
        self.previousGenerationId = previousGenerationId
        self.bundleProfileId = bundleProfileId
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
    let bundleProfileId: String?
    let bundlePath: String?

    init(
        summary: String,
        stage: AdblockUpdateFailureStage? = nil,
        failedShardIdentifier: String? = nil,
        bundleProfileId: String? = nil,
        bundlePath: String? = nil
    ) {
        self.summary = summary
        self.stage = stage
        self.failedShardIdentifier = failedShardIdentifier
        self.bundleProfileId = bundleProfileId
        self.bundlePath = bundlePath
    }

    var errorDescription: String? { summary }
}
