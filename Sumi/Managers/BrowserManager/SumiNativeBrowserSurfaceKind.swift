import Foundation

@MainActor
enum SumiNativeBrowserSurfaceKind {
    case settings
    case history
    case bookmarks

    func matches(_ tab: Tab) -> Bool {
        switch self {
        case .settings:
            return tab.representsSumiSettingsSurface
        case .history:
            return tab.representsSumiHistorySurface
        case .bookmarks:
            return tab.representsSumiBookmarksSurface
        }
    }

    func configure(_ tab: Tab, url: URL) {
        tab.url = url
        switch self {
        case .settings:
            tab.name = "Settings"
            tab.faviconPresentation = .systemSymbol(SumiSurface.settingsTabFaviconSystemImageName)
        case .history:
            tab.name = "History"
            tab.faviconPresentation = .systemSymbol(SumiSurface.historyTabFaviconSystemImageName)
        case .bookmarks:
            tab.name = "Bookmarks"
            tab.faviconPresentation = .systemSymbol(SumiSurface.bookmarksTabFaviconSystemImageName)
        }
        tab.faviconIsTemplateGlobePlaceholder = false
    }
}
