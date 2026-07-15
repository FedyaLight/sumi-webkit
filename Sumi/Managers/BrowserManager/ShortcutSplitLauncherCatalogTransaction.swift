import Foundation

/// Exact catalog half of a launcher move. Runtime residence settlement is
/// supplied as a staged callback and remains owned by the caller.
@MainActor
final class ShortcutSplitLauncherCatalogTransaction {
    struct PreviewIssuance { fileprivate init() {} }

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

    func prepareInsertion(
        _ pin: ShortcutPin,
        at index: Int
    ) -> ShortcutSplitLauncherCatalogInsertionPlan? {
        let source = snapshot()
        guard let inserted = pinStore.previewInsert(pin, at: index) else {
            return nil
        }
        let target = ShortcutSplitLauncherBindingPinTarget(inserted)
        return ShortcutSplitLauncherCatalogInsertionPlan(
            insertedPin: inserted,
            sourceCatalog: source,
            insertion: .init(pin: pin, index: index, target: target),
            presentationPreview: .init(
                pin: inserted,
                source: source,
                pins: pins,
                issuance: PreviewIssuance()
            )
        )
    }

    func stageInsertion(
        _ insertion: ShortcutSplitLauncherCatalogMovePlan.Insertion
    ) -> ShortcutPin? {
        pinStore.insert(
            insertion.pin,
            at: insertion.index,
            openTargetFolder: false
        )
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
        return ShortcutSplitLauncherCatalogPinReceipt(expected).accepts(current)
    }
}
