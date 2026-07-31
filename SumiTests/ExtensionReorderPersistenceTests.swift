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

        owner.movePinnedToolbarSlot(
            id: "a",
            to: 2,
            within: ["a", "b", "c"],
            profileId: nil
        )
        XCTAssertEqual(published.ids, ["b", "c", "a"])

        owner.movePinnedToolbarSlot(
            id: "a",
            to: 0,
            within: ["b", "c", "a"],
            profileId: nil
        )
        XCTAssertEqual(published.ids, ["a", "b", "c"])
    }

    /// The surface only renders pinned ids whose extension is enabled and has
    /// an action, so `targetIndex` is an index into that shorter list. Applying
    /// it straight to the persisted array lands the slot in the wrong place.
    func testMovePinnedToolbarSlotMapsDisplayIndexOntoPersistedOrder() {
        let database = makeDatabase()
        final class Published { var ids: [String] = [] }
        let published = Published()

        let owner = ExtensionToolbarPinningOwner(
            database: database,
            currentProfileId: { nil },
            installedExtensionIDs: { ["a", "hidden", "b", "c"] },
            publishedPinnedIDs: { published.ids },
            setPublishedPinnedIDs: { published.ids = $0 }
        )

        for id in ["a", "hidden", "b", "c"] {
            owner.pinToToolbar(id, profileId: nil)
        }
        XCTAssertEqual(published.ids, ["a", "hidden", "b", "c"])

        // "hidden" is pinned but not rendered, so the surface displays
        // ["a", "b", "c"]. `targetIndex` indexes that list with "a" removed, so
        // 1 means "between b and c" — and the unrendered "hidden" must stay
        // where it was rather than absorbing the index shift.
        owner.movePinnedToolbarSlot(
            id: "a",
            to: 1,
            within: ["a", "b", "c"],
            profileId: nil
        )
        XCTAssertEqual(published.ids, ["hidden", "b", "a", "c"])

        // Dropping past the last displayed slot lands after it.
        owner.movePinnedToolbarSlot(
            id: "a",
            to: 2,
            within: ["b", "a", "c"],
            profileId: nil
        )
        XCTAssertEqual(published.ids, ["hidden", "b", "c", "a"])
    }

    /// A compact strip truncates to its visible limit, so a move committed from
    /// it must not disturb the slots beyond that limit.
    func testMovePinnedToolbarSlotWithinTruncatedDisplayKeepsHiddenTail() {
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

        for id in ["a", "b", "c"] {
            owner.pinToToolbar(id, profileId: nil)
        }

        owner.movePinnedToolbarSlot(
            id: "a",
            to: 1,
            within: ["a", "b"],
            profileId: nil
        )
        XCTAssertEqual(published.ids, ["b", "a", "c"])
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
        owner.movePinnedToolbarSlot(
            id: "c",
            to: 0,
            within: ["a", "b", "c"],
            profileId: nil
        )
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
