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
        let schemaModelNames = SumiStartupSchemaV1.models.map { String(describing: $0) }
        let expectedSchemaModelNames = [
            "SpaceEntity",
            "ProfileEntity",
            "TabEntity",
            "FolderEntity",
            "TabsStateEntity",
            "HistoryEntryEntity",
            "HistoryVisitEntity",
            "ExtensionEntity",
            "SafariContentBlockerEntity",
            "UserScriptEntity",
            "UserScriptResourceEntity",
            "PermissionDecisionEntity",
        ]
        XCTAssertEqual(schemaModelNames, expectedSchemaModelNames)
        XCTAssertEqual(Set(schemaModelNames).count, expectedSchemaModelNames.count)
        XCTAssertEqual(
            SumiStartupMigrationPlan.schemas.map { $0.versionIdentifier },
            [Schema.Version(1, 0, 0)]
        )
        XCTAssertTrue(SumiStartupMigrationPlan.stages.isEmpty)
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
}
