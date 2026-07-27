import Foundation
import SumiDomain

@MainActor
final class ShortcutPinEssentialCopyPreparer {
    struct PreparedCopy {
        let pin: ShortcutPin
        let insertion: EssentialsShortcutPlacementOwner.InsertionPlan
        let context: EssentialsShortcutPlacementOwner.TargetContext?
    }

    private let placement: EssentialsShortcutPlacementOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let resolution: ShortcutPinRuntimeResolutionOwner

    init(
        placement: EssentialsShortcutPlacementOwner,
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
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) -> PreparedCopy? {
        guard pins.shortcutPin(by: pin.id) === pin else { return nil }
        guard let insertion = placement.resolveInsertion(
            using: .init(target: context)
        ), pins.essentialPins(for: insertion.profileId)
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
                role: .essential,
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
