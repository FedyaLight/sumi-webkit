import Foundation
import SumiDomain

@MainActor
final class RegularTabFavoritePinningService {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let placement: FavoriteShortcutPlacementOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let conversion: RegularTabShortcutConversionService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        placement: FavoriteShortcutPlacementOwner,
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
        context: FavoriteShortcutPlacementOwner.TargetContext?
    ) {
        structuralLookup.withTransaction {
            guard let insertion = placement.resolveInsertion(
                using: .init(target: context)
            ), pins.favoritePins(for: insertion.profileId)
                .contains(where: { $0.launchURL == tab.url }) == false
            else { return }
            guard conversion.accept(
                tab,
                destination: TabShortcutPinDestination(
                    role: .favorite,
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
