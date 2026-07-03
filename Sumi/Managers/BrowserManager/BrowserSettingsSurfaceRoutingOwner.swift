import Foundation

@MainActor
final class BrowserSettingsSurfaceRoutingOwner {
    struct Dependencies {
        let activeWindow: @MainActor () -> BrowserWindowState?
        let currentTab: @MainActor (BrowserWindowState) -> Tab?
        let settingsSurfaceURL: @MainActor (SettingsTabs) -> URL
        let privacySiteSettingsSurfaceURL: @MainActor (Tab?) -> URL
        let openNativeBrowserSurface: @MainActor (SumiNativeBrowserSurfaceKind, URL, BrowserWindowState) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func openSettingsTab(
        selecting pane: SettingsTabs,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? dependencies.activeWindow() else { return }
        dependencies.openNativeBrowserSurface(
            .settings,
            dependencies.settingsSurfaceURL(pane),
            windowState
        )
    }

    func openSiteSettingsTab(
        focusing tab: Tab? = nil,
        in windowState: BrowserWindowState? = nil
    ) {
        guard let windowState = windowState ?? dependencies.activeWindow() else { return }
        let targetTab = tab ?? dependencies.currentTab(windowState)

        dependencies.openNativeBrowserSurface(
            .settings,
            dependencies.privacySiteSettingsSurfaceURL(targetTab),
            windowState
        )
    }
}

extension BrowserSettingsSurfaceRoutingOwner.Dependencies {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            activeWindow: { [weak browserManager] in
                browserManager?.windowRegistry?.activeWindow
            },
            currentTab: { [weak browserManager] windowState in
                browserManager?.windowTabContextOwner.currentTab(for: windowState)
            },
            settingsSurfaceURL: { [weak browserManager] pane in
                browserManager?.permissionSiteSettingsRoutingOwner.settingsSurfaceURL(for: pane)
                    ?? pane.settingsSurfaceURL
            },
            privacySiteSettingsSurfaceURL: { [weak browserManager] tab in
                browserManager?.permissionSiteSettingsRoutingOwner.privacySiteSettingsSurfaceURL(focusing: tab)
                    ?? SettingsTabs.privacy.settingsSurfaceURL
            },
            openNativeBrowserSurface: { [weak browserManager] kind, url, windowState in
                browserManager?.nativeSurfaceRoutingOwner.openNativeBrowserSurface(
                    kind,
                    url: url,
                    in: windowState
                )
            }
        )
    }
}
