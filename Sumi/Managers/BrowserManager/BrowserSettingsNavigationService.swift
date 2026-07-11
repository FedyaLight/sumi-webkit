import Foundation

@MainActor
final class BrowserSettingsNavigationService {
    private let activeWindow: @MainActor () -> BrowserWindowState?
    private let currentTab: @MainActor (BrowserWindowState) -> Tab?
    private let settingsSurfaceURL: @MainActor (SettingsTabs) -> URL
    private let siteSettingsSurfaceURL: @MainActor (Tab?) -> URL
    private let openNativeSurface: @MainActor (
        SumiNativeBrowserSurfaceKind,
        URL,
        BrowserWindowState
    ) -> Void

    init(
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab?,
        settingsSurfaceURL: @escaping @MainActor (SettingsTabs) -> URL,
        siteSettingsSurfaceURL: @escaping @MainActor (Tab?) -> URL,
        openNativeSurface: @escaping @MainActor (
            SumiNativeBrowserSurfaceKind,
            URL,
            BrowserWindowState
        ) -> Void
    ) {
        self.activeWindow = activeWindow
        self.currentTab = currentTab
        self.settingsSurfaceURL = settingsSurfaceURL
        self.siteSettingsSurfaceURL = siteSettingsSurfaceURL
        self.openNativeSurface = openNativeSurface
    }

    func openSettings(
        selecting pane: SettingsTabs,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? activeWindow() else { return }
        openNativeSurface(.settings, settingsSurfaceURL(pane), windowState)
    }

    func openSiteSettings(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? activeWindow() else { return }
        let targetTab = tab ?? currentTab(windowState)
        openNativeSurface(.settings, siteSettingsSurfaceURL(targetTab), windowState)
    }
}
