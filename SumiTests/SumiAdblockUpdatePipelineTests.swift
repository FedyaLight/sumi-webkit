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
        try await super.tearDown()
    }

    func testRuntimeGeneratedSourceIsNotAvailableInAppRuntime() {
        XCTAssertEqual(AdblockRuleGenerationSource.allCases, [.embeddedBundle, .developmentBundle, .futureRemoteBundle])
        XCTAssertNil(AdblockRuleGenerationSource(rawValue: "runtimeGenerated"))
    }

    func testManifestStoreCommitsPreparedShardDefinitionsOnly() async throws {
        let store = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        let manifest = try await PreparedAdblockTestSupport.seedPreparedManifest(in: store)

        let active = try await store.activeManifest()
        let definitions = try await store.compiledShardDefinitions(for: manifest)

        XCTAssertEqual(active?.generationSource, .developmentBundle)
        XCTAssertEqual(active?.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(definitions.count, 1)
        XCTAssertTrue(definitions[0].name.hasPrefix("sumi.adblock.network."))
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
