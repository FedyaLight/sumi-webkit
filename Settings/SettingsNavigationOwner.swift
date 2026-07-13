//
//  SettingsNavigationOwner.swift
//  Sumi
//

import Foundation
import SumiDomain

/// Owns the ephemeral UI-routing state for the settings surface: which pane is
/// selected, the privacy sub-route, plus the `sumi://settings?pane=…` URL ↔
/// state translation. This is view navigation, not a persisted preference,
/// so it lives apart from the UserDefaults-backed `SumiSettingsService`.
@MainActor
@Observable
final class SettingsNavigationOwner {
    var currentSettingsTab: SettingsTabs = .general

    var privacySettingsRoute: SumiPrivacySettingsRoute = .overview

    /// Syncs sidebar state from `sumi://settings?pane=…`.
    func applyNavigation(from url: URL) {
        guard SumiSurface.isSettingsSurfaceURL(url),
              let raw = SumiSurface.settingsPaneQuery(from: url)?.lowercased()
        else { return }
        if let tab = SettingsTabs(paneQueryValue: raw) {
            currentSettingsTab = tab
            if tab == .privacy {
                privacySettingsRoute = Self.privacyRoute(from: url)
            }
        }
    }

    /// URL for the active settings tab.
    func settingsSurfaceURLForCurrentNavigation() -> URL {
        if currentSettingsTab == .privacy {
            switch privacySettingsRoute {
            case .overview:
                return currentSettingsTab.settingsSurfaceURL
            case .siteSettings(let filter):
                return SumiSurface.settingsSurfaceURL(
                    paneQuery: SettingsTabs.privacy.paneQueryValue,
                    extraQueryItems: Self.privacySiteSettingsQueryItems(filter: filter)
                )
            }
        }
        return currentSettingsTab.settingsSurfaceURL
    }

    private static func privacyRoute(from url: URL) -> SumiPrivacySettingsRoute {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let section = queryItems.first(where: { $0.name == "section" })?.value?.lowercased()
        guard section == "sitesettings" || section == "site-settings" else {
            return .overview
        }
        let filter = SumiSettingsSiteSettingsFilter(
            requestingOriginIdentity: queryItems.first(where: { $0.name == "origin" })?.value,
            topOriginIdentity: queryItems.first(where: { $0.name == "topOrigin" })?.value,
            displayDomain: queryItems.first(where: { $0.name == "site" })?.value
        )
        return .siteSettings(filter)
    }

    private static func privacySiteSettingsQueryItems(
        filter: SumiSettingsSiteSettingsFilter?
    ) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "section", value: "siteSettings")]
        if let filter {
            if let origin = filter.requestingOriginIdentity, !origin.isEmpty {
                items.append(URLQueryItem(name: "origin", value: origin))
            }
            if let topOrigin = filter.topOriginIdentity, !topOrigin.isEmpty {
                items.append(URLQueryItem(name: "topOrigin", value: topOrigin))
            }
            if let site = filter.displayDomain, !site.isEmpty {
                items.append(URLQueryItem(name: "site", value: site))
            }
        }
        return items
    }
}
