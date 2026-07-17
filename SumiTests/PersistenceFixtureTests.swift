import CoreData
import Foundation
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class PersistenceFixtureTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func setUp() {
        super.setUp()
        temporaryDirectories.removeAll()
    }

    override func tearDown() {
        for directory in temporaryDirectories {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                // A failed cleanup is harmless and the system temporary root
                // remains the final owner.
            }
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testPreVersionedStartupStoreFixtureMigratesWithoutQuarantine()
        throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("default.store")
        let quarantineURL = directory.appendingPathComponent(
            "StartupPersistenceQuarantine",
            isDirectory: true
        )
        for suffix in ["", "-wal", "-shm"] {
            try copyFixture(
                "startup-swiftdata/default.store\(suffix)",
                to: URL(fileURLWithPath: storeURL.path + suffix)
            )
        }
        let container = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: storeURL,
            quarantineRootURL: quarantineURL,
            openPersistentContainer: { url in
                try SumiStartupPersistence.makeContainer(
                    configuration: ModelConfiguration(url: url)
                )
            }
        )
        let profiles = try ModelContext(container).fetch(
            FetchDescriptor<ProfileEntity>(
                predicate: #Predicate {
                    $0.name == "Pre-versioned Fixture Profile"
                }
            )
        )

        XCTAssertEqual(profiles.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: quarantineURL.path),
            "A compatible historical schema must migrate without quarantine"
        )
    }

    func testBookmarkV2SQLiteFixtureLightweightMigratesToCurrentModel()
        throws {
        let directory = try makeTemporaryDirectory()
        try copyFixture(
            "bookmarks/SumiBookmarks-v2.sqlite",
            to: directory.appendingPathComponent("SumiBookmarks.sqlite")
        )

        let database = SumiBookmarkDatabase(directory: directory)
        XCTAssertTrue(database.isAvailable)
        let context = database.makeContext(
            concurrencyType: .privateQueueConcurrencyType,
            name: "PersistenceFixtureBookmarksV2"
        )
        var fixtureBookmark: BookmarkEntity?
        var fetchError: Error?
        context.performAndWait {
            let request = BookmarkEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "uuid == %@",
                "fixture-bookmark-v2"
            )
            do {
                fixtureBookmark = try context.fetch(request).first
            } catch {
                fetchError = error
            }
        }
        if let fetchError { throw fetchError }
        XCTAssertEqual(fixtureBookmark?.title, "Shipped Bookmark V2")
        XCTAssertEqual(
            fixtureBookmark?.url,
            "https://fixture.example/bookmark-v2"
        )
        XCTAssertFalse(fixtureBookmark?.isStub ?? true)
    }

    func testLegacyPermissionFilesMigrateToCanonicalSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        try copyFixture(
            "permissions/legacy-anti-abuse-v1.json",
            to: directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
            )
        )
        try copyFixture(
            "permissions/legacy-site-activity-v1.json",
            to: directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.legacySiteActivityFileName
            )
        )

        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: nil,
            storageDirectory: directory
        )
        XCTAssertEqual(
            authority.persistenceDiagnostics.loadOutcome,
            .loadedLegacySnapshots
        )

        let key = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(
                string: "https://fixture.example"
            ),
            topOrigin: SumiPermissionOrigin(
                string: "https://fixture.example"
            ),
            permissionType: .camera,
            profilePartitionId: "00000000-0000-0000-0000-000000000101"
        )
        let store = SumiPermissionAntiAbuseStore(
            persistenceAuthority: authority
        )
        let events = await store.events(
            for: key,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(events.map(\.id), ["fixture-dismissed-camera"])

        let didFlush = await authority.flushPendingWrites()
        XCTAssertTrue(didFlush)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.canonicalFileName
                ).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    SumiPermissionPersistenceAuthority.legacyAntiAbuseFileName
                ).path
            )
        )
    }

    func testPermissionCanonicalFixtureLoadsAndFutureAndMalformedFailClosed()
        async throws {
        let loadedDirectory = try makeTemporaryDirectory()
        try copyFixture(
            "permissions/canonical-v1.json",
            to: loadedDirectory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.canonicalFileName
            )
        )
        let loaded = SumiPermissionPersistenceAuthority(
            userDefaults: nil,
            storageDirectory: loadedDirectory
        )
        XCTAssertEqual(loaded.persistenceDiagnostics.loadOutcome, .loadedFile)

        for fixtureName in [
            "permissions/unsupported-future-v2.json",
            "permissions/malformed.json",
        ] {
            let directory = try makeTemporaryDirectory()
            let canonicalURL = directory.appendingPathComponent(
                SumiPermissionPersistenceAuthority.canonicalFileName
            )
            try copyFixture(fixtureName, to: canonicalURL)
            let original = try Data(contentsOf: canonicalURL)

            let authority = SumiPermissionPersistenceAuthority(
                userDefaults: nil,
                storageDirectory: directory
            )
            switch authority.persistenceDiagnostics.loadOutcome {
            case .unsupportedFileVersion, .failedFileDecode:
                break
            default:
                XCTFail(
                    "Expected fail-closed classification for \(fixtureName), got \(authority.persistenceDiagnostics.loadOutcome)"
                )
            }
            XCTAssertEqual(try Data(contentsOf: canonicalURL), original)
            XCTAssertEqual(
                try Data(
                    contentsOf: canonicalURL.appendingPathExtension(
                        "unreadable"
                    )
                ),
                original
            )
        }
    }

    func testSplitArchiveFixturesMigrateV1AndRejectFutureVersion() throws {
        let legacy = try fixtureData("tabs/split-groups-v1.json")
        guard case .legacyVersion1(let groups) = try TabPersistenceCodec()
            .decodeSplitGroupArchive(from: legacy)
        else {
            return XCTFail("Expected the shipped v1 split archive")
        }
        XCTAssertEqual(
            groups.first?.id,
            UUID(uuidString: "00000000-0000-0000-0000-000000000200")
        )

        var repairReasons = Set<String>()
        let migrated = TabRestoreRepair.restoreSplitGroups(
            from: legacy,
            regularTabIDs: [
                UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            ],
            shortcutReturnPlacementsByPinID: [:],
            repairReasons: &repairReasons
        )
        XCTAssertEqual(migrated.count, 1)
        XCTAssertTrue(
            repairReasons.contains(
                LegacySplitGroupV1RepairReason.migratedArchive
            )
        )

        XCTAssertThrowsError(
            try TabPersistenceCodec().decodeSplitGroupArchive(
                from: fixtureData(
                    "tabs/split-groups-unsupported-v3.json"
                )
            )
        )
    }

    func testWindowAndLastSessionLegacyFixturesRemainReadable() throws {
        let result = WindowSessionSnapshotCodec().decode(
            try fixtureData("sessions/window-session-legacy-split.json"),
            source: .overrideFile(
                fixtureURL("sessions/window-session-legacy-split.json")
            )
        )
        guard case .loaded(let window, _) = result else {
            return XCTFail("Expected legacy window-session fixture to decode")
        }
        XCTAssertEqual(
            window.legacySplitSessionForMigration?.rightTabId,
            UUID(uuidString: "00000000-0000-0000-0000-000000000303")
        )

        let suiteName = "PersistenceFixtureTests.LastSession.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try fixtureData(
                "sessions/last-session-windows-legacy-array.json"
            ),
            forKey: "\(SumiAppIdentity.runtimeBundleIdentifier).history.lastSessionWindows"
        )
        let lastSession = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(
            lastSession.snapshots.map(\.id),
            [UUID(uuidString: "00000000-0000-0000-0000-000000000310")!]
        )
        XCTAssertNil(lastSession.tabSnapshot)
    }

    @MainActor
    func testLogicalBackupFixturesReadV1AndRejectFutureAndMalformed()
        throws {
        let service = SumiBackupService()
        let archive = try service.readBackup(
            from: fixtureData("backups/logical-backup-v1.sumibackup")
        )
        XCTAssertEqual(archive.version, 1)
        XCTAssertEqual(archive.data.profiles.map(\.name), ["Fixture Profile"])

        for fixtureName in [
            "backups/logical-backup-unsupported-v2.sumibackup",
            "backups/logical-backup-malformed.sumibackup",
        ] {
            XCTAssertThrowsError(
                try service.readBackup(from: fixtureData(fixtureName))
            ) { error in
                XCTAssertTrue(error is SumiImportExportError)
            }
        }
    }

    func testImportJournalFixturesReadV1AndRejectFutureAndMalformed()
        async throws {
        let directory = try makeTemporaryDirectory()
        let journalURL = directory.appendingPathComponent(
            "ImportTransaction.json"
        )
        let journal = SumiImportTransactionFileJournal(fileURL: journalURL)

        try copyFixture("import/import-journal-v1.json", to: journalURL)
        let loaded = try await journal.load()
        XCTAssertEqual(loaded?.version, 1)
        XCTAssertEqual(loaded?.phase, .prepared)

        for fixtureName in [
            "import/import-journal-unsupported-v2.json",
            "import/import-journal-malformed.json",
        ] {
            try FileManager.default.removeItem(at: journalURL)
            try copyFixture(fixtureName, to: journalURL)
            do {
                _ = try await journal.load()
                XCTFail("Expected \(fixtureName) to fail closed")
            } catch {
                XCTAssertEqual(try Data(contentsOf: journalURL), try fixtureData(fixtureName))
            }
        }
    }

    func testFaviconMetadataFixturesReadV2AndRejectFutureAndMalformed()
        throws {
        let codec = SumiFaviconMetadataCodec()
        XCTAssertEqual(
            try codec.decode(
                fixtureData("favicons/metadata-v2.json")
            ).schemaVersion,
            2
        )
        XCTAssertThrowsError(
            try codec.decode(
                fixtureData("favicons/metadata-unsupported-v3.json")
            )
        ) { error in
            XCTAssertEqual(
                error as? SumiFaviconMetadataCodec.DecodingError,
                .unsupportedSchemaVersion(3)
            )
        }
        XCTAssertThrowsError(
            try codec.decode(
                fixtureData("favicons/metadata-malformed.json")
            )
        )
    }

    @MainActor
    func testBoostFixturesReadShippedStoreAndPreserveMalformedBytes()
        throws {
        let loadedDirectory = try makeTemporaryDirectory()
        try copyFixture(
            "boosts/boosts-shipped-unversioned.json",
            to: loadedDirectory.appendingPathComponent("boosts.json")
        )
        let store = SumiBoostStore(rootDirectory: loadedDirectory)
        let profileID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000501"
        )!
        XCTAssertEqual(
            store.activeBoost(
                for: URL(string: "https://fixture.example/")!,
                profileId: profileID
            )?.data.boostName,
            "Fixture Boost"
        )

        let malformedDirectory = try makeTemporaryDirectory()
        let malformedURL = malformedDirectory.appendingPathComponent(
            "boosts.json"
        )
        try copyFixture("boosts/boosts-malformed.json", to: malformedURL)
        let original = try Data(contentsOf: malformedURL)
        let malformedStore = SumiBoostStore(
            rootDirectory: malformedDirectory
        )
        XCTAssertTrue(
            malformedStore.boosts(
                for: URL(string: "https://fixture.example/")!,
                profileId: profileID
            ).isEmpty
        )
        XCTAssertEqual(try Data(contentsOf: malformedURL), original)
        XCTAssertEqual(
            try Data(
                contentsOf: malformedURL.appendingPathExtension("unreadable")
            ),
            original
        )
    }

    func testLiveFolderFixturesReadShippedStoreAndFailClosedMalformed()
        async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("live-folders.json")
        try copyFixture(
            "live-folders/live-folders-shipped-unversioned.json",
            to: storeURL
        )
        let store = SumiLiveFolderStore(fileURL: storeURL)
        let loaded = try await store.load()
        XCTAssertEqual(
            loaded.sources.map(\.id),
            [UUID(uuidString: "00000000-0000-0000-0000-000000000700")!]
        )
        let source = try XCTUnwrap(loaded.sources.first)
        XCTAssertEqual(source.title, "Fixture Feed")
        XCTAssertEqual(source.urlString, "https://fixture.example/feed.xml")

        try FileManager.default.removeItem(at: storeURL)
        try copyFixture(
            "live-folders/live-folders-malformed.json",
            to: storeURL
        )
        let malformed = try Data(contentsOf: storeURL)
        do {
            _ = try await store.load()
            XCTFail("Malformed Live Folder state must fail closed")
        } catch {}
        do {
            try await store.normalizeLegacyProfileReferences()
            XCTFail("Retirement normalization must reject malformed state")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: storeURL), malformed)
    }

    func testLiveFolderRetirementNormalizationRemovesLegacyProfileIdentity()
        async throws {
        let directory = try makeTemporaryDirectory()
        let storeURL = directory.appendingPathComponent("live-folders.json")
        try copyFixture(
            "live-folders/live-folders-shipped-unversioned.json",
            to: storeURL
        )
        let legacyProfileID = UUID()
        let data = try Data(contentsOf: storeURL)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var sources = try XCTUnwrap(object["sources"] as? [[String: Any]])
        sources[0]["profileId"] = legacyProfileID.uuidString
        object["sources"] = sources
        try JSONSerialization.data(withJSONObject: object)
            .write(to: storeURL, options: [.atomic])
        let store = SumiLiveFolderStore(fileURL: storeURL)

        try await store.normalizeLegacyProfileReferences()

        let normalized = try Data(contentsOf: storeURL)
        XCTAssertFalse(
            String(decoding: normalized, as: UTF8.self)
                .contains(legacyProfileID.uuidString)
        )
        let normalizedState = try await store.load()
        XCTAssertEqual(normalizedState.sources.count, 1)
    }

    func testAdblockManifestFixturesReadV1AndRejectFutureAndTamper()
        async throws {
        let directory = try makeTemporaryDirectory()
        let activeURL = directory.appendingPathComponent(
            "active-generation.json"
        )
        let archive = AdblockGenerationArchive(rootDirectory: directory)

        try copyFixture("adblock/manifest-v1.json", to: activeURL)
        let manifest = try await archive.activeManifest()
        XCTAssertEqual(manifest?.schemaVersion, 1)

        for fixtureName in [
            "adblock/manifest-unsupported-v7.json",
            "adblock/manifest-tampered-index.json",
        ] {
            try FileManager.default.removeItem(at: activeURL)
            try copyFixture(fixtureName, to: activeURL)
            do {
                _ = try await archive.activeManifest()
                XCTFail("Expected \(fixtureName) to fail closed")
            } catch {
                XCTAssertEqual(
                    try Data(contentsOf: activeURL),
                    try fixtureData(fixtureName)
                )
            }
        }
    }
}

private extension PersistenceFixtureTests {
    func fixtureURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/Persistence/\(relativePath)",
                isDirectory: false
            )
    }

    func fixtureData(_ relativePath: String) throws -> Data {
        try Data(contentsOf: fixtureURL(relativePath))
    }

    func copyFixture(_ relativePath: String, to destination: URL) throws {
        try FileManager.default.copyItem(
            at: fixtureURL(relativePath),
            to: destination
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiPersistenceFixtureTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
