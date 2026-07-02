import Foundation
@testable import Sumi
import SwiftData
import XCTest

final class HistoryVisitDeletionOwnerTests: XCTestCase {
    func testDeletingLastVisitDeletesOrphanedEntry() throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com/only")!
        let visitID = UUID()
        try record(harness, id: visitID, url: url, visitedAt: Date(timeIntervalSince1970: 1_000))

        let deleted = try harness.deletionOwner.deleteVisits(
            in: harness.makeContext(),
            withIDs: [visitID],
            profileId: harness.profileID
        )

        XCTAssertEqual(deleted, 1)
        XCTAssertTrue(try fetchEntries(harness).isEmpty)
    }

    func testDeletionScopedToProfileLeavesOtherProfilesIntact() throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com/shared")!
        let otherProfileID = UUID()
        let ownVisitID = UUID()
        let otherVisitID = UUID()
        try record(harness, id: ownVisitID, url: url, visitedAt: Date(timeIntervalSince1970: 1_000))
        try record(
            harness,
            id: otherVisitID,
            url: url,
            visitedAt: Date(timeIntervalSince1970: 2_000),
            profileID: otherProfileID
        )

        let deleted = try harness.deletionOwner.deleteVisits(
            in: harness.makeContext(),
            withIDs: [ownVisitID, otherVisitID],
            profileId: harness.profileID
        )

        XCTAssertEqual(deleted, 1)
        let remainingVisits = try harness.makeContext().fetch(FetchDescriptor<HistoryVisitEntity>())
        XCTAssertEqual(remainingVisits.map(\.id), [otherVisitID])
    }

    private struct Harness {
        let container: ModelContainer
        let profileID: UUID
        let recorder: HistoryVisitRecorder
        let deletionOwner: HistoryVisitDeletionOwner

        func makeContext() -> ModelContext {
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            return ctx
        }
    }

    private func makeHarness() throws -> Harness {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let planner = HistoryEntityFetchPlanner()
        let visitReader = HistoryVisitRecordReader(planner: planner)
        return Harness(
            container: container,
            profileID: UUID(),
            recorder: HistoryVisitRecorder(planner: planner),
            deletionOwner: HistoryVisitDeletionOwner(planner: planner, visitReader: visitReader)
        )
    }

    private func record(
        _ harness: Harness,
        id: UUID,
        url: URL,
        visitedAt: Date,
        profileID: UUID? = nil
    ) throws {
        _ = try harness.recorder.recordVisit(
            in: harness.makeContext(),
            id: id,
            url: url,
            title: "Title",
            visitedAt: visitedAt,
            profileId: profileID ?? harness.profileID,
            tabId: nil
        )
    }

    private func fetchEntries(_ harness: Harness) throws -> [HistoryEntryEntity] {
        try harness.makeContext().fetch(FetchDescriptor<HistoryEntryEntity>())
    }
}
