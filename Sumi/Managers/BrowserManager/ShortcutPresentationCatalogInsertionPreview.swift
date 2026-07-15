import Foundation

/// Sealed evidence that one noncanonical pin is the detached preview produced
/// from an exact launcher insertion source. It permits admission preparation,
/// never staged identity acceptance.
@MainActor
final class ShortcutPresentationCatalogInsertionPreview {
    private let pin: ShortcutPin
    private let source: ShortcutSplitLauncherCatalogSnapshot
    private weak var pins: ShortcutPinCollectionStateOwner?

    init(
        pin: ShortcutPin,
        source: ShortcutSplitLauncherCatalogSnapshot,
        pins: ShortcutPinCollectionStateOwner,
        issuance: ShortcutSplitLauncherCatalogTransaction.PreviewIssuance
    ) {
        self.pin = pin
        self.source = source
        self.pins = pins
    }

    func resolvePin(
        withID id: UUID,
        canonical: () -> ShortcutPin?
    ) -> ShortcutPin? {
        guard pin.id == id else { return canonical() }
        guard let pins, source.isCurrent(in: pins),
              source.pin(withID: id) == nil else { return nil }
        return pin
    }
}
