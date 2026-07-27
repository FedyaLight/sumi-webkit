@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionReorderPersistenceTests: XCTestCase {
    private func makeDatabase() -> SumiDatabase {
        try! SumiDatabase.inMemory()
    }

    // MARK: - Pinned toolbar order

    func testMovePinnedToolbarSlotReordersAndPublishes() {
        let database = makeDatabase()
        final class Published { var ids: [String] = [] }
        let published = Published()

        let owner = ExtensionToolbarPinningOwner(
            database: database,
            currentProfileId: { nil },
            installedExtensionIDs: { ["a", "b", "c"] },
            publishedPinnedIDs: { published.ids },
            setPublishedPinnedIDs: { published.ids = $0 }
        )

        owner.pinToToolbar("a", profileId: nil)
        owner.pinToToolbar("b", profileId: nil)
        owner.pinToToolbar("c", profileId: nil)
        XCTAssertEqual(published.ids, ["a", "b", "c"])

        owner.movePinnedToolbarSlot(id: "a", to: 2, profileId: nil)
        XCTAssertEqual(published.ids, ["b", "c", "a"])

        owner.movePinnedToolbarSlot(id: "a", to: 0, profileId: nil)
        XCTAssertEqual(published.ids, ["a", "b", "c"])
    }

    func testPinnedToolbarOrderSurvivesReload() {
        let database = makeDatabase()
        final class Published { var ids: [String] = [] }
        let published = Published()

        func makeOwner() -> ExtensionToolbarPinningOwner {
            ExtensionToolbarPinningOwner(
                database: database,
                currentProfileId: { nil },
                installedExtensionIDs: { ["a", "b", "c"] },
                publishedPinnedIDs: { published.ids },
                setPublishedPinnedIDs: { published.ids = $0 }
            )
        }

        let owner = makeOwner()
        owner.pinToToolbar("a", profileId: nil)
        owner.pinToToolbar("b", profileId: nil)
        owner.pinToToolbar("c", profileId: nil)
        owner.movePinnedToolbarSlot(id: "c", to: 0, profileId: nil)
        XCTAssertEqual(published.ids, ["c", "a", "b"])

        // A fresh owner reading the same database reloads the moved order.
        let reloaded = makeOwner()
        reloaded.reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertEqual(published.ids, ["c", "a", "b"])
    }

    // MARK: - Hub (unpinned) order

    func testMoveUnpinnedExtensionReordersAndPersists() {
        let database = makeDatabase()

        func makeOwner() -> ExtensionHubOrderingOwner {
            ExtensionHubOrderingOwner(database: database)
        }

        let owner = makeOwner()
        XCTAssertEqual(
            owner.orderedUnpinnedExtensionIDs(candidateIDs: ["a", "b", "c"], profileId: nil),
            ["a", "b", "c"]
        )

        owner.moveUnpinnedExtension(
            id: "a",
            to: 2,
            within: ["a", "b", "c"],
            profileId: nil
        )
        XCTAssertEqual(
            owner.orderedUnpinnedExtensionIDs(candidateIDs: ["a", "b", "c"], profileId: nil),
            ["b", "c", "a"]
        )

        // Newly-seen candidates are appended after the persisted order.
        XCTAssertEqual(
            owner.orderedUnpinnedExtensionIDs(candidateIDs: ["a", "b", "c", "d"], profileId: nil),
            ["b", "c", "a", "d"]
        )

        let reloaded = makeOwner()
        XCTAssertEqual(
            reloaded.orderedUnpinnedExtensionIDs(candidateIDs: ["a", "b", "c"], profileId: nil),
            ["b", "c", "a"]
        )
    }
}
