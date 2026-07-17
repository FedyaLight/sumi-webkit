import CryptoKit
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupPersistenceTests: XCTestCase {
    func testStartupContainerUsesVersionedSchemaAndMigrationPlan() throws {
        let container = try SumiStartupPersistence.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        XCTAssertEqual(SumiStartupPersistence.schema.version, Schema.Version(2, 0, 0))
        XCTAssertEqual(SumiStartupSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SumiStartupSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        let schemaModelNames = SumiStartupSchemaV2.models.map { String(describing: $0) }
        let expectedSchemaModelNames = [
            "SpaceEntity",
            "ProfileEntity",
            "ProfileRetirementEntity",
            "TabEntity",
            "FolderEntity",
            "TabsStateEntity",
            "HistoryEntryEntity",
            "HistoryVisitEntity",
            "ExtensionEntity",
            "SafariContentBlockerEntity",
            "PermissionDecisionEntity",
        ]
        XCTAssertEqual(schemaModelNames, expectedSchemaModelNames)
        XCTAssertEqual(Set(schemaModelNames).count, expectedSchemaModelNames.count)
        XCTAssertEqual(
            // Xcode 27 beta crashes compiling a key path through this existential.
            // swiftlint:disable:next prefer_key_path
            SumiStartupMigrationPlan.schemas.map { $0.versionIdentifier },
            [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)]
        )
        XCTAssertEqual(SumiStartupMigrationPlan.stages.count, 1)
        XCTAssertNotNil(container.migrationPlan)
    }

    func testMigrationPlanChainsEveryVersionedSchema() {
        let schemas = SumiStartupMigrationPlan.schemas
        XCTAssertFalse(schemas.isEmpty)
        XCTAssertEqual(
            SumiStartupPersistence.schema.version,
            schemas.last?.versionIdentifier,
            "The runtime schema must be the newest versioned schema in the migration plan."
        )
        XCTAssertEqual(
            SumiStartupMigrationPlan.stages.count,
            schemas.count - 1,
            """
            Every versioned schema added to SumiStartupMigrationPlan.schemas needs a \
            MigrationStage from its predecessor. Without one, existing stores hit the \
            migrationOrSchemaMismatch startup path and the app refuses to launch.
            """
        )
    }

    func testOnDiskV1StoreMigratesProfilesAndCreatesEmptyRetirementJournal()
        throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiStartupV1Migration-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let profileID = UUID()
        let spaceID = UUID()
        let tabID = UUID()
        let historyEntryID = UUID()
        let historyVisitID = UUID()
        let permissionKey = SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(
                identity: "https://migration.example"
            ),
            topOrigin: SumiPermissionOrigin(
                identity: "https://migration.example"
            ),
            permissionType: .notifications,
            profilePartitionId: profileID.uuidString
        )

        do {
            let legacyContainer = try ModelContainer(
                for: Schema(versionedSchema: SumiStartupSchemaV1.self),
                configurations: [ModelConfiguration(url: storeURL)]
            )
            let legacyContext = legacyContainer.mainContext
            legacyContext.insert(
                ProfileEntity(
                    id: profileID,
                    name: "Migrated Profile",
                    icon: "person",
                    index: 0
                )
            )
            legacyContext.insert(
                SpaceEntity(
                    id: spaceID,
                    name: "Migrated Space",
                    icon: "square.grid.2x2",
                    index: 0,
                    profileId: profileID
                )
            )
            legacyContext.insert(
                TabEntity(
                    id: tabID,
                    urlString: "https://migration.example",
                    name: "Migrated Tab",
                    isPinned: false,
                    index: 0,
                    spaceId: spaceID,
                    profileId: profileID
                )
            )
            legacyContext.insert(
                HistoryEntryEntity(
                    id: historyEntryID,
                    urlKey: "migration.example/",
                    urlString: "https://migration.example",
                    title: "Migrated History",
                    domain: "migration.example",
                    siteDomain: "migration.example",
                    numberOfTotalVisits: 1,
                    lastVisit: Date(timeIntervalSince1970: 1_000),
                    profileId: profileID
                )
            )
            legacyContext.insert(
                HistoryVisitEntity(
                    id: historyVisitID,
                    entryID: historyEntryID,
                    visitedAt: Date(timeIntervalSince1970: 1_000),
                    profileId: profileID,
                    tabId: tabID
                )
            )
            legacyContext.insert(
                try PermissionDecisionEntity(
                    record: SumiPermissionStoreRecord(
                        key: permissionKey,
                        decision: SumiPermissionDecision(
                            state: .allow,
                            persistence: .persistent,
                            source: .user
                        ),
                        displayDomain: "migration.example"
                    )
                )
            )
            try legacyContext.save()
        }

        let migrated = try SumiStartupPersistence.makeContainer(
            configuration: ModelConfiguration(url: storeURL)
        )
        let profiles = try migrated.mainContext.fetch(
            FetchDescriptor<ProfileEntity>()
        )
        let retirementRecords = try migrated.mainContext.fetch(
            FetchDescriptor<ProfileRetirementEntity>()
        )
        let spaces = try migrated.mainContext.fetch(FetchDescriptor<SpaceEntity>())
        let tabs = try migrated.mainContext.fetch(FetchDescriptor<TabEntity>())
        let historyEntries = try migrated.mainContext.fetch(
            FetchDescriptor<HistoryEntryEntity>()
        )
        let historyVisits = try migrated.mainContext.fetch(
            FetchDescriptor<HistoryVisitEntity>()
        )
        let permissionDecisions = try migrated.mainContext.fetch(
            FetchDescriptor<PermissionDecisionEntity>()
        )

        XCTAssertEqual(profiles.map(\.id), [profileID])
        XCTAssertEqual(profiles.map(\.name), ["Migrated Profile"])
        XCTAssertEqual(spaces.map(\.id), [spaceID])
        XCTAssertEqual(spaces.map(\.profileId), [profileID])
        XCTAssertEqual(tabs.map(\.id), [tabID])
        XCTAssertEqual(tabs.map(\.profileId), [profileID])
        XCTAssertEqual(historyEntries.map(\.id), [historyEntryID])
        XCTAssertEqual(historyEntries.map(\.profileId), [profileID])
        XCTAssertEqual(historyVisits.map(\.id), [historyVisitID])
        XCTAssertEqual(historyVisits.map(\.profileId), [profileID])
        XCTAssertEqual(
            permissionDecisions.map(\.persistentIdentity),
            [permissionKey.persistentIdentity]
        )
        XCTAssertTrue(retirementRecords.isEmpty)
    }

    func testStructuredSQLiteCorruptionClassifiesAsReplacementAuthority() {
        let corruptionFixtures = [
            StartupPersistenceFixtures.corruptStore,
            StartupPersistenceFixtures.notADatabase,
            StartupPersistenceFixtures.extendedCorruptIndex,
            StartupPersistenceFixtures.wrappedCorruptStore,
        ]

        for error in corruptionFixtures {
            let diagnostics = SumiStartupPersistence.classifyStoreOpenFailure(error)
            XCTAssertEqual(diagnostics.reason, .localStoreCorruption)
            XCTAssertTrue(diagnostics.authorizesStoreReplacement)
        }
    }

    func testCorruptStoreFamilyIsPreservedBeforeFreshStoreCreation() throws {
        let fixture = try makeStoreFixture()
        var completedOperations: [SumiStartupStoreRecovery.RecoveryOperation] = []
        var openAttempts = 0

        let result: String = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            performRecoveryOperation: { operation, body in
                try body()
                completedOperations.append(operation)
            },
            openPersistentContainer: { openedURL in
                XCTAssertEqual(openedURL, fixture.storeURL)
                openAttempts += 1

                switch openAttempts {
                case 1:
                    XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
                    throw StartupPersistenceFixtures.corruptStore

                case 2:
                    XCTAssertEqual(completedOperations, expectedRecoveryOperations)
                    let quarantineURL = try publishedQuarantine(in: fixture.quarantineRootURL)
                    try assertPreservedFamily(in: quarantineURL, matches: fixture.originalFamily)
                    XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
                    XCTAssertTrue(
                        FileManager.default.fileExists(
                            atPath: quarantineURL
                                .appendingPathComponent(SumiStartupStoreRecovery.manifestFileName)
                                .path
                        )
                    )
                    throw StartupPersistenceFixtures.corruptStore

                case 3:
                    XCTAssertEqual(completedOperations, expectedFreshCreationOperations)
                    let quarantineURL = try publishedQuarantine(in: fixture.quarantineRootURL)
                    try assertPreservedFamily(in: quarantineURL, matches: fixture.originalFamily)
                    XCTAssertTrue(try storeFamilySnapshot(at: fixture.storeURL).isEmpty)
                    return "fresh-store"

                default:
                    XCTFail("Unexpected startup open attempt \(openAttempts)")
                    return "unexpected"
                }
            }
        )

        XCTAssertEqual(result, "fresh-store")
        XCTAssertEqual(openAttempts, 3)

        let quarantineURL = try publishedQuarantine(in: fixture.quarantineRootURL)
        try assertPreservedFamily(in: quarantineURL, matches: fixture.originalFamily)
        let manifest = try readManifest(in: quarantineURL)
        XCTAssertEqual(manifest.formatVersion, 2)
        XCTAssertEqual(manifest.reason, "sqliteCorruption")
        XCTAssertEqual(manifest.storeFileName, fixture.storeURL.lastPathComponent)
        XCTAssertTrue(
            manifest.errors.contains {
                $0.domain == NSSQLiteErrorDomain && $0.code == 11
            }
        )
        XCTAssertEqual(
            manifest.files,
            fixture.originalFamily
                .map {
                    .init(
                        name: $0.key,
                        byteCount: Int64($0.value.count),
                        sha256: SHA256.hash(data: $0.value)
                            .map { String(format: "%02x", $0) }
                            .joined()
                    )
                }
                .sorted { $0.name < $1.name }
        )
    }

    func testRecoveryOpenStartsOnlyAfterEveryRecoveryOperationCompletes() throws {
        let fixture = try makeStoreFixture()
        var completedOperations: [SumiStartupStoreRecovery.RecoveryOperation] = []
        var openAttempts = 0

        let result: String = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            performRecoveryOperation: { operation, body in
                try body()
                completedOperations.append(operation)
            },
            openPersistentContainer: { _ in
                openAttempts += 1
                if openAttempts == 1 {
                    throw StartupPersistenceFixtures.corruptStore
                }

                XCTAssertEqual(completedOperations, expectedRecoveryOperations)
                return "recovered-store"
            }
        )

        XCTAssertEqual(result, "recovered-store")
        XCTAssertEqual(openAttempts, 2)
        XCTAssertEqual(completedOperations, expectedRecoveryOperations)
    }

    func testEveryQuarantineOperationFailureIsFailClosed() throws {
        for failingOperation in expectedQuarantineOperations {
            let fixture = try makeStoreFixture()
            var completedOperations: [SumiStartupStoreRecovery.RecoveryOperation] = []
            var openAttempts = 0

            XCTAssertThrowsError(
                try SumiStartupPersistence.makePersistentContainerForStartup(
                    storeURL: fixture.storeURL,
                    quarantineRootURL: fixture.quarantineRootURL,
                    performRecoveryOperation: { operation, body in
                        guard operation != failingOperation else {
                            throw StartupPersistenceInjectedFault()
                        }
                        try body()
                        completedOperations.append(operation)
                    },
                    openPersistentContainer: { _ -> String in
                        openAttempts += 1
                        throw StartupPersistenceFixtures.corruptStore
                    }
                ),
                "Expected injected failure at \(failingOperation)."
            )

            XCTAssertEqual(openAttempts, 1, "Unexpected reopen after \(failingOperation).")
            XCTAssertFalse(
                completedOperations.contains(failingOperation),
                "The failed operation was recorded as complete: \(failingOperation)."
            )
            XCTAssertEqual(
                try storeFamilySnapshot(at: fixture.storeURL),
                fixture.originalFamily,
                "Active browser data changed after \(failingOperation)."
            )
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: transitionMarkerURL(for: fixture).path),
                "A destructive transition was authorized after \(failingOperation)."
            )

            if failingOperation == .synchronizeQuarantineRoot {
                let quarantineURL = try publishedQuarantine(in: fixture.quarantineRootURL)
                try assertPreservedFamily(
                    in: quarantineURL,
                    matches: fixture.originalFamily
                )
                XCTAssertNoThrow(try readManifest(in: quarantineURL))
            } else if FileManager.default.fileExists(atPath: fixture.quarantineRootURL.path) {
                let leftovers = try FileManager.default.contentsOfDirectory(
                    at: fixture.quarantineRootURL,
                    includingPropertiesForKeys: nil
                )
                XCTAssertFalse(
                    leftovers.contains {
                        $0.lastPathComponent.hasPrefix("incident-")
                            || $0.lastPathComponent.hasPrefix(".staging-")
                    },
                    "An unpublished incident remained after \(failingOperation)."
                )
            }
        }
    }

    func testStartupAttemptsToOpenThePreservedFamilyCopy() throws {
        let fixture = try makeStoreFixture()
        var openAttempts = 0

        let result: String = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL
        ) { _ in
            openAttempts += 1
            if openAttempts == 1 {
                throw StartupPersistenceFixtures.corruptStore
            }

            XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
            try assertPreservedFamily(
                in: publishedQuarantine(in: fixture.quarantineRootURL),
                matches: fixture.originalFamily
            )
            return "recovered-store"
        }

        XCTAssertEqual(result, "recovered-store")
        XCTAssertEqual(openAttempts, 2)
    }

    func testRestoreRebuildsTheActiveFamilyFromQuarantineBytes() throws {
        let fixture = try makeStoreFixture()
        let quarantine = try SumiStartupStoreRecovery.quarantine(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            failure: StartupPersistenceFixtures.corruptStore
        )

        for name in fixture.originalFamily.keys {
            try FileManager.default.removeItem(
                at: fixture.rootURL.appendingPathComponent(name, isDirectory: false)
            )
        }
        try Data("replacement-active-bytes".utf8).write(to: fixture.storeURL)
        XCTAssertNotEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)

        try SumiStartupStoreRecovery.restorePreservedFamily(
            from: quarantine,
            to: fixture.storeURL
        )

        XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
    }

    func testWrappedCorruptionManifestRecordsTheAuthorizingSQLiteError() throws {
        let fixture = try makeStoreFixture()
        let quarantine = try SumiStartupStoreRecovery.quarantine(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            failure: StartupPersistenceFixtures.wrappedCorruptStore
        )

        let manifest = try readManifest(in: quarantine.directoryURL)
        XCTAssertTrue(
            manifest.errors.contains {
                $0.domain == NSCocoaErrorDomain && $0.code == 134080
            }
        )
        XCTAssertTrue(
            manifest.errors.contains {
                $0.domain == NSSQLiteErrorDomain && $0.code == 11
            }
        )
    }

    func testStartupResumesInterruptedFamilyRestoreBeforeOpening() throws {
        let fixture = try makeStoreFixture()
        let quarantine = try SumiStartupStoreRecovery.quarantine(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            failure: StartupPersistenceFixtures.corruptStore
        )
        try SumiStartupStoreRecovery.beginPreservedFamilyRestore(
            from: quarantine,
            to: fixture.storeURL
        )

        try FileManager.default.removeItem(at: URL(fileURLWithPath: fixture.storeURL.path + "-wal"))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: fixture.storeURL.path + "-shm"))
        try Data("partial-primary-copy".utf8).write(to: fixture.storeURL)

        let result: String = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL
        ) { _ in
            XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
            return "resumed-restore"
        }

        XCTAssertEqual(result, "resumed-restore")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transitionMarkerURL(for: fixture).path))
    }

    func testStartupCompletesInterruptedFreshStorePreparationBeforeOpening() throws {
        let fixture = try makeStoreFixture()
        let quarantine = try SumiStartupStoreRecovery.quarantine(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL,
            failure: StartupPersistenceFixtures.corruptStore
        )
        try SumiStartupStoreRecovery.beginFreshStorePreparation(
            at: fixture.storeURL,
            preserving: quarantine
        )

        try FileManager.default.removeItem(at: URL(fileURLWithPath: fixture.storeURL.path + "-wal"))
        try FileManager.default.removeItem(at: URL(fileURLWithPath: fixture.storeURL.path + "-shm"))

        let result: String = try SumiStartupPersistence.makePersistentContainerForStartup(
            storeURL: fixture.storeURL,
            quarantineRootURL: fixture.quarantineRootURL
        ) { _ in
            XCTAssertTrue(try storeFamilySnapshot(at: fixture.storeURL).isEmpty)
            return "resumed-fresh-store"
        }

        XCTAssertEqual(result, "resumed-fresh-store")
        XCTAssertFalse(FileManager.default.fileExists(atPath: transitionMarkerURL(for: fixture).path))
        try assertPreservedFamily(in: quarantine.directoryURL, matches: fixture.originalFamily)
    }

    func testMalformedTransitionMarkerCannotMutateOrOpenTheStore() throws {
        let fixture = try makeStoreFixture()
        try Data("{malformed-marker".utf8).write(to: transitionMarkerURL(for: fixture))
        var openAttempts = 0

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineRootURL
            ) { _ -> String in
                openAttempts += 1
                return "unexpected-open"
            }
        )

        XCTAssertEqual(openAttempts, 0)
        XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
        XCTAssertTrue(FileManager.default.fileExists(atPath: transitionMarkerURL(for: fixture).path))
    }

    func testLifetimeLockRejectsAConcurrentStoreOwnerWithoutChangingData() throws {
        let fixture = try makeStoreFixture()
        let firstOwner = try SumiStartupStoreIO.LifetimeLock(storeURL: fixture.storeURL)

        try withExtendedLifetime(firstOwner) {
            XCTAssertThrowsError(
                try SumiStartupStoreIO.LifetimeLock(storeURL: fixture.storeURL)
            )
            XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
        }
    }

    func testPermissionFixturePreservesBrowserData() throws {
        try assertFailureIsNonDestructive(
            StartupPersistenceFixtures.permissionDenied,
            expectedReason: .permissionDenied
        )
    }

    func testDiskFullFixturePreservesBrowserData() throws {
        try assertFailureIsNonDestructive(
            StartupPersistenceFixtures.diskFull,
            expectedReason: .diskSpace
        )
    }

    func testSchemaFixturePreservesBrowserData() throws {
        try assertFailureIsNonDestructive(
            StartupPersistenceFixtures.schemaMismatch,
            expectedReason: .migrationOrSchemaMismatch
        )
    }

    func testUnclassifiedMalformedFixtureCannotAuthorizeDeletion() throws {
        try assertFailureIsNonDestructive(
            StartupPersistenceFixtures.unclassifiedMalformed,
            expectedReason: .unclassified
        )
    }

    func testNonCausalSQLiteMetadataCannotAuthorizeDeletion() throws {
        try assertFailureIsNonDestructive(
            StartupPersistenceFixtures.nonCausalCorruptionMetadata,
            expectedReason: .unclassified
        )
    }

    func testUnclassifiedRecoveryFailureCannotAuthorizeFreshStoreCreation() throws {
        let fixture = try makeStoreFixture()
        var openAttempts = 0

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineRootURL
            ) { _ -> String in
                openAttempts += 1
                if openAttempts == 1 {
                    throw StartupPersistenceFixtures.corruptStore
                }

                XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
                throw StartupPersistenceFixtures.unclassifiedMalformed
            }
        )

        XCTAssertEqual(openAttempts, 2)
        XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
        let quarantineURL = try publishedQuarantine(in: fixture.quarantineRootURL)
        try assertPreservedFamily(in: quarantineURL, matches: fixture.originalFamily)
        XCTAssertNoThrow(try readManifest(in: quarantineURL))
    }

    func testPreservationFailureLeavesTheActiveStoreFamilyUntouched() throws {
        let fixture = try makeStoreFixture()
        try Data("not-a-directory".utf8).write(to: fixture.quarantineRootURL)
        var openAttempts = 0

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineRootURL
            ) { _ -> String in
                openAttempts += 1
                throw StartupPersistenceFixtures.corruptStore
            }
        )

        XCTAssertEqual(openAttempts, 1)
        XCTAssertEqual(try storeFamilySnapshot(at: fixture.storeURL), fixture.originalFamily)
    }
}

