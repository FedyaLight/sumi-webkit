import Combine
import CryptoKit
import WebKit
import XCTest

@testable import Sumi

final class AdblockGenerationArchitectureTests: XCTestCase {
    @MainActor
    func testSiteOverridesReloadFromUnifiedDatabase() throws {
        let database = try SumiDatabase.inMemory()
        let url = try XCTUnwrap(URL(string: "https://www.example.com/path"))
        let store = AdblockSitePolicyStore(database: database)

        store.setSiteOverride(.disabled, for: url)

        let reloaded = AdblockSitePolicyStore(database: database)
        XCTAssertEqual(reloaded.override(for: url), .disabled)
    }

    @MainActor
    func testCompiledIdentifierCatalogReloadsAndPersistsThroughUnifiedDatabase() throws {
        let database = try SumiDatabase.inMemory()
        try database.transaction {
            try $0.documents.save(
                ["network": ["compiled.one", "compiled.two"]],
                forKey: "content-blocking.compiled-identifiers"
            )
        }
        let catalog = SumiCompiledContentRuleListCatalog(database: database)

        catalog.forgetIdentifiers(["compiled.one"])

        let persisted = try database.read {
            try $0.documents.value(
                [String: [String]].self,
                forKey: "content-blocking.compiled-identifiers"
            )
        }
        XCTAssertEqual(persisted, ["network": ["compiled.two"]])
    }

    @MainActor
    func testLegacyMigrationResetsEngineStateOnceAndPreservesSelection() throws {
        let suiteName = "SumiAdblockLegacyMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiAdblockLegacyMigrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            XCTAssertNoThrow(try FileManager.default.removeItem(at: root))
        }
        let storageURLs = ["Adblock", "AdblockRemoteBundles", "SelectedFilterBundles"]
            .map { root.appendingPathComponent($0, isDirectory: true) }
        for url in storageURLs {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            try Data("legacy".utf8).write(
                to: url.appendingPathComponent("payload")
            )
        }
        defaults.set("protection", forKey: "settings.protection.level")
        defaults.set("adblock", forKey: "settings.protection.appliedLevel")
        defaults.set(
            ["easylist", "ru-adlist"],
            forKey: "settings.protection.filterListSelection"
        )
        defaults.set(
            ["easylist"],
            forKey: "settings.protection.appliedFilterListSelection"
        )
        defaults.set(
            true,
            forKey: "settings.protection.browserRestartRequired"
        )
        let database = try SumiDatabase.inMemory()
        try database.transaction {
            try $0.documents.save(
                ["network": ["sumi.adblock.legacy"]],
                forKey: SumiCompiledContentRuleListCatalog.documentKey
            )
        }
        let migration = SumiAdblockLegacyMigration(
            userDefaults: defaults,
            database: database,
            storageURLs: storageURLs,
            compiler: RecordingAdblockCompiler(availableIdentifiers: [])
        )

        try migration.prepareOwnedStateIfNeeded()

