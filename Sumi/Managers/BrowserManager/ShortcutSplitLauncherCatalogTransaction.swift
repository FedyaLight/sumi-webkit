import Foundation

/// Exact catalog half of a launcher move. Runtime residence settlement is
/// supplied as a staged callback and remains owned by the caller.
@MainActor
final class ShortcutSplitLauncherCatalogTransaction {
    private let pinStore: ShortcutPinStoreOwner
    private let pins: ShortcutPinCollectionStateOwner

    init(
        pinStore: ShortcutPinStoreOwner,
        pins: ShortcutPinCollectionStateOwner
    ) {
        self.pinStore = pinStore
        self.pins = pins
    }

    func preview(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> ShortcutPin? {
        pinStore.previewMove(
            pin,
            to: destination.role,
            profileId: destination.profileId,
            spaceId: destination.spaceId,
            folderId: destination.folderId,
            proposedIndex: destination.index
        )
    }

    func currentPin(withID id: UUID) -> ShortcutPin? {
        pins.shortcutPin(by: id)
    }

    func snapshot() -> ShortcutSplitLauncherCatalogSnapshot {
        ShortcutSplitLauncherCatalogSnapshot(pins)
    }

    func matches(_ expected: ShortcutSplitLauncherCatalogSnapshot) -> Bool {
        expected.isCurrent(in: pins)
    }

    func restore(_ source: ShortcutSplitLauncherCatalogSnapshot) {
        source.restore(to: pins)
    }

    func move(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination,
        applying: @escaping (ShortcutPin) -> Bool
    ) -> ShortcutPin? {
        pinStore.move(
            pin,
            to: destination.role,
            profileId: destination.profileId,
            spaceId: destination.spaceId,
            folderId: destination.folderId,
            index: destination.index,
            openTargetFolder: false,
            applying: applying
        )
    }

    func isCurrent(_ expected: ShortcutPin) -> Bool {
        guard let current = pins.shortcutPin(by: expected.id) else {
            return false
        }
        return matches(current, expected)
    }

    func rollback(
        sourcePin: ShortcutPin,
        movedPinID: UUID,
        applying: @escaping (ShortcutPin) -> Bool
    ) -> Bool {
        guard let current = pins.shortcutPin(by: movedPinID) else {
            return false
        }
        return pinStore.move(
            current,
            to: sourcePin.role,
            profileId: sourcePin.profileId,
            spaceId: sourcePin.spaceId,
            folderId: sourcePin.folderId,
            index: sourcePin.index,
            openTargetFolder: false,
            applying: {
                self.matches($0, sourcePin) && applying($0)
            }
        )?.id == sourcePin.id
    }

    private func matches(_ lhs: ShortcutPin, _ rhs: ShortcutPin) -> Bool {
        lhs.id == rhs.id
            && lhs.role == rhs.role
            && lhs.profileId == rhs.profileId
            && lhs.executionProfileId == rhs.executionProfileId
            && lhs.spaceId == rhs.spaceId
            && lhs.folderId == rhs.folderId
            && lhs.index == rhs.index
            && lhs.launchURL == rhs.launchURL
            && lhs.title == rhs.title
            && lhs.iconAsset == rhs.iconAsset
    }
}