private extension SumiStartupPersistenceTests {
    func assertFailureIsNonDestructive(
        _ error: NSError,
        expectedReason: SumiStartupPersistence.StoreOpenFailureReason,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let fixture = try makeStoreFixture()
        var openAttempts = 0

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineRootURL
            ) { _ -> String in
                openAttempts += 1
                throw error
            },
            file: file,
            line: line
        )

        XCTAssertEqual(openAttempts, 1, file: file, line: line)
        XCTAssertEqual(
            try storeFamilySnapshot(at: fixture.storeURL),
            fixture.originalFamily,
            file: file,
            line: line
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.quarantineRootURL.path),
            file: file,
            line: line
        )

        let diagnostics = SumiStartupPersistence.classifyStoreOpenFailure(error)
        XCTAssertEqual(diagnostics.reason, expectedReason, file: file, line: line)
        XCTAssertFalse(diagnostics.authorizesStoreReplacement, file: file, line: line)
    }

    private func makeStoreFixture() throws -> StartupPersistenceStoreFixture {
        let fixture = try StartupPersistenceStoreFixture()
        addTeardownBlock {
            try? FileManager.default.removeItem(at: fixture.rootURL)
        }
        return fixture
    }

    private func storeFamilySnapshot(at storeURL: URL) throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let fileURL = suffix.isEmpty
                ? storeURL
                : URL(fileURLWithPath: storeURL.path + suffix, isDirectory: false)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            snapshot[fileURL.lastPathComponent] = try Data(contentsOf: fileURL)
        }
        return snapshot
    }

    private func publishedQuarantine(in rootURL: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        )
        let quarantines = contents.filter { $0.lastPathComponent.hasPrefix("incident-") }
        XCTAssertEqual(quarantines.count, 1)
        return try XCTUnwrap(quarantines.first)
    }

    private func assertPreservedFamily(
        in quarantineURL: URL,
        matches expected: [String: Data],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let preservedStoreURL = quarantineURL
            .appendingPathComponent(SumiStartupStoreRecovery.preservedDirectoryName, isDirectory: true)
            .appendingPathComponent("default.store", isDirectory: false)
        XCTAssertEqual(
            try storeFamilySnapshot(at: preservedStoreURL),
            expected,
            file: file,
            line: line
        )
    }

    private func readManifest(in quarantineURL: URL) throws -> SumiStartupStoreRecovery.Manifest {
        let manifestURL = quarantineURL.appendingPathComponent(
            SumiStartupStoreRecovery.manifestFileName,
            isDirectory: false
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            SumiStartupStoreRecovery.Manifest.self,
            from: Data(contentsOf: manifestURL)
        )
        return SumiStartupStoreRecovery.Manifest(
            formatVersion: manifest.formatVersion,
            incidentID: manifest.incidentID,
            createdAt: manifest.createdAt,
            reason: manifest.reason,
            storeFileName: manifest.storeFileName,
            files: manifest.files.sorted { $0.name < $1.name },
            errors: manifest.errors
        )
    }

    private func transitionMarkerURL(for fixture: StartupPersistenceStoreFixture) -> URL {
        fixture.rootURL.appendingPathComponent(
            SumiStartupStoreRecovery.transitionMarkerFileName,
            isDirectory: false
        )
    }

    var expectedQuarantineOperations: [SumiStartupStoreRecovery.RecoveryOperation] {
        StartupRecoveryOperationFixtures.quarantine
    }

    var expectedRecoveryOperations: [SumiStartupStoreRecovery.RecoveryOperation] {
        StartupRecoveryOperationFixtures.quarantine + StartupRecoveryOperationFixtures.restore
    }

    var expectedFreshCreationOperations: [SumiStartupStoreRecovery.RecoveryOperation] {
        expectedRecoveryOperations + StartupRecoveryOperationFixtures.fresh
    }
}

