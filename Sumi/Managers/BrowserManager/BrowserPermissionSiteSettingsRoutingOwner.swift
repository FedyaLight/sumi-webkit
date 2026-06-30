import Foundation

@MainActor
final class BrowserPermissionSiteSettingsRoutingOwner {
    func settingsSurfaceURL(for pane: SettingsTabs) -> URL {
        switch pane {
        case .userScripts:
            return SumiSurface.settingsSurfaceURL(paneQuery: SettingsTabs.userScripts.paneQueryValue)
        default:
            return pane.settingsSurfaceURL
        }
    }

    func privacySiteSettingsSurfaceURL(focusing tab: Tab?) -> URL {
        privacySiteSettingsSurfaceURL(filter: privacySiteSettingsFilter(focusing: tab))
    }

    func privacySiteSettingsFilter(focusing tab: Tab?) -> SumiSettingsSiteSettingsFilter? {
        let mainURL = tab?.extensionPageRuntimeOwner.committedMainDocumentURLForCurrentPage()
            ?? tab?.existingWebView?.url
            ?? tab?.url
        let origin = SumiPermissionOrigin(url: mainURL)
        guard origin.isWebOrigin else { return nil }

        return SumiSettingsSiteSettingsFilter(
            requestingOrigin: origin,
            topOrigin: origin,
            displayDomain: SumiCurrentSitePermissionsViewModel.displayDomain(
                for: origin,
                fallbackURL: mainURL
            )
        )
    }

    func privacySiteSettingsSurfaceURL(filter: SumiSettingsSiteSettingsFilter?) -> URL {
        var extraQueryItems = [URLQueryItem(name: "section", value: "siteSettings")]
        if let filter {
            if let origin = filter.requestingOriginIdentity, !origin.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "origin", value: origin))
            }
            if let topOrigin = filter.topOriginIdentity, !topOrigin.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "topOrigin", value: topOrigin))
            }
            if let site = filter.displayDomain, !site.isEmpty {
                extraQueryItems.append(URLQueryItem(name: "site", value: site))
            }
        }
        return SumiSurface.settingsSurfaceURL(
            paneQuery: SettingsTabs.privacy.paneQueryValue,
            extraQueryItems: extraQueryItems
        )
    }

    func windowState(
        displayingPermissionPageId pageId: String,
        in windowRegistry: WindowRegistry?,
        tabsForDisplay: (BrowserWindowState) -> [Tab]
    ) -> BrowserWindowState? {
        guard let windowRegistry else { return nil }
        let normalizedPageId = pageId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let activeWindow = windowRegistry.activeWindow,
           windowState(activeWindow, displaysPermissionPageId: normalizedPageId, tabsForDisplay: tabsForDisplay) {
            return activeWindow
        }

        return windowRegistry.allWindows.first {
            windowState($0, displaysPermissionPageId: normalizedPageId, tabsForDisplay: tabsForDisplay)
        }
    }

    private func windowState(
        _ windowState: BrowserWindowState,
        displaysPermissionPageId pageId: String,
        tabsForDisplay: (BrowserWindowState) -> [Tab]
    ) -> Bool {
        tabsForDisplay(windowState).contains { tab in
            tab.currentPermissionPageId()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == pageId
        }
    }
}
