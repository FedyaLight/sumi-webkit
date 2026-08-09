import Foundation
@testable import Sumi
import XCTest
import SumiDomain

@MainActor
final class ShortcutPinCollectionStateOwnerTests: XCTestCase {
    func testQueriesSortAndFindPinsAcrossCollections() {
        let profileId = UUID()
        let spaceId = UUID()
        let laterFavorite = Self.makePin(role: .favorite, profileId: profileId, index: 2)
        let earlierFavorite = Self.makePin(role: .favorite, profileId: profileId, index: 1)
        let spacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let owner = ShortcutPinCollectionStateOwner()

        owner.replaceAll(
            pinnedByProfile: [profileId: [laterFavorite, earlierFavorite]],
            spacePinnedShortcuts: [spaceId: [spacePin]],
            pendingPinnedWithoutProfile: []
        )

        XCTAssertEqual(owner.favoritePins(for: profileId).map(\.id), [earlierFavorite.id, laterFavorite.id])
        XCTAssertEqual(owner.favoritePins(for: nil), [])
        XCTAssertEqual(owner.spacePinnedPins(for: spaceId).map(\.id), [spacePin.id])
        XCTAssertEqual(owner.shortcutPin(by: earlierFavorite.id)?.id, earlierFavorite.id)
        XCTAssertEqual(owner.shortcutPin(by: spacePin.id)?.id, spacePin.id)
        XCTAssertNil(owner.shortcutPin(by: UUID()))
        XCTAssertTrue(owner.hasSpacePinnedShortcuts(in: spaceId))
        XCTAssertFalse(owner.hasSpacePinnedShortcuts(in: UUID()))
    }

    func testRemoveAllClearsCollectionsAndPendingPins() {
        let profileId = UUID()
        let spaceId = UUID()
        let pendingPin = Self.makePin(role: .favorite, index: 0)
        let owner = ShortcutPinCollectionStateOwner()

        owner.replaceAll(
            pinnedByProfile: [profileId: [Self.makePin(role: .favorite, profileId: profileId, index: 0)]],
            spacePinnedShortcuts: [spaceId: [Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)]],
            pendingPinnedWithoutProfile: [pendingPin]
        )

        owner.removeAll()

        XCTAssertEqual(owner.pinnedByProfile, [:])
        XCTAssertEqual(owner.spacePinnedShortcuts, [:])
        XCTAssertEqual(owner.pendingPinnedWithoutProfile, [])
    }

    private static func makePin(
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: "Pin \(index)"
        )
    }
}
