import Foundation
import SwiftUI

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
            tab.favicon = Image(systemName: SumiSurface.settingsTabFaviconSystemImageName)
        case .history:
            tab.name = "History"
            tab.favicon = Image(systemName: SumiSurface.historyTabFaviconSystemImageName)
        case .bookmarks:
            tab.name = "Bookmarks"
            tab.favicon = Image(systemName: SumiSurface.bookmarksTabFaviconSystemImageName)
        }
        tab.faviconIsTemplateGlobePlaceholder = false
    }
}