struct StartupPersistenceInjectedFault: Error {}

enum StartupPersistenceFixtures {
    static let corruptStore = NSError(
        domain: NSSQLiteErrorDomain,
        code: 11,
        userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
    )

    static let notADatabase = NSError(
        domain: NSSQLiteErrorDomain,
        code: 26,
        userInfo: [NSLocalizedDescriptionKey: "file is not a database"]
    )

    static let extendedCorruptIndex = NSError(
        domain: NSSQLiteErrorDomain,
        code: 779,
        userInfo: [NSLocalizedDescriptionKey: "database index is corrupt"]
    )

    static let wrappedCorruptStore = NSError(
        domain: NSCocoaErrorDomain,
        code: 134080,
        userInfo: [NSUnderlyingErrorKey: corruptStore]
    )

    static let nonCausalCorruptionMetadata = NSError(
        domain: "SumiFixtureUnknownErrorDomain",
        code: 9002,
        userInfo: ["diagnosticError": corruptStore]
    )

    static let permissionDenied = NSError(
        domain: NSCocoaErrorDomain,
        code: NSFileReadNoPermissionError,
        userInfo: [NSLocalizedDescriptionKey: "Store access denied."]
    )

    static let diskFull = NSError(
        domain: NSSQLiteErrorDomain,
        code: 13,
        userInfo: [NSLocalizedDescriptionKey: "database or disk is full"]
    )

