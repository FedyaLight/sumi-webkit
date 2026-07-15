@MainActor
final class ShortcutPresentationCatalogIdentityHandoff {
    private weak var checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint?
    private let source: ShortcutSplitLauncherCatalogSnapshot
    private let insertion: ShortcutSplitLauncherBindingPinTarget?

    fileprivate init(
        checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint,
        source: ShortcutSplitLauncherCatalogSnapshot,
        insertion: ShortcutSplitLauncherBindingPinTarget?
    ) {
        self.checkpoint = checkpoint
        self.source = source
        self.insertion = insertion
    }

    func authorizesReplacement(
        of sourcePin: ShortcutPin,
        with currentPin: ShortcutPin
    ) -> Bool {
        guard checkpoint?.isCurrent() == true else { return false }
        let sourceIdentity = source.contains(
            ShortcutSplitLauncherCatalogPinReceipt(sourcePin)
        )
        let insertedIdentity = source.pin(withID: sourcePin.id) == nil
            && insertion?.accepts(sourcePin) == true
        guard sourceIdentity || insertedIdentity else { return false }
        return sourcePin.id == currentPin.id
            && sourcePin.role == currentPin.role
            && sourcePin.profileId == currentPin.profileId
            && sourcePin.executionProfileId == currentPin.executionProfileId
            && sourcePin.spaceId == currentPin.spaceId
            && sourcePin.folderId == currentPin.folderId
            && sourcePin.launchURL == currentPin.launchURL
            && sourcePin.title == currentPin.title
            && sourcePin.iconAsset == currentPin.iconAsset
    }
}

extension ShortcutSplitLauncherMoveBatchCheckpoint {
    func preparePresentationIdentityHandoff()
        -> ShortcutPresentationCatalogIdentityHandoff? {
        guard validateForStaging() else { return nil }
        return ShortcutPresentationCatalogIdentityHandoff(
            checkpoint: self,
            source: source,
            insertion: plan.insertion?.target
        )
    }
}
