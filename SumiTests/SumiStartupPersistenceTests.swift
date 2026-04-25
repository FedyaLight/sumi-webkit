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

    func testStartupPersistenceSourceDoesNotContainRemovedRecoveryOrBlockingPatterns() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Sumi/Services/SumiStartupPersistence.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
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
}
