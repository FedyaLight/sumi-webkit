import Foundation
import SumiDomain

@MainActor
final class ShortcutPinSpacePinningTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let spaces: TabSpaceCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let rebinder: FavoriteShortcutSpaceRebinder
    private let conversion: RegularTabShortcutConversionService

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        rebinder: FavoriteShortcutSpaceRebinder,
        conversion: RegularTabShortcutConversionService
    ) {
        self.structuralLookup = structuralLookup
        self.spaces = spaces
        self.pins = pins
        self.rebinder = rebinder
        self.conversion = conversion
    }

    func pin(_ tab: Tab, to spaceID: UUID) {
        structuralLookup.withTransaction {
            guard spaces.contains(spaceId: spaceID),
                  pins.spacePinnedPins(for: spaceID)
                  .contains(where: { $0.launchURL == tab.url }) == false
            else { return }
            let source = tab.shortcutPinId.flatMap(pins.shortcutPin(by:))
            let index = pins.spacePinnedPins(for: spaceID).count
            switch rebinder.rebind(
                tab,
                source: source,
                spaceID: spaceID,
                index: index
            ) {
            case .committed, .rejected:
                return
            case .notApplicable:
                break
            }
            _ = conversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: spaceID,
                    folderId: nil,
                    index: index,
                    opensFolder: true
                ),
                preferredWindowId: nil
            )
        }
    }
}
