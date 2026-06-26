import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupPersistenceTests: XCTestCase {
    func testCorruptStoreOpenFailureResetsOnceAndReopensOnce() throws {
        let recreatedContainer = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        var openAttempts = 0
        var resetAttempts = 0
        let initialError = NSError(
            domain: NSCocoaErrorDomain,
            code: 134110,
            userInfo: [NSLocalizedDescriptionKey: "The local store is incompatible."]
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
        XCTAssertTrue(resolvedContainer === recreatedContainer)
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
            "migration",
            "migrate",
        ] {
            XCTAssertFalse(source.contains(removedPattern), "\(removedPattern) is still present")
        }

        XCTAssertFalse(lowercasedSource.contains("backup"))
        XCTAssertFalse(lowercasedSource.contains("migration"))
        XCTAssertFalse(lowercasedSource.contains("migrate"))
    }

    func testSharedStartupPersistenceDoesNotFatalErrorOnOpenFailure() throws {
        let source = try startupPersistenceSource()

        XCTAssertFalse(source.contains("fatalError("))
        XCTAssertTrue(source.contains("private let containerResult: Result<ModelContainer, Error>"))
        XCTAssertTrue(source.contains("func modelContainer() throws -> ModelContainer"))
    }

    private func startupPersistenceSource() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Services/SumiStartupPersistence.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
