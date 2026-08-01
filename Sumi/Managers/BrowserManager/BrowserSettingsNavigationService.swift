import Foundation

/// Routes browser commands into the app's single Settings window.
@MainActor
final class BrowserSettingsNavigationService {
    private let settings: @MainActor () -> SumiSettingsService?
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?

    init(
        settings: @escaping @MainActor () -> SumiSettingsService?,
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?
    ) {
        self.settings = settings
        self.currentTab = currentTab
    }

    func openSettings(
        selecting pane: SettingsTabs,
        in windowState: BrowserWindowState? = nil
    ) {
        settings()?.navigation.openSettings(selecting: pane)
    }

    func openSiteSettings(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        let targetTab = tab ?? windowState.flatMap(currentTab)
        let filter = BrowserPermissionSettingsRoutes
            .privacySiteSettingsFilter(focusing: targetTab)
        settings()?.navigation.openSiteSettings(filter: filter)
    }
}
