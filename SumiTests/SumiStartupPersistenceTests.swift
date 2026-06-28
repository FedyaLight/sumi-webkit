import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupPersistenceTests: XCTestCase {
    func testStartupContainerUsesVersionedSchemaAndMigrationPlan() throws {
        let container = try SumiStartupPersistence.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        XCTAssertEqual(SumiStartupPersistence.schema.version, Schema.Version(1, 0, 0))
        XCTAssertEqual(SumiStartupSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(Set(SumiStartupSchemaV1.models.map { String(describing: $0) }), [
            "ExtensionEntity",
            "FolderEntity",
            "HistoryEntryEntity",
            "HistoryVisitEntity",
            "PermissionDecisionEntity",
            "ProfileEntity",
            "SafariContentBlockerEntity",
            "SpaceEntity",
            "TabEntity",
            "TabsStateEntity",
            "UserScriptEntity",
            "UserScriptResourceEntity",
        ])
        XCTAssertEqual(SumiStartupMigrationPlan.schemas.count, 1)
        XCTAssertTrue(SumiStartupMigrationPlan.stages.isEmpty)
        XCTAssertNotNil(container.migrationPlan)
    }

    func testResettableLocalStoreOpenFailureResetsOnceAndReopensOnce() throws {
        let recreatedContainer = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        var openAttempts = 0
        var resetAttempts = 0
        let initialError = NSError(
            domain: "NSSQLiteErrorDomain",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "database disk image is malformed"]
        )

        let resolvedContainer = try SumiStartupPersistence.makePersistentContainerForStartup {
            openAttempts += 1
            if openAttempts == 1 {
                throw initialError
            }
            return recreatedContainer
        } resetPersistentStore: {
            resetAttempts += 1
        }

        XCTAssertEqual(openAttempts, 2)
        XCTAssertEqual(resetAttempts, 1)
        XCTAssertIdentical(resolvedContainer, recreatedContainer)
    }

    func testSchemaMigrationOpenFailureDoesNotResetLocalStore() throws {
        var openAttempts = 0
        var resetAttempts = 0
        let migrationError = NSError(
            domain: NSCocoaErrorDomain,
            code: 134110,
            userInfo: [NSLocalizedDescriptionKey: "The local store is incompatible."]
        )

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup {
                openAttempts += 1
                throw migrationError
            } resetPersistentStore: {
                resetAttempts += 1
            }
        )

        XCTAssertEqual(openAttempts, 1)
        XCTAssertEqual(resetAttempts, 0)
        let diagnostics = SumiStartupPersistence.classifyStoreOpenFailure(migrationError)
        XCTAssertEqual(diagnostics.reason, .migrationOrSchemaMismatch)
        XCTAssertFalse(diagnostics.shouldResetLocalStore)
    }

    func testNonResettableStoreOpenFailurePropagatesWithoutFallbackContainer() throws {
        var openAttempts = 0
        var resetAttempts = 0
        let permissionError = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [NSLocalizedDescriptionKey: "Store access denied."]
        )

        XCTAssertThrowsError(
            try SumiStartupPersistence.makePersistentContainerForStartup {
                openAttempts += 1
                throw permissionError
            } resetPersistentStore: {
                resetAttempts += 1
            }
        )

        XCTAssertEqual(openAttempts, 1)
        XCTAssertEqual(resetAttempts, 0)
    }

    func testStartupPersistenceSourceDoesNotContainRemovedRecoveryOrBlockingPatterns() throws {
        let source = try startupPersistenceSource()
        let lowercasedSource = source.lowercased()

        for removedPattern in [
            "backup",
            "restoreFromBackup",
            "runBlockingOnUtilityQueue",
            "DispatchGroup",
            "group.wait",
            "DispatchSemaphore",
        ] {
            XCTAssertFalse(source.contains(removedPattern), "\(removedPattern) is still present")
        }

        XCTAssertFalse(lowercasedSource.contains("backup"))
    }

    func testSharedStartupPersistenceDoesNotFatalErrorOnOpenFailure() throws {
        let source = try startupPersistenceSource()

        XCTAssertFalse(source.contains("fatalError("))
        XCTAssertTrue(source.contains("private let containerResult: Result<ModelContainer, Error>"))
        XCTAssertTrue(source.contains("func modelContainer() throws -> ModelContainer"))
    }

    func testDataLayerApplicationSupportLookupsDoNotForceUnwrap() throws {
        let sourcePaths = [
            "Sumi/Services/SumiStartupPersistence.swift",
            "Sumi/Bookmarks/SumiBookmarkDatabase.swift",
            "Sumi/Favicons/SumiFaviconSystem.swift",
            "Sumi/Services/SumiApplicationSupportDirectory.swift",
        ]

        for sourcePath in sourcePaths {
            let source = try source(named: sourcePath)
            let collapsedSource = source.components(separatedBy: .whitespacesAndNewlines)
                .joined()
            XCTAssertFalse(
                collapsedSource.contains(".applicationSupportDirectory,in:.userDomainMask).first!"),
                "\(sourcePath) still force unwraps Application Support"
            )
        }

        let resolverSource = try source(named: "Sumi/Services/SumiApplicationSupportDirectory.swift")
        XCTAssertTrue(resolverSource.contains("temporaryDirectory"))
        XCTAssertTrue(resolverSource.contains("Application Support directory is unavailable"))
        XCTAssertTrue(resolverSource.contains("log.fault"))
    }

    private func startupPersistenceSource() throws -> String {
        try source(named: "Sumi/Services/SumiStartupPersistence.swift")
    }

    private func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
