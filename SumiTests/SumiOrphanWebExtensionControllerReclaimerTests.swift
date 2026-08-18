import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SumiOrphanWebExtensionControllerReclaimerTests: XCTestCase {
    func testReclaimsOnlyNonLiveNamespacesAndPersistsTheRemainder() async throws {
        let database = try SumiDatabase.inMemory()
        let live = UUID()
        let firstOrphan = UUID()
        let secondOrphan = UUID()
        var removed: [UUID] = []

        let firstPass = try await SumiOrphanWebExtensionControllerReclaimer.runIfNeeded(
            liveControllerIDs: [live],
            database: database,
            fetchIdentifiers: { [live, firstOrphan, secondOrphan] },
            removeIdentifier: { identifier in
                removed.append(identifier)
                return identifier != firstOrphan
            }
        )

        XCTAssertEqual(firstPass, [secondOrphan])
        XCTAssertEqual(Set(removed), Set([firstOrphan, secondOrphan]))

        removed.removeAll()
        let secondPass = try await SumiOrphanWebExtensionControllerReclaimer.runIfNeeded(
            liveControllerIDs: [live],
            database: database,
            fetchIdentifiers: { XCTFail("Must use the persisted retry set"); return [] },
            removeIdentifier: { identifier in
                removed.append(identifier)
                return true
            }
        )

        XCTAssertEqual(secondPass, [firstOrphan])
        XCTAssertEqual(removed, [firstOrphan])
    }

    func testLiveNamespaceIsRemovedFromAStaleRetrySet() async throws {
        let database = try SumiDatabase.inMemory()
        let nowLive = UUID()

        let seeded = try await SumiOrphanWebExtensionControllerReclaimer.runIfNeeded(
            liveControllerIDs: [],
            database: database,
            fetchIdentifiers: { [nowLive] },
            removeIdentifier: { _ in false }
        )
        XCTAssertTrue(seeded.isEmpty)

        let removed = try await SumiOrphanWebExtensionControllerReclaimer.runIfNeeded(
            liveControllerIDs: [nowLive],
            database: database,
            fetchIdentifiers: { XCTFail("Must use the persisted retry set"); return [] },
            removeIdentifier: { _ in
                XCTFail("A now-live namespace must not be removed")
                return false
            }
        )

        XCTAssertTrue(removed.isEmpty)
    }
}
