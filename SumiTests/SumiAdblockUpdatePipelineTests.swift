import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockUpdatePipelineTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.resetForTests()
#endif
        try await super.tearDown()
    }

    func testRuntimeGeneratedSourceIsNotAvailableInAppRuntime() {
        XCTAssertEqual(AdblockRuleGenerationSource.allCases, [.embeddedBundle, .developmentBundle, .remoteReleaseBundle])
        XCTAssertNil(AdblockRuleGenerationSource(rawValue: "runtime" + "Generated"))
    }

    func testManifestStoreCommitsPreparedShardDefinitionsOnly() async throws {
        let store = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        let manifest = try await PreparedAdblockTestSupport.seedPreparedManifest(in: store)

        let active = try await store.activeManifest()
        let definitions = try await store.compiledShardDefinitions(for: manifest)

        XCTAssertEqual(active?.generationSource, .developmentBundle)
        XCTAssertEqual(active?.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(definitions.count, 2)
        XCTAssertTrue(definitions.contains { $0.name.hasPrefix("sumi.tracking.network.") })
        XCTAssertTrue(definitions.contains { $0.name.hasPrefix("sumi.adblock.network.") })
    }

    func testRollbackRestoresPreviousPreparedGeneration() async throws {
        let root = temporaryDirectory()
        let store = AdblockUpdateManifestStore(rootDirectory: root)
        let previous = try await PreparedAdblockTestSupport.seedPreparedManifest(
            in: store,
            generationId: "previous-generation",
            generationSource: .developmentBundle
        )
        _ = try await PreparedAdblockTestSupport.seedPreparedManifest(
            in: store,
            generationId: "active-generation",
            previousGenerationId: previous.activeGenerationId,
            generationSource: .developmentBundle
        )
        let activeManifest = try await store.activeManifest()
        let active = try XCTUnwrap(activeManifest)
        let compiler = RollbackLookupCompiler(
            availableIdentifiers: Set(previous.webKitRuleListIdentifiers)
        )
        let publisher = RecordingPreparedPublisher()
        let coordinator = AdblockUpdateCoordinator(
            manifestStore: store,
            publisher: publisher,
            contentRuleListStore: compiler
        )

        let report = await coordinator.rollbackIfActiveGenerationFailsSmokeCheck()
        let restored = try await store.activeManifest()

        XCTAssertTrue(report.rolledBack)
        XCTAssertEqual(report.activeGenerationId, active.activeGenerationId)
        XCTAssertEqual(report.restoredGenerationId, previous.activeGenerationId)
        XCTAssertEqual(restored?.activeGenerationId, previous.activeGenerationId)
        XCTAssertEqual(publisher.committedManifestIds, [previous.activeGenerationId])
    }

    func testSuccessfulUpdateCleanupRemovesPreviousCompiledRuleListsAndManifestReference() async throws {
        let root = temporaryDirectory()
        let store = AdblockUpdateManifestStore(rootDirectory: root)
        let previous = try await PreparedAdblockTestSupport.seedPreparedManifest(
            in: store,
            generationId: "cleanup-previous-\(UUID().uuidString)",
            generationSource: .developmentBundle
        )
        let active = try await PreparedAdblockTestSupport.seedPreparedManifest(
            in: store,
            generationId: "cleanup-active-\(UUID().uuidString)",
            previousGenerationId: previous.activeGenerationId,
            generationSource: .developmentBundle
        )
        let staleIdentifier = "sumi.adblock.network.stale.0001.deadbeef0000"
        let compiler = RemovalRecordingLookupCompiler(
            availableIdentifiers: Set(active.webKitRuleListIdentifiers)
                .union(previous.webKitRuleListIdentifiers)
                .union([staleIdentifier])
        )
        let collector = AdblockGenerationGarbageCollector(
            manifestStore: store,
            contentRuleListStore: compiler
        )

        let report = await collector.cleanupAfterSuccessfulUpdate()
        let cleanedActiveManifest = try await store.activeManifest()

        XCTAssertEqual(
            report.removedWebKitIdentifiers,
            (previous.webKitRuleListIdentifiers + [staleIdentifier]).sorted()
        )
        XCTAssertEqual(
            compiler.removedIdentifiers.sorted(),
            (previous.webKitRuleListIdentifiers + [staleIdentifier]).sorted()
        )
        XCTAssertTrue(Set(compiler.removedIdentifiers).isDisjoint(with: active.webKitRuleListIdentifiers))
        XCTAssertNil(cleanedActiveManifest?.previousGenerationId)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root
                    .appendingPathComponent("Generated", isDirectory: true)
                    .appendingPathComponent(previous.activeGenerationId, isDirectory: true)
                    .path
            )
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockUpdatePipelineTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

@MainActor
private final class RecordingPreparedPublisher: AdblockRuleListPublishing {
    private(set) var committedManifestIds: [String] = []

    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        PreparedAdblockRuleListPublication(
            manifest: manifest,
            definitions: definitions,
            preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate(
                policy: .enabled(ruleLists: definitions),
                updateEvent: SumiContentBlockerRulesUpdate(
                    rules: [],
                    changes: [:],
                    completionTokens: []
                )
            )
        )
    }

    func commitPublication(_ publication: PreparedAdblockRuleListPublication) {
        committedManifestIds.append(publication.manifest.activeGenerationId)
    }
}

@MainActor
private final class RollbackLookupCompiler: SumiContentRuleListCompiling {
    private let availableIdentifiers: Set<String>

    init(availableIdentifiers: Set<String>) {
        self.availableIdentifiers = availableIdentifiers
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? { nil }
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool { availableIdentifiers.contains(identifier) }
    func compileContentRuleList(forIdentifier identifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList {
        throw AdblockUpdateDiagnostics(summary: "Not needed in rollback test")
    }
    func availableContentRuleListIdentifiers() async -> [String] { availableIdentifiers.sorted() }
    func removeContentRuleList(forIdentifier identifier: String) async throws {}
}

@MainActor
private final class RemovalRecordingLookupCompiler: SumiContentRuleListCompiling {
    private let availableIdentifiers: Set<String>
    private(set) var removedIdentifiers: [String] = []

    init(availableIdentifiers: Set<String>) {
        self.availableIdentifiers = availableIdentifiers
    }

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? { nil }
    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool { availableIdentifiers.contains(identifier) }
    func compileContentRuleList(forIdentifier identifier: String, encodedContentRuleList: String) async throws -> WKContentRuleList {
        throw AdblockUpdateDiagnostics(summary: "Not needed in cleanup test")
    }
    func availableContentRuleListIdentifiers() async -> [String] { availableIdentifiers.sorted() }
    func removeContentRuleList(forIdentifier identifier: String) async throws {
        removedIdentifiers.append(identifier)
    }
}
