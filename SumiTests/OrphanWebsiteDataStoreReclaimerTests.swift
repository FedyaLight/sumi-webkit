import Foundation
import XCTest

@testable import Sumi

@MainActor
final class OrphanWebsiteDataStoreReclaimerTests: XCTestCase {
    func testReclaimerPersistsCandidatesAndRemovesOneBoundedBatch() async throws {
        let database = try SumiDatabase.inMemory()
        let live = UUID()
        let orphans = (0...64).map { _ in UUID() }
        var fetchCount = 0
        var removed: [UUID] = []

        let firstPass = try await SumiOrphanIdentifierBatch.runIfNeeded(
            documentKey: "test.website-data-store-orphans",
            batchSize: 64,
            liveIdentifiers: [live],
            database: database,
            fetchIdentifiers: {
                fetchCount += 1
                return [live] + orphans
            },
            removeIdentifier: { identifier in
                removed.append(identifier)
                return true
            }
        )

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(firstPass.count, 64)
        XCTAssertEqual(removed.count, 64)
        XCTAssertFalse(removed.contains(live))

        let secondPass = try await SumiOrphanIdentifierBatch.runIfNeeded(
            documentKey: "test.website-data-store-orphans",
            batchSize: 64,
            liveIdentifiers: [live],
            database: database,
            fetchIdentifiers: {
                fetchCount += 1
                return []
            },
            removeIdentifier: { identifier in
                removed.append(identifier)
                return true
            }
        )

        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(secondPass.count, 1)
        XCTAssertEqual(Set(removed), Set(orphans))
    }
}
