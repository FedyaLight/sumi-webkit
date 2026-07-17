import Foundation

/// Resolves a shortcut presentation page and delegates the admitted mutation
/// to its concrete structural committer.
@MainActor
final class ShortcutTabMaterializer {
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let committer: ShortcutTabMaterializationCommitter

    init(
        resolution: ShortcutPinRuntimeResolutionOwner,
        committer: ShortcutTabMaterializationCommitter
    ) {
        self.resolution = resolution
        self.committer = committer
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowID: UUID,
        currentSpaceId: UUID?
    ) -> Tab? {
        guard let presentationPage = resolution.presentationPageReceipt(
            for: pin,
            windowID: windowID,
            presentationSpaceID: currentSpaceId
        ) else { return nil }
        return materialize(
            pin,
            in: windowID,
            currentSpaceId: currentSpaceId,
            presentationPage: presentationPage
        )
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowID: UUID,
        currentSpaceId: UUID?,
        presentationPage: LiveShortcutPresentationPageReceipt
    ) -> Tab? {
        committer.commit(
            pin,
            in: windowID,
            currentSpaceID: currentSpaceId,
            presentationPage: presentationPage
        )
    }
}
