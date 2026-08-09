import Foundation

@MainActor
final class SidebarRegularTabShortcutCommands {
    private let favoritePinning: RegularTabFavoritePinningService
    private let spacePinning: ShortcutPinSpacePinningTransaction

    init(
        favoritePinning: RegularTabFavoritePinningService,
        spacePinning: ShortcutPinSpacePinningTransaction
    ) {
        self.favoritePinning = favoritePinning
        self.spacePinning = spacePinning
    }

    func pinTabToSpace(_ tab: Tab, spaceID: UUID) {
        spacePinning.pin(tab, to: spaceID)
    }

    func addTabToFavorite(
        _ tab: Tab,
        in space: Space,
        windowState: BrowserWindowState
    ) {
        favoritePinning.pin(
            tab,
            context: FavoriteShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }
}
