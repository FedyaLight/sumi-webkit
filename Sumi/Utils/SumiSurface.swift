//
//  SumiSurface.swift
//  Sumi
//
//  Internal browser surfaces and helpers.
//

import Foundation

enum SumiSurface {
    static let emptyTabURL = URL(string: "about:blank")!
    /// Internal settings UI opened as a browser tab (`sumi://settings?pane=…`).
    static let settingsURLHost = "settings"
    /// Internal history UI opened as a browser tab (`sumi://history?range=…`).
    static let historyURLHost = "history"
    /// SF Symbol used for the settings tab row / favicon slot (sidebar, pinned UI, etc.).
    static let settingsTabFaviconSystemImageName = "gearshape.fill"
    static let historyTabFaviconSystemImageName = "clock.arrow.circlepath"

    static func isEmptyNewTabURL(_ url: URL) -> Bool {
        url.absoluteString == emptyTabURL.absoluteString
    }

    static func isSettingsSurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == settingsURLHost.lowercased()
    }

    static func isHistorySurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == historyURLHost.lowercased()
    }

    /// Stable `pane` query value for `sumi://settings?pane=…`.
    static func settingsSurfaceURL(paneQuery: String) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.settingsURLHost
        components.queryItems = [URLQueryItem(name: "pane", value: paneQuery)]
        return components.url ?? URL(string: "sumi://settings?pane=appearance")!
    }

    static func settingsPaneQuery(from url: URL) -> String? {
        guard isSettingsSurfaceURL(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pane" })?
            .value
    }

    static func historySurfaceURL(rangeQuery: String) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.historyURLHost
        components.queryItems = [URLQueryItem(name: "range", value: rangeQuery)]
        return components.url ?? URL(string: "sumi://history?range=all")!
    }

    static func historyRange(from url: URL) -> HistoryRange? {
        guard isHistorySurfaceURL(url) else { return nil }
        let queryValue = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "range" })?
            .value
        return queryValue.flatMap(HistoryRange.init(rawValue:))
    }

}
