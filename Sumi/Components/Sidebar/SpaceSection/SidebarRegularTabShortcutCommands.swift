import Foundation

@MainActor
final class SidebarRegularTabShortcutCommands {
    private let essentialPinning: RegularTabEssentialPinningService
    private let spacePinning: ShortcutPinSpacePinningTransaction

    init(
        essentialPinning: RegularTabEssentialPinningService,
        spacePinning: ShortcutPinSpacePinningTransaction
    ) {
        self.essentialPinning = essentialPinning
        self.spacePinning = spacePinning
    }

    func pinTabToSpace(_ tab: Tab, spaceID: UUID) {
        spacePinning.pin(tab, to: spaceID)
    }

    func addTabToEssentials(
        _ tab: Tab,
        in space: Space,
        windowState: BrowserWindowState
    ) {
        essentialPinning.pin(
            tab,
            context: EssentialsShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: space.id
            )
        )
    }
}