        XCTAssertTrue(storageURLs.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path) == false
        })
        let persisted = try database.read {
            try $0.documents.value(
                [String: [String]].self,
                forKey: SumiCompiledContentRuleListCatalog.documentKey
            )
        }
        XCTAssertNil(persisted)
        XCTAssertEqual(
            defaults.string(forKey: "settings.protection.level"),
            "adblock"
        )
        XCTAssertEqual(
            defaults.string(forKey: "settings.protection.appliedLevel"),
            "off"
        )
        XCTAssertEqual(
            defaults.stringArray(forKey: "settings.protection.filterListSelection"),
            ["easylist", "ru-adlist"]
        )
        XCTAssertNil(
            defaults.object(
                forKey: "settings.protection.appliedFilterListSelection"
            )
        )
        XCTAssertNil(
            defaults.object(forKey: "settings.protection.browserRestartRequired")
        )

        try FileManager.default.createDirectory(
            at: storageURLs[0],
            withIntermediateDirectories: true
        )
        try migration.prepareOwnedStateIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURLs[0].path))
    }

    @MainActor
    func testLegacyMigrationRemovesOnlyOwnedCompiledRulesOnce() async throws {
        let suiteName = "SumiAdblockCompiledMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let compiler = RecordingAdblockCompiler(
            availableIdentifiers: [
                "sumi.adblock.legacy",
                "sumi.tracking.network.legacy",
                "sumi.tracking.legacy",
                "user.extension.rules",
            ]
        )
        let migration = SumiAdblockLegacyMigration(
            userDefaults: defaults,
            database: try SumiDatabase.inMemory(),
            storageURLs: [],
            compiler: compiler
        )

        try await migration.removeLegacyCompiledRulesIfNeeded()
        try await migration.removeLegacyCompiledRulesIfNeeded()

        XCTAssertEqual(
            compiler.removedIdentifiers.sorted(),
            [
                "sumi.adblock.legacy",
                "sumi.tracking.legacy",
                "sumi.tracking.network.legacy",
            ]
        )
        let userRuleRemains = await compiler.canLookUpContentRuleList(
            forIdentifier: "user.extension.rules"
        )
        XCTAssertTrue(userRuleRemains)
    }

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
        let incomingDirectory = try fixture.archive.generationDirectoryURL(generationId: "incoming")
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
        let generationDirectory = try fixture.archive.generationDirectoryURL(generationId: "generation")
        try Data("{}".utf8).write(to: generationDirectory.appendingPathComponent("network.json"))

        do {
            try await fixture.archive.validateCompiledShardFiles(for: manifest)
            XCTFail("Expected tampered shard validation to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("hash mismatch"))
        }
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

    func testArchiveReadsLegacyLocalGenerationSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(generationId: "legacy")
        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [:]
        )
        let manifestURL = fixture.root.appendingPathComponent(
            "active-generation.json"
        )
        let current = try String(contentsOf: manifestURL, encoding: .utf8)
        let legacy = current.replacingOccurrences(
            of: "\"localSelection\"",
            with: "\"developmentBundle\""
        )
        try Data(legacy.utf8).write(to: manifestURL, options: .atomic)

        let decoded = try await fixture.archive.activeManifest()

        XCTAssertEqual(decoded?.activeGenerationId, manifest.activeGenerationId)
    }

    func testArchiveRejectsArchivedManifestWhoseIdentityDoesNotMatchDirectory() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(generationId: "expected")
        try await fixture.archive.commit(manifest: manifest, stagedCompiledShardURLs: [:])
        let generationDirectory = try fixture.archive.generationDirectoryURL(
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

    @MainActor
    func testRetentionRemovesInactiveGenerationsAndLegacyPreviousReference() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let previousData = Data("[]".utf8)
        let activeData = Data("[ ]".utf8)
        let previousShard = makeShard(id: "previous", generationId: "previous", data: previousData)
        let activeShard = makeShard(id: "active", generationId: "active", data: activeData)
        let previous = makeManifest(generationId: "previous", shards: [previousShard])
        let active = makeManifest(generationId: "active", shards: [activeShard])
        try await fixture.archive.commit(
            manifest: previous,
            stagedCompiledShardURLs: [previousShard.id: try fixture.writeSource(previousData, name: "previous.json")]
        )
        try await fixture.archive.commit(
            manifest: active,
            stagedCompiledShardURLs: [activeShard.id: try fixture.writeSource(activeData, name: "active.json")]
        )
        let activeManifestURL = fixture.root.appendingPathComponent("active-generation.json")
        var legacyManifest = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: activeManifestURL)
            ) as? [String: Any]
        )
        legacyManifest["previousGenerationId"] = "previous"
        try JSONSerialization.data(withJSONObject: legacyManifest).write(
            to: activeManifestURL,
            options: .atomic
        )
        let staleDirectory = try fixture.archive.generationDirectoryURL(generationId: "stale")
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

        let report = await retention.removeInactiveGenerations()

        let previousDirectory = try fixture.archive.generationDirectoryURL(generationId: "previous")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previousDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleDirectory.path))
        XCTAssertEqual(
            compiler.removedIdentifiers,
            [previousShard.webKitIdentifier, staleIdentifier].sorted()
        )
        XCTAssertEqual(
            report.removedWebKitIdentifiers,
            [previousShard.webKitIdentifier, staleIdentifier].sorted()
        )
        let activeGenerationId = try await fixture.archive.activeManifest()?.activeGenerationId
        XCTAssertEqual(activeGenerationId, "active")
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
        let archiveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AdblockStoppedRuntime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: archiveRoot) }
        let archive = AdblockGenerationArchive(rootDirectory: archiveRoot)
        let compiler = RecordingAdblockCompiler(availableIdentifiers: [])
        var sitePolicyCreationCount = 0
        var ruleListRuntimeCreationCount = 0
        let module = SumiAdBlockingModule(
            sitePolicyFactory: {
                sitePolicyCreationCount += 1
                return AdblockSitePolicyStore()
            },
            filterListCatalog: nil,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog(),
            ruleListRuntimeFactory: { isEnabled in
                ruleListRuntimeCreationCount += 1
                return AdblockRuleListRuntime(
                    isRuntimeEnabled: isEnabled,
                    generationArchive: archive,
                    compiler: compiler,
                    compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
                )
            }
        )

        _ = module.surfaceEligibility(for: URL(string: "https://example.com"))
        XCTAssertEqual(sitePolicyCreationCount, 0)
        XCTAssertEqual(ruleListRuntimeCreationCount, 0)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(module.normalTabUserScripts(for: URL(string: "https://example.com")).isEmpty)
        XCTAssertTrue(try module.contentRuleListDefinitions(for: []).isEmpty)
        XCTAssertEqual(ruleListRuntimeCreationCount, 0)

        module.setRuntimeLevel(.adblock)
        _ = module.surfaceEligibility(for: URL(string: "https://example.com"))
        XCTAssertTrue(module.isEnabled)
        XCTAssertTrue(module.isEnabled)
        let enabledURL = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertEqual(module.normalTabUserScripts(for: enabledURL).count, 1)
        XCTAssertEqual(ruleListRuntimeCreationCount, 0)
        XCTAssertEqual(sitePolicyCreationCount, 1)

        module.setSiteOverride(.disabled, for: enabledURL)
        XCTAssertTrue(module.normalTabUserScripts(for: enabledURL).isEmpty)
        XCTAssertEqual(
            module.normalTabUserScripts(for: URL(string: "https://example.org")).count,
            1
        )

        _ = try module.contentRuleListDefinitions(for: [])
        XCTAssertEqual(ruleListRuntimeCreationCount, 1)
        XCTAssertTrue(module.hasLoadedRuntime)

        // No suspension occurs between runtime creation and disable, so the
        // queued startup task must be cancelled before it can touch the archive.
        module.setRuntimeLevel(.off)
        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.hasLoadedRuntime)
        XCTAssertTrue(module.normalTabUserScripts(for: enabledURL).isEmpty)
        await Task.yield()
        XCTAssertFalse(FileManager.default.fileExists(atPath: archiveRoot.path))
    }

    @MainActor
    func testAdvancedBlockingBootstrapWithheldForGenerationWithoutAdvancedCapability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = makeManifest(generationId: "plain")
        try await fixture.archive.commit(manifest: manifest, stagedCompiledShardURLs: [:])

        let module = makeEnabledModule(archive: fixture.archive)
        module.setRuntimeLevel(.adblock)
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        // Manifest not loaded yet: keep the conservative bootstrap injection.
        XCTAssertEqual(module.normalTabUserScripts(for: url).count, 1)

        _ = try await module.restoreLocalGenerationForStartup()
        XCTAssertNotNil(module.activeManifestIfLoaded())

        // The loaded generation has no advanced-blocking capability, so the
        // lookup could never return a configuration; the per-frame bootstrap
        // must be withheld instead of running in every frame of every page.
        XCTAssertTrue(module.normalTabUserScripts(for: url).isEmpty)
    }

    @MainActor
    func testAdvancedBlockingBootstrapKeptForGenerationWithAdvancedCapability() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let artifacts = try makeAdvancedBlockingArtifacts(root: fixture.root)
        let manifest = makeManifest(
            generationId: "advanced",
            advancedBlocking: artifacts.descriptor
        )
        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [:],
            stagedAdvancedArtifactURLs: artifacts.sources
        )

        let module = makeEnabledModule(archive: fixture.archive)
        module.setRuntimeLevel(.adblock)
        _ = try await module.restoreLocalGenerationForStartup()
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        XCTAssertEqual(module.normalTabUserScripts(for: url).count, 1)
    }

    @MainActor
    func testAdvancedBlockingBootstrapWithheldForUnsupportedRuntime() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let artifacts = try makeAdvancedBlockingArtifacts(
            root: fixture.root,
            runtimeVersion: "unsupported"
        )
        let manifest = makeManifest(
            generationId: "unsupported",
            advancedBlocking: artifacts.descriptor
        )
        try await fixture.archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: [:],
            stagedAdvancedArtifactURLs: artifacts.sources
        )

        let module = makeEnabledModule(archive: fixture.archive)
        module.setRuntimeLevel(.adblock)
        _ = try await module.restoreLocalGenerationForStartup()

        XCTAssertTrue(
            module.normalTabUserScripts(
                for: URL(string: "https://example.com")
            ).isEmpty
        )
    }

    @MainActor
    private func makeEnabledModule(archive: AdblockGenerationArchive) -> SumiAdBlockingModule {
        SumiAdBlockingModule(
            sitePolicyFactory: { AdblockSitePolicyStore() },
            filterListCatalog: nil,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog(),
            ruleListRuntimeFactory: { isEnabled in
                AdblockRuleListRuntime(
                    isRuntimeEnabled: isEnabled,
                    generationArchive: archive,
                    compiler: RecordingAdblockCompiler(availableIdentifiers: []),
                    compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
                )
            }
        )
    }

    private func makeAdvancedBlockingArtifacts(
        root: URL,
        runtimeVersion: String = "4.3.0"
    ) throws -> (
        descriptor: AdvancedBlockingGenerationDescriptor,
        sources: [String: URL]
    ) {
        let fixtureRoot = root.appendingPathComponent(
            "AdvancedArtifacts",
            isDirectory: true
        )
        let values: [(AdvancedBlockingArtifactRole, String, Data)] = [
            (.ruleStorage, ".webext/rules.bin", Data("rules".utf8)),
            (.engineIndex, ".webext/engine.bin", Data("engine".utf8)),
            (.engineMetadata, ".webext/meta.bin", Data("meta".utf8)),
        ]
        var sources: [String: URL] = [:]
        let artifacts = try values.map { role, relativePath, data in
            let source = fixtureRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: source.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: source)
            sources[relativePath] = source
            return AdvancedBlockingGenerationDescriptor.Artifact(
                role: role,
                relativePath: relativePath,
                hash: SHA256.hash(data: data)
                    .map { String(format: "%02x", $0) }
                    .joined(),
                byteSize: data.count
            )
        }
        let descriptor = AdvancedBlockingGenerationDescriptor(
            format: AdvancedBlockingGenerationDescriptor.safariConverterFormat,
            schemaVersion: 1,
            runtimeVersion: runtimeVersion,
            ruleCount: values.count,
            artifacts: artifacts
        )
        return (descriptor, sources)
    }

    private func makeManifest(
        schemaVersion: Int = AdblockCompiledGenerationManifest.currentSchemaVersion,
        generationId: String,
        shards: [NativeContentBlockingShardDescriptor] = [],
        advancedBlocking: AdvancedBlockingGenerationDescriptor? = nil
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: schemaVersion,
            activeGenerationId: generationId,
            selectedFilterLists: [],
            networkShards: shards,
            advancedBlocking: advancedBlocking,
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 0),
            bundleProfileId: SumiProtectionBundleProfile.adblock
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
            webKitIdentifier: "sumi.adblock.\(generationId).\(id)",
            contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            approximateRuleCount: 1,
            jsonByteCount: data.count
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
