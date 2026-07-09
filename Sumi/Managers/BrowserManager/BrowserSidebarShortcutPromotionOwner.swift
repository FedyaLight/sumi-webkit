import Foundation

@MainActor
final class BrowserSidebarShortcutPromotionOwner {
    private let copyShortcutPinToEssentials: @MainActor (
        ShortcutPin,
        String,
        EssentialsShortcutPlacementOwner.TargetContext
    ) -> Void

    init(
        copyShortcutPinToEssentials: @escaping @MainActor (
            ShortcutPin,
            String,
            EssentialsShortcutPlacementOwner.TargetContext
        ) -> Void
    ) {
        self.copyShortcutPinToEssentials = copyShortcutPinToEssentials
    }

    func pinShortcutGlobally(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        spaceId: UUID,
        liveTab: Tab?
    ) {
        copyShortcutPinToEssentials(
            pin,
            pin.resolvedDisplayTitle(liveTab: liveTab),
            EssentialsShortcutPlacementOwner.TargetContext(
                windowState: windowState,
                spaceId: spaceId
            )
        )
    }
}
