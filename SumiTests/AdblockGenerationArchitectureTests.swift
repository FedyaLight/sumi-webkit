import Combine
import CryptoKit
import WebKit
import XCTest

@testable import Sumi

final class AdblockGenerationArchitectureTests: XCTestCase {
    func testArchiveRejectsIncompleteShardSetWithoutSwitchingActiveManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stable = makeManifest(generationId: "stable")
        try await fixture.archive.commit(manifest: stable, stagedCompiledShardURLs: [:])
        let incoming = makeManifest(
            generationId: "incoming",
            shards: [makeShard(id: "incoming-network", generationId: "incoming", data: Data("[]".utf8))]
        )

        do {
            try await fixture.archive.commit(manifest: incoming, stagedCompiledShardURLs: [:])
            XCTFail("Expected an incomplete staging set to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("staging set mismatch"))
        }

        let active = try await fixture.archive.activeManifest()
        XCTAssertEqual(active?.activeGenerationId, "stable")
        let incomingDirectory = try await fixture.archive.generationDirectoryURL(generationId: "incoming")
        XCTAssertFalse(FileManager.default.fileExists(atPath: incomingDirectory.path))
    }

    func testArchiveDetectsPersistedShardTampering() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalData = Data("[]".utf8)
        let shard = makeShard(id: "network", generationId: "generation", data: originalData)
        let source = try fixture.writeSource(originalData, name: "network.json")
        let manifest = makeManifest(generationId: "generation", shards: [shard])
        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [shard.id: source]
        )
        let generationDirectory = try await fixture.archive.generationDirectoryURL(generationId: "generation")
        try Data("{}".utf8).write(to: generationDirectory.appendingPathComponent("network.json"))

        do {
            try await fixture.archive.validateCompiledShardFiles(for: manifest)
            XCTFail("Expected tampered shard validation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("hash mismatch"))
        }
    }

    func testArchiveRejectsSelfReferentialRollbackGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(
            generationId: "cycle",
            previousGenerationId: "cycle"
        )

        await XCTAssertThrowsErrorAsync {
            try await fixture.archive.commit(
                manifest: manifest,
                stagedCompiledShardURLs: [:]
            )
        }
        let activeManifest = try await fixture.archive.activeManifest()
        XCTAssertNil(activeManifest)
    }

    func testArchiveRejectsFutureManifestSchema() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(
            schemaVersion: AdblockCompiledGenerationManifest.currentSchemaVersion + 1,
            generationId: "future"
        )

        await XCTAssertThrowsErrorAsync {
            try await fixture.archive.commit(
                manifest: manifest,
                stagedCompiledShardURLs: [:]
            )
        }
        let activeManifest = try await fixture.archive.activeManifest()
        XCTAssertNil(activeManifest)
    }

    func testArchiveRejectsArchivedManifestWhoseIdentityDoesNotMatchDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(generationId: "expected")
        try await fixture.archive.commit(manifest: manifest, stagedCompiledShardURLs: [:])
        let generationDirectory = try await fixture.archive.generationDirectoryURL(
            generationId: "expected"
        )
        let manifestURL = generationDirectory.appendingPathComponent("manifest.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        object["activeGenerationId"] = "other"
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL, options: .atomic)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.archive.archivedManifest(generationId: "expected")
        }
    }

    func testArchiveRejectsTamperedWebKitIdentifierIndex() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let data = Data("[]".utf8)
        let shard = makeShard(id: "network", generationId: "generation", data: data)
        let manifest = makeManifest(generationId: "generation", shards: [shard])
        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [
                shard.id: try fixture.writeSource(data, name: "identifier-index.json"),
            ]
        )
        let manifestURL = fixture.root.appendingPathComponent("active-generation.json")
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        object["webKitRuleListIdentifiers"] = ["sumi.adblock.spoofed"]
        try JSONSerialization.data(withJSONObject: object).write(to: manifestURL, options: .atomic)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.archive.activeManifest()
        }
    }

    @MainActor
    func testRecoveryLeavesDurableActivePointerUntouchedWhenWebKitPreparationFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let previousData = Data("[]".utf8)
        let activeData = Data("[ ]".utf8)
        let previousShard = makeShard(id: "previous", generationId: "previous", data: previousData)
        let activeShard = makeShard(id: "active", generationId: "active", data: activeData)
        let previous = makeManifest(generationId: "previous", shards: [previousShard])
        let active = makeManifest(
            generationId: "active",
            previousGenerationId: "previous",
            shards: [activeShard]
        )
        try await fixture.archive.commit(
            manifest: previous,
            stagedCompiledShardURLs: [previousShard.id: try fixture.writeSource(previousData, name: "previous.json")]
        )
        try await fixture.archive.commit(
            manifest: active,
            stagedCompiledShardURLs: [activeShard.id: try fixture.writeSource(activeData, name: "active.json")]
        )
        let publisher = FailingAdblockPublisher()
        let compiler = RecordingAdblockCompiler(availableIdentifiers: [previousShard.webKitIdentifier])
        let recovery = AdblockGenerationRecovery(
            archive: fixture.archive,
            publisher: publisher,
            contentRuleListStore: compiler
        )

        let report = await recovery.restorePreviousGenerationIfNeeded()

        XCTAssertFalse(report.rolledBack)
        XCTAssertEqual(publisher.prepareCount, 1)
        XCTAssertEqual(publisher.commitCount, 0)
        let durableActiveManifest = try await fixture.archive.activeManifest()
        XCTAssertEqual(durableActiveManifest?.activeGenerationId, "active")
    }

    @MainActor
    func testRetentionKeepsPreviousRollbackGenerationAndItsWebKitRules() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let previousData = Data("[]".utf8)
        let activeData = Data("[ ]".utf8)
        let previousShard = makeShard(id: "previous", generationId: "previous", data: previousData)
        let activeShard = makeShard(id: "active", generationId: "active", data: activeData)
        let previous = makeManifest(generationId: "previous", shards: [previousShard])
        let active = makeManifest(
            generationId: "active",
            previousGenerationId: "previous",
            shards: [activeShard]
        )
        try await fixture.archive.commit(
            manifest: previous,
            stagedCompiledShardURLs: [previousShard.id: try fixture.writeSource(previousData, name: "previous.json")]
        )
        try await fixture.archive.commit(
            manifest: active,
            stagedCompiledShardURLs: [activeShard.id: try fixture.writeSource(activeData, name: "active.json")]
        )
        let staleDirectory = try await fixture.archive.generationDirectoryURL(generationId: "stale")
        try FileManager.default.createDirectory(at: staleDirectory, withIntermediateDirectories: true)
        let staleIdentifier = "sumi.adblock.stale"
        let compiler = RecordingAdblockCompiler(
            availableIdentifiers: [
                activeShard.webKitIdentifier,
                previousShard.webKitIdentifier,
                staleIdentifier,
            ]
        )
        let retention = AdblockGenerationRetention(
            archive: fixture.archive,
            contentRuleListStore: compiler
        )

        let report = await retention.removeUnrecoverableGenerations()

        let previousDirectory = try await fixture.archive.generationDirectoryURL(generationId: "previous")
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDirectory.path))
        XCTAssertEqual(compiler.removedIdentifiers, [staleIdentifier])
        XCTAssertEqual(report.removedWebKitIdentifiers, [staleIdentifier])
        let retainedActiveManifest = try await fixture.archive.activeManifest()
        XCTAssertEqual(retainedActiveManifest?.previousGenerationId, "previous")
    }

    func testRemoteReleaseAssetIndexRejectsDuplicatesInsteadOfTrapping() throws {
        let release = try JSONDecoder().decode(
            SumiProtectionBundleGitHubRelease.self,
            from: Data(
                """
                {
                  "tag_name":"release",
                  "html_url":null,
                  "draft":false,
                  "prerelease":false,
                  "published_at":null,
                  "assets":[
                    {"name":"duplicate","size":2,"browser_download_url":"https://example.com/a","digest":null},
                    {"name":"duplicate","size":2,"browser_download_url":"https://example.com/b","digest":null}
                  ]
                }
                """.utf8
            )
        )

        XCTAssertThrowsError(try SumiProtectionBundleReleaseValidator().approvedAssetIndex(for: release)) {
            XCTAssertEqual(
                $0 as? SumiProtectionBundleRemoteUpdateError,
                .duplicateAssetName("duplicate")
            )
        }
    }

    func testRemoteCacheRefusesReplacementWhenInstalledVersionMetadataIsCorrupt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileId = "profile"
        let bundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: fixture.root
        )
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: bundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName)
        )
        let cache = SumiProtectionBundleCache(rootDirectory: fixture.root)

        XCTAssertThrowsError(
            try cache.rejectDowngradeIfNeeded(
                profileId: profileId,
                incomingReleaseVersion: "99999999"
            )
        ) { error in
            guard let remoteError = error as? SumiProtectionBundleRemoteUpdateError,
                  case .cacheCommitFailed = remoteError
            else {
                return XCTFail("Expected fail-closed metadata validation, got \(error)")
            }
        }
    }

    func testCacheTransactionRestoresPreviousBundleWhenPostCommitValidationFails() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileId = "profile"
        let destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: fixture.root
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let previousMarker = destination.appendingPathComponent("previous.txt")
        try Data("previous".utf8).write(to: previousMarker)
        let validator = FailSecondBundleValidation()
        var transaction: SumiProtectionBundleCacheTransaction? = try SumiProtectionBundleCacheTransaction(
            profileId: profileId,
            rootDirectory: fixture.root,
            payloadValidator: validator
        )
        try transaction?.write(Data("incoming".utf8), relativePath: "incoming.txt")

        XCTAssertThrowsError(
            try transaction?.commit(
                expectedIdentity: SumiProtectionBundleIdentity(
                    profileId: profileId,
                    bundleId: "bundle",
                    generationId: "generation"
                )
            )
        )
        transaction = nil

        XCTAssertEqual(try Data(contentsOf: previousMarker), Data("previous".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("incoming.txt").path))
    }

    func testRemoteCacheCommitRechecksVersionBeforeReplacingInstalledBundle() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileId = "profile"
        let destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: fixture.root
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let installedMarker = destination.appendingPathComponent("installed.txt")
        try Data("newer".utf8).write(to: installedMarker)
        let installedMetadata = SumiAdblockPreparedBundleRemoteMetadata(
            releaseVersion: "3",
            releaseTag: "3"
        )
        try JSONEncoder().encode(installedMetadata).write(
            to: destination.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName)
        )
        var transaction: SumiProtectionBundleCacheTransaction? = try SumiProtectionBundleCacheTransaction(
            profileId: profileId,
            rootDirectory: fixture.root,
            payloadValidator: AcceptBundleValidation()
        )
        try transaction?.write(Data("older".utf8), relativePath: "incoming.txt")
        let cache = SumiProtectionBundleCache(rootDirectory: fixture.root)
        let identity = SumiProtectionBundleIdentity(
            profileId: profileId,
            bundleId: "older-bundle",
            generationId: "older-generation"
        )
        let pendingTransaction = try XCTUnwrap(transaction)

        XCTAssertThrowsError(
            try cache.commit(
                pendingTransaction,
                expectedIdentity: identity,
                incomingReleaseVersion: "2"
            )
        ) { error in
            XCTAssertEqual(
                error as? SumiProtectionBundleRemoteUpdateError,
                .releaseDowngradeRejected(current: "3", incoming: "2")
            )
        }
        transaction = nil

        XCTAssertEqual(try Data(contentsOf: installedMarker), Data("newer".utf8))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("incoming.txt").path
            )
        )
    }

    @MainActor
    func testTaskRegistrySupersedesAndDrainsRetiredWork() async {
        enum TaskKey: Hashable {
            case work
        }
        let registry = ContentBlockingTaskRegistry<TaskKey>()
        let firstStarted = expectation(description: "first task started")
        let firstCancelled = expectation(description: "first task cancelled")
        let replacementFinished = expectation(description: "replacement finished")
        registry.replaceTask(for: .work) {
            firstStarted.fulfill()
            while !Task.isCancelled {
                await Task.yield()
            }
            firstCancelled.fulfill()
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        registry.replaceTask(for: .work) {
            replacementFinished.fulfill()
        }
        await registry.drainTasksForTests()

        await fulfillment(of: [firstCancelled, replacementFinished], timeout: 1)
    }

    @MainActor
    func testMutationGateCancelsQueuedWorkAndInvalidatesActiveLeaseWhenStopped() async throws {
        let gate = AdblockGenerationMutationGate()
        let acquiredLease = await gate.acquire()
        let activeLease = try XCTUnwrap(acquiredLease)
        let waiterStarted = expectation(description: "queued mutation started waiting")
        let queuedMutation = Task { @MainActor in
            waiterStarted.fulfill()
            return await gate.acquire()
        }
        await fulfillment(of: [waiterStarted], timeout: 1)

        queuedMutation.cancel()

        let cancelledLease = await queuedMutation.value
        XCTAssertNil(cancelledLease)
        XCTAssertTrue(gate.owns(activeLease))
        gate.stop()
        XCTAssertFalse(gate.owns(activeLease))
        gate.release(activeLease)
        let stoppedLease = await gate.acquire()
        XCTAssertNil(stoppedLease)
    }

    @MainActor
    func testPublicationNotifiesManifestObserversAfterContentBlockingPolicyCommit() async throws {
        let compiler = RecordingAdblockCompiler(availableIdentifiers: [])
        let provider = AdblockManifestRuleListProvider(manifest: nil)
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: provider
        )
        await service.drainScheduledTasksForTests()
        let publisher = AdblockRuleListPublisher(
            ruleListProvider: provider,
            contentBlockingService: service
        )
        let definition = SumiContentRuleListDefinition(
            name: "published",
            encodedContentRuleList: "[]",
            storeIdentifierOverride: "sumi.adblock.published"
        )
        var policyWasEnabledAtNotification: Bool?
        var manifestWasPublishedAtContentUpdate: Bool?
        let providerObservation = provider.changesPublisher.sink {
            policyWasEnabledAtNotification = service.privacyConfigurationManager
                .sumiPrivacyConfig
                .isEnabled(featureKey: .contentBlocking)
        }
        let contentObservation = service.updatesPublisher.sink { _ in
            guard provider.activeManifest != nil else { return }
            manifestWasPublishedAtContentUpdate = provider.activeManifest?.activeGenerationId == "published"
        }
        let publication = PreparedAdblockRuleListPublication(
            manifest: makeManifest(generationId: "published"),
            definitions: [definition.metadataOnly()],
            preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate(
                policy: .enabled(ruleLists: [definition.metadataOnly()]),
                updateEvent: SumiContentBlockerRulesUpdate(
                    rules: [],
                    changes: [:],
                    completionTokens: []
                )
            )
        )

        publisher.commitPublication(publication)

        XCTAssertEqual(policyWasEnabledAtNotification, true)
        XCTAssertEqual(manifestWasPublishedAtContentUpdate, true)
        withExtendedLifetime((providerObservation, contentObservation)) {}
        service.stopRuntime()
        await service.drainScheduledTasksForTests(cancel: true)
    }

    @MainActor
    func testStoppedContentServiceRejectsLatePreparedPublication() async {
        let compiler = RecordingAdblockCompiler(availableIdentifiers: [])
        let provider = AdblockManifestRuleListProvider(manifest: nil)
        let service = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: provider
        )
        await service.drainScheduledTasksForTests()
        service.stopRuntime()
        let publisher = AdblockRuleListPublisher(
            ruleListProvider: provider,
            contentBlockingService: service
        )
        let definition = SumiContentRuleListDefinition(
            name: "late",
            encodedContentRuleList: "[]",
            storeIdentifierOverride: "sumi.adblock.late"
        )
        let publication = PreparedAdblockRuleListPublication(
            manifest: makeManifest(generationId: "late"),
            definitions: [definition.metadataOnly()],
            preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate(
                policy: .enabled(ruleLists: [definition.metadataOnly()]),
                updateEvent: SumiContentBlockerRulesUpdate(
                    rules: [],
                    changes: [:],
                    completionTokens: []
                )
            )
        )

        publisher.commitPublication(publication)
        await Task.yield()

        XCTAssertFalse(
            service.privacyConfigurationManager.sumiPrivacyConfig
                .isEnabled(featureKey: .contentBlocking)
        )
        XCTAssertTrue(service.latestRuleListIdentifiers.isEmpty)
        await service.drainScheduledTasksForTests(cancel: true)
    }

    @MainActor
    func testDisabledModuleDoesNotCreateRuntimeAndStopsQueuedStartupBeforeDiskWork() async throws {
        let suiteName = "AdblockGenerationArchitectureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdblockStoppedRuntime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }
        let archive = AdblockGenerationArchive(rootDirectory: archiveRoot)
        let compiler = RecordingAdblockCompiler(availableIdentifiers: [])
        var sitePolicyCreationCount = 0
        var ruleListRuntimeCreationCount = 0
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            sitePolicyFactory: {
                sitePolicyCreationCount += 1
                return AdblockSitePolicyStore(userDefaults: defaults)
            },
            preparedBundleResourceURL: nil,
            preparedBundleRemoteRootURL: nil,
            preparedBundleGeneratedRootURL: nil,
            ruleListRuntimeFactory: { isEnabled in
                ruleListRuntimeCreationCount += 1
                return AdblockRuleListRuntime(
                    isRuntimeEnabled: isEnabled,
                    generationArchive: archive,
                    compiler: compiler,
                    embeddedBundleURLProvider: { nil }
                )
            }
        )

        _ = module.surfaceEligibility(for: URL(string: "https://example.com"))
        XCTAssertEqual(sitePolicyCreationCount, 0)
        XCTAssertEqual(ruleListRuntimeCreationCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(try module.contentRuleListDefinitions(for: []).isEmpty)
        XCTAssertEqual(ruleListRuntimeCreationCount, 0)

        module.setRuntimeLevel(.adblock)
        _ = module.surfaceEligibility(for: URL(string: "https://example.com"))
        XCTAssertTrue(module.isEnabled)
        XCTAssertTrue(module.isPreparedBundleRuntimeEnabled)
        XCTAssertEqual(sitePolicyCreationCount, 1)

        module.setRuntimeLevel(.protection)
        _ = module.surfaceEligibility(for: URL(string: "https://example.com"))
        XCTAssertFalse(module.isEnabled)
        XCTAssertTrue(module.isPreparedBundleRuntimeEnabled)
        XCTAssertEqual(sitePolicyCreationCount, 1)
        _ = try module.contentRuleListDefinitions(for: [])
        XCTAssertEqual(ruleListRuntimeCreationCount, 1)
        XCTAssertTrue(module.hasLoadedRuntime)

        // No suspension occurs between runtime creation and disable, so the
        // queued startup task must be cancelled before it can touch the archive.
        module.setRuntimeLevel(.off)
        XCTAssertFalse(module.isPreparedBundleRuntimeEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        await Task.yield()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveRoot.path))
    }

    private func makeManifest(
        schemaVersion: Int = 1,
        generationId: String,
        previousGenerationId: String? = nil,
        shards: [NativeContentBlockingShardDescriptor] = []
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: schemaVersion,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 0),
            selectedFilterLists: [],
            networkShards: shards,
            nativeCSSShards: [],
            nativeCompiler: nil,
            nativeCompilerSourceLists: nil,
            compilerDiagnosticsSummary: "test",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 0),
            previousGenerationId: previousGenerationId,
            generationSource: .remoteReleaseBundle
        )
    }

    private func makeShard(
        id: String,
        generationId: String,
        data: Data
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: id,
            generationId: generationId,
            kind: .network,
            sourceListIdentifiers: [],
            sourceCategories: [],
            webKitIdentifier: "sumi.adblock.\(generationId).\(id)",
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            approximateRuleCount: 1,
            jsonByteCount: data.count,
            compilerIdentity: nil,
            diagnosticsSummary: "test"
        )
    }
}

