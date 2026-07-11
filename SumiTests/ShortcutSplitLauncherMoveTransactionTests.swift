import XCTest

@testable import Sumi

@MainActor
final class ShortcutSplitLauncherMoveTransactionTests: XCTestCase {
    func testFailedBatchRestoresEveryPreviouslyMovedPin() throws {
        let spaceID = UUID()
        let first = makePin(spaceID: spaceID, index: 0)
        let second = makePin(spaceID: spaceID, index: 1)
        var catalog = [first.id: first, second.id: second]
        var appliedDestinations: [UUID: [ShortcutSplitLauncherDestination]] = [:]

        let transaction = ShortcutSplitLauncherMoveTransaction(
            shortcutPin: { catalog[$0] },
            canMove: { _, _ in true },
            move: { pin, destination in
                appliedDestinations[pin.id, default: []].append(destination)
                if pin.id == second.id { return nil }
                let moved = self.moved(pin, to: destination)
                catalog[pin.id] = moved
                return moved
            }
        )
        let destination = ShortcutSplitLauncherDestination(
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: nil,
            index: 4
        )

        XCTAssertFalse(transaction.apply([
            PreparedShortcutSplitLauncherRestoration(
                pin: first,
                destination: destination
            ),
            PreparedShortcutSplitLauncherRestoration(
                pin: second,
                destination: destination
            ),
        ]))

        XCTAssertEqual(catalog[first.id]?.index, first.index)
        XCTAssertEqual(catalog[first.id]?.spaceId, first.spaceId)
        XCTAssertEqual(appliedDestinations[first.id]?.map(\.index), [4, 0])
        XCTAssertEqual(appliedDestinations[second.id]?.map(\.index), [4])
    }

    func testStaleBatchRejectsBeforeAnyMove() {
        let spaceID = UUID()
        let pin = makePin(spaceID: spaceID, index: 0)
        var current: ShortcutPin? = pin
        var moveCount = 0
        let transaction = ShortcutSplitLauncherMoveTransaction(
            shortcutPin: { _ in current },
            canMove: { _, _ in true },
            move: { pin, _ in
                moveCount += 1
                return pin
            }
        )
        let restoration = PreparedShortcutSplitLauncherRestoration(
            pin: pin,
            destination: ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceID,
                folderId: nil,
                index: 1
            )
        )
        current = nil

        XCTAssertFalse(transaction.apply([restoration]))
        XCTAssertEqual(moveCount, 0)
    }

    private func makePin(spaceID: UUID, index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceID,
            index: index,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher"
        )
    }

    private func moved(
        _ pin: ShortcutPin,
        to destination: ShortcutSplitLauncherDestination
    ) -> ShortcutPin {
        ShortcutPin(
            id: pin.id,
            role: destination.role,
            profileId: destination.profileId,
            executionProfileId: pin.executionProfileId,
            spaceId: destination.spaceId,
            index: destination.index,
            folderId: destination.folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            iconAsset: pin.iconAsset
        )
    }
}
