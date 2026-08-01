import Foundation
import SumiDomain

@MainActor
enum SumiNativeBrowserSurfaceKind {
    case history
    case bookmarks

    func matches(_ tab: Tab) -> Bool {
        switch self {
        case .history:
            return tab.representsSumiHistorySurface
        case .bookmarks:
            return tab.representsSumiBookmarksSurface
        }
    }

    func configure(_ tab: Tab, url: URL) {
        tab.url = url
        switch self {
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
