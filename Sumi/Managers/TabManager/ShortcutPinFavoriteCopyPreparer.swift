import Foundation
import SumiDomain

@MainActor
final class ShortcutPinFavoriteCopyPreparer {
    struct PreparedCopy {
        let pin: ShortcutPin
        let insertion: FavoriteShortcutPlacementOwner.InsertionPlan
        let context: FavoriteShortcutPlacementOwner.TargetContext?
    }

    private let placement: FavoriteShortcutPlacementOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let resolution: ShortcutPinRuntimeResolutionOwner

    init(
        placement: FavoriteShortcutPlacementOwner,
        pins: ShortcutPinCollectionStateOwner,
        resolution: ShortcutPinRuntimeResolutionOwner
    ) {
        self.placement = placement
        self.pins = pins
        self.resolution = resolution
    }

    func prepare(
        _ pin: ShortcutPin,
        title: String,
        context: FavoriteShortcutPlacementOwner.TargetContext?
    ) -> PreparedCopy? {
        guard pins.shortcutPin(by: pin.id) === pin else { return nil }
        guard let insertion = placement.resolveInsertion(
            using: .init(target: context)
        ), pins.favoritePins(for: insertion.profileId)
            .contains(where: { $0.launchURL == pin.launchURL }) == false
        else { return nil }
        let currentSpaceID = context?.spaceId
            ?? context?.windowState?.currentSpaceId
        let executionProfileID = resolution.resolvedExecutionProfileId(
            for: pin,
            currentSpaceId: currentSpaceID
        )
        return PreparedCopy(
            pin: ShortcutPin(
                id: UUID(),
                role: .favorite,
                profileId: insertion.profileId,
                executionProfileId: executionProfileID == insertion.profileId
                    ? nil : executionProfileID,
                index: insertion.index,
                launchURL: pin.launchURL,
                title: title,
                iconAsset: pin.iconAsset,
                titleIsCustom: title == pin.title
                    ? pin.titleIsCustom
                    : true
            ),
            insertion: insertion,
            context: context
        )
    }

    func publishTargetDiagnostic(for prepared: PreparedCopy) {
        placement.logTargetMismatchIfNeeded(
            resolution: prepared.insertion.resolution,
            context: prepared.context
        )
    }
}
