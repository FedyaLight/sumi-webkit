import Combine
import XCTest

@testable import Sumi

@MainActor
final class ShortcutTabMaterializerTests: XCTestCase {
    func testFreshEssentialUsesExecutionProfileAndReusesExactIdentity() throws {
        let tabManager = try makeInMemoryTabManager()
        let windowId = UUID()
        let ownerProfileId = UUID()
        let executionProfileId = UUID()
        let ignoredSpaceId = UUID()
        let ignoredFolderId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: ownerProfileId,
            executionProfileId: executionProfileId,
            spaceId: ignoredSpaceId,
            index: 0,
            folderId: ignoredFolderId,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        var eventCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher
            .sink { eventCount += 1 }

        let fresh = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: ignoredSpaceId
            )
        }

        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(fresh.shortcutPinId, pin.id)
        XCTAssertEqual(fresh.shortcutPinRole, .essential)
        XCTAssertNil(fresh.spaceId)
        XCTAssertEqual(fresh.profileId, executionProfileId)
        XCTAssertNil(fresh.folderId)
        XCTAssertFalse(fresh.isPinned)
        XCTAssertFalse(fresh.isSpacePinned)
        XCTAssertIdentical(
            tabManager.liveShortcutTabs.tab(for: pin.id, in: windowId),
            fresh
        )
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: fresh.id),
            fresh
        )

        eventCount = 0
        let reused = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: UUID()
            )
        }

        XCTAssertIdentical(reused, fresh)
        XCTAssertEqual(eventCount, 0)
    }

    func testSpacePinnedMaterializationInheritsMetadataAndRebindsOnce() throws {
        let spaceProfileId = UUID()
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Workspace",
            profileId: spaceProfileId
        )
        let firstFolderId = UUID()
        let secondFolderId = UUID()
        let windowId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: firstFolderId,
            launchURL: URL(string: "https://space-pinned.example")!,
            title: "Space Pinned"
        )
        var eventCount = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher
            .sink { eventCount += 1 }

        let fresh = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowId,
                currentSpaceId: space.id
            )
        }

        XCTAssertEqual(eventCount, 1)
        XCTAssertEqual(fresh.shortcutPinId, pin.id)
        XCTAssertEqual(fresh.shortcutPinRole, .spacePinned)
        XCTAssertEqual(fresh.spaceId, space.id)
        XCTAssertEqual(fresh.profileId, spaceProfileId)
        XCTAssertEqual(fresh.folderId, firstFolderId)
        XCTAssertFalse(fresh.isPinned)
        XCTAssertFalse(fresh.isSpacePinned)

        let updatedPin = pin.updated(folderId: .some(secondFolderId))
        eventCount = 0
        let rebound = withExtendedLifetime(cancellable) {
            tabManager.shortcutTabMaterializer.materialize(
                updatedPin,
                in: windowId,
                currentSpaceId: space.id
            )
        }

        XCTAssertIdentical(rebound, fresh)
        XCTAssertEqual(rebound.folderId, secondFolderId)
        XCTAssertEqual(rebound.spaceId, space.id)
        XCTAssertEqual(rebound.profileId, spaceProfileId)
        XCTAssertEqual(eventCount, 1)
    }
}
