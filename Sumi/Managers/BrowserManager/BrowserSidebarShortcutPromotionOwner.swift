import Foundation

@MainActor
final class BrowserSidebarShortcutPromotionOwner {
    struct Dependencies {
        let copyShortcutPinToEssentials: @MainActor (
            ShortcutPin,
            String,
            TabManager.EssentialsTargetContext
        ) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func pinShortcutGlobally(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        spaceId: UUID,
        liveTab: Tab?
    ) {
        dependencies.copyShortcutPinToEssentials(
            pin,
            pin.resolvedDisplayTitle(liveTab: liveTab),
            TabManager.EssentialsTargetContext(
                windowState: windowState,
                spaceId: spaceId
            )
        )
    }
}

extension BrowserSidebarShortcutPromotionOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            copyShortcutPinToEssentials: { [weak browserManager] pin, title, context in
                _ = browserManager?.tabManager.copyShortcutPinToEssentials(
                    pin,
                    title: title,
                    context: context
                )
            }
        )
    }
}
