import Foundation

@MainActor
final class BrowserSidebarShortcutPromotionOwner {
    struct Dependencies {
        let makePromotionTab: @MainActor (URL, String, String, UUID) -> Tab?
        let pinTab: @MainActor (Tab, TabManager.EssentialsTargetContext) -> Void
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
        guard let promotionTab = dependencies.makePromotionTab(
            pin.launchURL,
            pin.resolvedDisplayTitle(liveTab: liveTab),
            SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId
        ) else {
            return
        }

        dependencies.pinTab(
            promotionTab,
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
            makePromotionTab: { [weak browserManager] url, title, favicon, spaceId in
                guard let browserManager else { return nil }
                return Tab(
                    url: url,
                    name: title,
                    favicon: favicon,
                    spaceId: spaceId,
                    index: 0,
                    browserManager: browserManager
                )
            },
            pinTab: { [weak browserManager] tab, context in
                browserManager?.tabManager.pinTab(tab, context: context)
            }
        )
    }
}
