import XCTest
@testable import Sumi

final class SumiDatabaseTests: XCTestCase {
    func testProfileDeletionCascadesThroughCanonicalWorkspaceRecords() throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        let spaceID = UUID()
        let tabID = UUID()

        try database.transaction { transaction in
            try transaction.profiles.save(
                ProfileRecord(id: profileID, name: "Personal", index: 0)
            )
            try transaction.workspace.save(
                SpaceRecord(
                    id: spaceID,
                    profileID: profileID,
                    name: "Work",
                    icon: "briefcase",
                    index: 0,
                    workspaceThemeData: nil
                )
            )
            try transaction.workspace.save(
                TabRecord(
                    id: tabID,
                    profileID: profileID,
                    executionProfileID: nil,
                    spaceID: spaceID,
                    folderID: nil,
                    urlString: "https://example.com",
                    name: "Example",
                    isPinned: false,
                    isSpacePinned: false,
                    index: 0,
                    iconAsset: nil,
                    titleIsCustom: false,
                    currentURLString: "https://example.com",
                    canGoBack: false,
                    canGoForward: false,
                    pageKind: TabPersistedPageKind.web.rawValue
                )
            )
        }

        XCTAssertEqual(
            try database.read { try $0.workspace.tabs().first?.pageKind },
            TabPersistedPageKind.web.rawValue
        )

        try database.transaction { transaction in
            try transaction.profiles.delete(id: profileID)
        }

        XCTAssertTrue(try database.read { try $0.profiles.all() }.isEmpty)
        XCTAssertTrue(try database.read { try $0.workspace.spaces().isEmpty })
        XCTAssertTrue(try database.read { try $0.workspace.tabs().isEmpty })
    }

    func testTransactionRollsBackEveryBrowserRecord() throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()

        XCTAssertThrowsError(
            try database.transaction { transaction in
                try transaction.profiles.save(
                    ProfileRecord(id: profileID, name: "Rolled back", index: 0)
                )
                throw TestError.expected
            }
        )

        XCTAssertTrue(try database.read { try $0.profiles.all() }.isEmpty)
    }

    func testHistoryAggregatesVisitsPerProfileAndCascadesWithProfile() throws {
        let database = try SumiDatabase.inMemory()
        let profileID = UUID()
        let url = URL(string: "https://example.com/article")!
        let firstVisit = Date(timeIntervalSince1970: 1_000)
        let secondVisit = Date(timeIntervalSince1970: 2_000)

        try database.transaction { transaction in
            try transaction.profiles.save(
                ProfileRecord(id: profileID, name: "Personal", index: 0)
            )
            try transaction.history.recordVisit(
                id: UUID(),
                url: url,
                title: "First title",
                visitedAt: firstVisit,
                profileID: profileID,
                tabID: nil
            )
            try transaction.history.recordVisit(
                id: UUID(),
                url: url,
                title: "Final title",
                visitedAt: secondVisit,
                profileID: profileID,
                tabID: nil
            )
        }

        let entries = try database.read {
            try $0.history.entries(profileID: profileID)
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].title, "Final title")
        XCTAssertEqual(entries[0].numberOfTotalVisits, 2)
        XCTAssertEqual(entries[0].lastVisit, secondVisit)
        XCTAssertEqual(
            try database.read { try $0.history.visits(profileID: profileID).count },
            2
        )

        try database.transaction { transaction in
            try transaction.profiles.delete(id: profileID)
        }
        XCTAssertTrue(try database.read { try $0.history.entries(profileID: profileID) }.isEmpty)
        XCTAssertTrue(try database.read { try $0.history.visits(profileID: profileID) }.isEmpty)
    }

    private enum TestError: Error {
        case expected
    }
}
