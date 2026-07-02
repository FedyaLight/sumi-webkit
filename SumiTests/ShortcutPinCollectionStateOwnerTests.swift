import Foundation
@testable import Sumi
import XCTest

@MainActor
final class ShortcutPinCollectionStateOwnerTests: XCTestCase {
    func testQueriesSortAndFindPinsAcrossCollections() {
        let profileId = UUID()
        let spaceId = UUID()
        let laterEssential = Self.makePin(role: .essential, profileId: profileId, index: 2)
        let earlierEssential = Self.makePin(role: .essential, profileId: profileId, index: 1)
        let spacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let owner = ShortcutPinCollectionStateOwner()

        owner.replaceAll(
            pinnedByProfile: [profileId: [laterEssential, earlierEssential]],
            spacePinnedShortcuts: [spaceId: [spacePin]],
            pendingPinnedWithoutProfile: []
        )

        XCTAssertEqual(owner.essentialPins(for: profileId).map(\.id), [earlierEssential.id, laterEssential.id])
        XCTAssertEqual(owner.essentialPins(for: nil), [])
        XCTAssertEqual(owner.spacePinnedPins(for: spaceId).map(\.id), [spacePin.id])
        XCTAssertEqual(owner.shortcutPin(by: earlierEssential.id)?.id, earlierEssential.id)
        XCTAssertEqual(owner.shortcutPin(by: spacePin.id)?.id, spacePin.id)
        XCTAssertNil(owner.shortcutPin(by: UUID()))
        XCTAssertTrue(owner.hasSpacePinnedShortcuts(in: spaceId))
        XCTAssertFalse(owner.hasSpacePinnedShortcuts(in: UUID()))
    }

    func testRemoveAllClearsCollectionsAndPendingPins() {
        let profileId = UUID()
        let spaceId = UUID()
        let pendingPin = Self.makePin(role: .essential, index: 0)
        let owner = ShortcutPinCollectionStateOwner()

        owner.replaceAll(
            pinnedByProfile: [profileId: [Self.makePin(role: .essential, profileId: profileId, index: 0)]],
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
