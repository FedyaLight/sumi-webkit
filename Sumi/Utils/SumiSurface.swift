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
    /// SF Symbol used for the settings tab row / favicon slot (sidebar, pinned UI, etc.).
    public static let settingsTabFaviconSystemImageName = "gearshape.fill"

    public static func isEmptyNewTabURL(_ url: URL) -> Bool {
        url.absoluteString == emptyTabURL.absoluteString
    }

    public static func isSettingsSurfaceURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "sumi"
            && url.host?.lowercased() == settingsURLHost.lowercased()
    }

    /// Stable `pane` query value for `sumi://settings?pane=…`.
    public static func settingsSurfaceURL(paneQuery: String) -> URL {
        var components = URLComponents()
        components.scheme = "sumi"
        components.host = Self.settingsURLHost
        components.queryItems = [URLQueryItem(name: "pane", value: paneQuery)]
        return components.url ?? URL(string: "sumi://settings?pane=appearance")!
    }

    public static func settingsPaneQuery(from url: URL) -> String? {
        guard isSettingsSurfaceURL(url) else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "pane" })?
            .value
    }
}
