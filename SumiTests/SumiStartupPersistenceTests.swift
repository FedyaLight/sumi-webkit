import Darwin
import GRDB
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupPersistenceTests: XCTestCase {
    func testLegacyDirectoryMigrationIsReleaseGatedAndAtomic() throws {
        let fixture = try Fixture()
        let legacy = fixture.rootURL.appendingPathComponent("legacy")
        let canonical = fixture.rootURL.appendingPathComponent("canonical")
        try FileManager.default.createDirectory(
            at: legacy,
            withIntermediateDirectories: true
        )

        XCTAssertEqual(
            SumiApplicationSupportDirectory.migrateLegacyDirectoryIfNeeded(
                from: legacy,
                to: canonical
            ),
            canonical
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))

        XCTAssertEqual(
            SumiApplicationSupportDirectory.migrateLegacyDirectoryIfNeeded(
                from: legacy,
                to: canonical,
                allowsMigration: true
            ),
            canonical
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
    }

    func testKnownDatabaseFailuresHaveExactClassification() {
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                SumiDatabaseError.unsupportedSchemaVersion(3)
            ).reason,
            .schemaMismatch
        )
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                DatabaseError(resultCode: .SQLITE_FULL)
            ).reason,
            .diskSpace
        )
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                DatabaseError(resultCode: .SQLITE_READONLY)
            ).reason,
            .permissionDenied
        )
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                DatabaseError(resultCode: .SQLITE_CORRUPT)
            ).reason,
            .localStoreCorruption
        )
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                DatabaseError(resultCode: .SQLITE_NOTADB)
            ).reason,
            .localStoreCorruption
        )
    }

    func testVersionOneDatabaseMigratesThroughCurrentSchema() throws {
        let fixture = try Fixture()
        let queue = try DatabaseQueue(path: fixture.storeURL.path)
        try queue.write { database in
            try database.create(table: "folders") { table in
                table.column("id", .blob).primaryKey()
                table.column("space_id", .blob).notNull()
                table.column("parent_folder_id", .blob)
                table.column("name", .text).notNull()
                table.column("icon", .text).notNull()
                table.column("color", .text).notNull()
                table.column("is_open", .boolean).notNull()
                table.column("position", .integer).notNull()
            }
            try database.create(table: "tabs") { table in
                table.column("id", .blob).primaryKey()
            }
            try database.execute(sql: "PRAGMA user_version = 1")
        }

        let database = try SumiDatabase.open(at: fixture.storeURL)
        let folder = FolderRecord(
            id: UUID(),
            spaceID: UUID(),
            parentFolderID: nil,
            name: "Feed",
            icon: "folder",
            color: "#000000",
            isOpen: true,
            isLiveFolder: true,
            index: 0
        )
        try database.transaction { try $0.workspace.save(folder) }

        XCTAssertEqual(
            try database.read { try $0.workspace.folders().first?.isLiveFolder },
            true
        )
    }

    func testDeveloperStorageIsIsolatedByDatabaseSchemaVersion() {
        let baseURL = URL(fileURLWithPath: "/Application Support")

        XCTAssertEqual(
            SumiApplicationSupportDirectory.resolvedAppRootURL(
                baseURL: baseURL,
                bundleIdentifier: "com.sumi.browser.testhost",
                databaseSchemaVersion: 5
            ),
            baseURL.appendingPathComponent(
                "com.sumi.browser.testhost/schema-5",
                isDirectory: true
            )
        )
        XCTAssertEqual(
            SumiApplicationSupportDirectory.resolvedAppRootURL(
                baseURL: baseURL,
                bundleIdentifier: SumiAppIdentity.bundleIdentifier,
                databaseSchemaVersion: 5
            ),
            baseURL.appendingPathComponent(
                SumiAppIdentity.bundleIdentifier,
                isDirectory: true
            )
        )
    }

    func testDeveloperStorageRemovesOnlyObsoleteSchemaDirectories() throws {
        let fixture = try Fixture()
        let current = fixture.rootURL.appendingPathComponent("schema-5", isDirectory: true)
        let obsolete = fixture.rootURL.appendingPathComponent("schema-4", isDirectory: true)
        let future = fixture.rootURL.appendingPathComponent("schema-6", isDirectory: true)
        let unrelated = fixture.rootURL.appendingPathComponent("Favicons", isDirectory: true)
        let similarFile = fixture.rootURL.appendingPathComponent("schema-not-a-version")
        for directory in [current, obsolete, future, unrelated] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        try Data().write(to: similarFile)

        SumiApplicationSupportDirectory.removeObsoleteDeveloperSchemaDirectories(
            in: fixture.rootURL,
            keepingSchemaVersion: 5
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: obsolete.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: future.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: similarFile.path))
    }

    func testCorruptUnifiedDatabaseIsPreservedBeforeFreshCreation() throws {
        let fixture = try Fixture()
        let original = Data("not a sqlite database".utf8)
        try original.write(to: fixture.storeURL)

        let database = try SumiStartupPersistence
            .makePersistentDatabaseForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineURL,
                openDatabase: SumiDatabase.open
            )

        XCTAssertEqual(try database.read { try $0.profiles.all() }, [])
        XCTAssertNoThrow(try SumiDatabase.open(at: fixture.storeURL))
        let incidents = try FileManager.default.contentsOfDirectory(
            at: fixture.quarantineURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("incident-") }
        XCTAssertEqual(incidents.count, 1)
        XCTAssertEqual(
            try Data(
                contentsOf: incidents[0]
                    .appendingPathComponent(
                        SumiStartupStoreRecovery.preservedDirectoryName,
                        isDirectory: true
                    )
                    .appendingPathComponent("Sumi.sqlite")
            ),
            original
        )
    }

    func testNonCorruptionFailureNeverReplacesDatabase() throws {
        let fixture = try Fixture()
        let original = Data("browser data".utf8)
        try original.write(to: fixture.storeURL)
        var openCount = 0

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentDatabaseForStartup(
                storeURL: fixture.storeURL,
                quarantineRootURL: fixture.quarantineURL
            ) { _ -> SumiDatabase in
                openCount += 1
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EACCES)
                )
            }
        )

        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.storeURL), original)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.quarantineURL.path
            )
        )
    }

    func testLifetimeLockRejectsSecondOwnerWithoutChangingDatabase() throws {
        let fixture = try Fixture()
        let original = Data("browser data".utf8)
        try original.write(to: fixture.storeURL)
        let first = try SumiStartupStoreIO.LifetimeLock(
            storeURL: fixture.storeURL
        )

        try withExtendedLifetime(first) {
            XCTAssertThrowsError(
                try SumiStartupStoreIO.LifetimeLock(
                    storeURL: fixture.storeURL
                )
            )
            XCTAssertEqual(try Data(contentsOf: fixture.storeURL), original)
        }
    }
}

private final class Fixture {
    let rootURL: URL
    let storeURL: URL
    let quarantineURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiStartupPersistenceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = rootURL.appendingPathComponent("Sumi.sqlite")
        quarantineURL = rootURL.appendingPathComponent(
            "StartupPersistenceQuarantine",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
