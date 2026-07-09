//
//  SumiSurface.swift
//  Sumi
//
//  Internal browser surfaces and helpers.
//

import Foundation

public enum SumiSurface {
    public static let emptyTabURL = URL(string: "about:blank")!
    /// Internal settings UI opened as a browser tab (`sumi://settings?pane=…`).
    public static let settingsURLHost = "settings"
    /// Internal history UI opened as a browser tab (`sumi://history?range=…`).
    public static let historyURLHost = "history"
    /// Internal bookmarks manager opened as a browser tab (`sumi://bookmarks?folder=…`).
    public static let bookmarksURLHost = "bookmarks"
    /// SF Symbol used for the settings tab row / favicon slot (sidebar, pinned UI, etc.).
    public static let settingsTabFaviconSystemImageName = "gearshape.fill"
    public static let historyTabFaviconSystemImageName = "clock.arrow.circlepath"
    public static let bookmarksTabFaviconSystemImageName = "book.closed.fill"

    public static func isEmptyNewTabURL(_ url: URL) -> Bool {
        url.absoluteString == emptyTabURL.absoluteString
    }

    public static func isSettingsSurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == settingsURLHost.lowercased()
    }

    public static func isHistorySurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == historyURLHost.lowercased()
    }

    public static func isBookmarksSurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == bookmarksURLHost.lowercased()
    }

    public static func isNativeSurfaceURL(_ url: URL) -> Bool {
        isSettingsSurfaceURL(url)
            || isHistorySurfaceURL(url)
            || isBookmarksSurfaceURL(url)
    }

    /// Stable `pane` query value for `sumi://settings?pane=…`.
    public static func settingsSurfaceURL(
        paneQuery: String,
        extraQueryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.settingsURLHost
        components.queryItems = [URLQueryItem(name: "pane", value: paneQuery)] + extraQueryItems
        return components.url ?? URL(string: "sumi://settings?pane=general")!
    }

    public static func settingsPaneQuery(from url: URL) -> String? {
        guard isSettingsSurfaceURL(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pane" })?
            .value
    }

    public static func historySurfaceURL(rangeQuery: String) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.historyURLHost
        components.queryItems = [URLQueryItem(name: "range", value: rangeQuery)]
        return components.url ?? URL(string: "sumi://history?range=all")!
    }

    public static func bookmarksSurfaceURL(selecting folderID: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.bookmarksURLHost
        if let folderID, !folderID.isEmpty {
            components.queryItems = [URLQueryItem(name: "folder", value: folderID)]
        }
        return components.url ?? URL(string: "sumi://bookmarks")!
    }

    public static func bookmarksSelectedFolderID(from url: URL) -> String? {
        guard isBookmarksSurfaceURL(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "folder" })?
            .value
    }
}
