import Foundation
import SumiDomain

@MainActor
final class RegularTabEssentialPinningService {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let placement: EssentialsShortcutPlacementOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let conversion: RegularTabShortcutConversionService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        placement: EssentialsShortcutPlacementOwner,
        pins: ShortcutPinCollectionStateOwner,
        conversion: RegularTabShortcutConversionService
    ) {
        self.structuralLookup = structuralLookup
        self.placement = placement
        self.pins = pins
        self.conversion = conversion
    }

    func pin(
        _ tab: Tab,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) {
        structuralLookup.withTransaction {
            guard let insertion = placement.resolveInsertion(
                using: .init(target: context)
            ), pins.essentialPins(for: insertion.profileId)
                .contains(where: { $0.launchURL == tab.url }) == false
            else { return }
            guard conversion.accept(
                tab,
                destination: TabShortcutPinDestination(
                    role: .essential,
                    profileId: insertion.profileId,
                    spaceId: nil,
                    folderId: nil,
                    index: insertion.index,
                    opensFolder: true
                ),
                preferredWindowId: context?.windowState?.id
            ) else { return }
            placement.logTargetMismatchIfNeeded(
                resolution: insertion.resolution,
                context: context
            )
        }
    }
}