private struct Fixture {
    let root: URL
    let archive: AdblockGenerationArchive

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdblockGenerationArchitectureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        archive = AdblockGenerationArchive(rootDirectory: root)
    }

    func writeSource(_ data: Data, name: String) throws -> URL {
        let url = root.appendingPathComponent("Sources", isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private final class FailingAdblockPublisher: AdblockRuleListPublishing {
    private(set) var prepareCount = 0
    private(set) var commitCount = 0

    func preparePublication(
        manifest _: AdblockCompiledGenerationManifest,
        definitions _: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        prepareCount += 1
        throw TestError.publicationFailed
    }

    func commitPublication(_: PreparedAdblockRuleListPublication) {
        commitCount += 1
    }
}

@MainActor
private final class RecordingAdblockCompiler: SumiContentRuleListCompiling, @unchecked Sendable {
    private var availableIdentifiers: Set<String>
    private(set) var removedIdentifiers = [String]()

    init(availableIdentifiers: Set<String>) {
        self.availableIdentifiers = availableIdentifiers
    }

    func lookUpContentRuleList(forIdentifier _: String) async -> WKContentRuleList? { nil }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        availableIdentifiers.contains(identifier)
    }

    func compileContentRuleList(
        forIdentifier _: String,
        encodedContentRuleList _: String
    ) async throws -> WKContentRuleList {
        throw TestError.publicationFailed
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        availableIdentifiers.sorted()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        availableIdentifiers.remove(identifier)
        removedIdentifiers.append(identifier)
    }
}

private final class FailSecondBundleValidation: SumiProtectionBundlePayloadValidating, @unchecked Sendable {
    private var validationCount = 0

    func validateBundle(
        at _: URL
    ) throws -> SumiProtectionBundleValidationReceipt {
        validationCount += 1
        if validationCount == 3 {
            throw TestError.publicationFailed
        }
        return SumiProtectionBundleValidationReceipt(
            identity: SumiProtectionBundleIdentity(
                profileId: "profile",
                bundleId: "bundle",
                generationId: "generation"
            ),
            payloadFingerprint: validationCount == 1
                ? "candidate"
                : "previous"
        )
    }
}

private struct AcceptBundleValidation: SumiProtectionBundlePayloadValidating {
    func validateBundle(
        at _: URL
    ) throws -> SumiProtectionBundleValidationReceipt {
        SumiProtectionBundleValidationReceipt(
            identity: SumiProtectionBundleIdentity(
                profileId: "profile",
                bundleId: "older-bundle",
                generationId: "older-generation"
            ),
            payloadFingerprint: "accepted"
        )
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {}
}

private enum TestError: LocalizedError {
    case publicationFailed

    var errorDescription: String? { "publication failed" }
}