    static let schemaMismatch = NSError(
        domain: NSCocoaErrorDomain,
        code: 134110,
        userInfo: [NSLocalizedDescriptionKey: "The local store is incompatible."]
    )

    static let unclassifiedMalformed = NSError(
        domain: "SumiFixtureUnknownErrorDomain",
        code: 9001,
        userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
    )

    static let corruptStoreFamily = [
        "default.store": Data("corrupt-primary-store-bytes".utf8),
        "default.store-wal": Data("pending-wal-browser-data".utf8),
        "default.store-shm": Data("shared-memory-browser-data".utf8),
    ]
}

struct StartupPersistenceStoreFixture {
    let rootURL: URL
    let storeURL: URL
    let quarantineRootURL: URL
    let originalFamily: [String: Data]

    init(fileManager: FileManager = .default) throws {
        rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "SumiStartupPersistenceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = rootURL.appendingPathComponent("default.store", isDirectory: false)
        quarantineRootURL = rootURL.appendingPathComponent("quarantine", isDirectory: true)
        originalFamily = StartupPersistenceFixtures.corruptStoreFamily

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for (name, data) in originalFamily {
            try data.write(
                to: rootURL.appendingPathComponent(name, isDirectory: false),
                options: .withoutOverwriting
            )
        }
    }
}
