@testable import Sumi
import XCTest

@available(macOS 15.5, *)
@MainActor
final class ExtensionReorderPersistenceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "reorder-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    // MARK: - Pinned toolbar order

    func testMovePinnedToolbarSlotReordersAndPublishes() {
        let defaults = makeDefaults()
        final class Published { var ids: [String] = [] }
        let published = Published()

        let owner = ExtensionToolbarPinningOwner(
            dependencies: .init(
                preferences: defaults,
                currentProfileId: { nil },
                installedExtensionIDs: { ["a", "b", "c"] },
                publishedPinnedIDs: { published.ids },
                setPublishedPinnedIDs: { published.ids = $0 }
            )
        )

        owner.pinToToolbar("a")
        owner.pinToToolbar("b")
        owner.pinToToolbar("c")
        XCTAssertEqual(published.ids, ["a", "b", "c"])

        owner.movePinnedToolbarSlot(id: "a", to: 2)
        XCTAssertEqual(published.ids, ["b", "c", "a"])

        owner.movePinnedToolbarSlot(id: "a", to: 0)
        XCTAssertEqual(published.ids, ["a", "b", "c"])
    }

    func testPinnedToolbarOrderSurvivesReload() {
        let defaults = makeDefaults()
        final class Published { var ids: [String] = [] }
        let published = Published()

        func makeOwner() -> ExtensionToolbarPinningOwner {
            ExtensionToolbarPinningOwner(
                dependencies: .init(
                    preferences: defaults,
                    currentProfileId: { nil },
                    installedExtensionIDs: { ["a", "b", "c"] },
                    publishedPinnedIDs: { published.ids },
                    setPublishedPinnedIDs: { published.ids = $0 }
                )
            )
        }

        let owner = makeOwner()
        owner.pinToToolbar("a")
        owner.pinToToolbar("b")
        owner.pinToToolbar("c")
        owner.movePinnedToolbarSlot(id: "c", to: 0)
        XCTAssertEqual(published.ids, ["c", "a", "b"])

        // A fresh owner reading the same preferences reloads the moved order.
        let reloaded = makeOwner()
        reloaded.reloadPinnedToolbarExtensionsForCurrentProfile()
        XCTAssertEqual(published.ids, ["c", "a", "b"])
    }

    // MARK: - Hub (unpinned) order

    func testMoveUnpinnedExtensionReordersAndPersists() {
        let defaults = makeDefaults()

        func makeOwner() -> ExtensionHubOrderingOwner {
            ExtensionHubOrderingOwner(
                dependencies: .init(preferences: defaults, currentProfileId: { nil })
            )
        }

        let owner = makeOwner()
        XCTAssertEqual(
            owner.orderedUnpinnedExtensionIDs(candidateIDs: ["a", "b", "c"], profileId: nil),
            ["a", "b", "c"]
        )

        owner.moveUnpinnedExtension(id: "a", to: 2, within: ["a", "b", "c"])
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
