import Darwin
import GRDB
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupPersistenceTests: XCTestCase {
    func testKnownDatabaseFailuresHaveExactClassification() {
        XCTAssertEqual(
            SumiStartupPersistence.classifyStoreOpenFailure(
                SumiDatabaseError.unsupportedSchemaVersion(2)
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
