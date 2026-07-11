import XCTest

@testable import Sumi

@MainActor
final class BrowserPermissionSettingsRoutesTests: XCTestCase {
    func testSettingsSurfaceURLKeepsUserscriptsPaneMapping() {
        XCTAssertEqual(
            BrowserPermissionSettingsRoutes.settingsSurfaceURL(for: .userScripts),
            URL(string: "sumi://settings?pane=userScripts")
        )
        XCTAssertEqual(
            BrowserPermissionSettingsRoutes.settingsSurfaceURL(for: .about),
            SettingsTabs.about.settingsSurfaceURL
        )
    }

    func testPrivacySiteSettingsURLKeepsQueryItemsAndOrder() {
        let url = BrowserPermissionSettingsRoutes.privacySiteSettingsSurfaceURL(
            filter: SumiSettingsSiteSettingsFilter(
                requestingOriginIdentity: "https://example.com",
                topOriginIdentity: "https://top.example",
                displayDomain: "example.com"
            )
        )

        XCTAssertEqual(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            [
                URLQueryItem(name: "pane", value: "privacy"),
                URLQueryItem(name: "section", value: "siteSettings"),
                URLQueryItem(name: "origin", value: "https://example.com"),
                URLQueryItem(name: "topOrigin", value: "https://top.example"),
                URLQueryItem(name: "site", value: "example.com"),
            ]
        )
    }

    func testPrivacySiteSettingsFilterUsesCommittedURLBeforeVisibleAndStoredURL() {
        let tab = Tab(
            url: URL(string: "https://stored.example/path")!,
            name: "Stored",
            loadsCachedFaviconOnInit: false
        )
        tab.extensionPageRuntimeOwner.committedMainDocumentURL = URL(string: "https://committed.example/page")!

        let filter = BrowserPermissionSettingsRoutes.privacySiteSettingsFilter(
            focusing: tab
        )

        XCTAssertEqual(filter?.requestingOriginIdentity, "https://committed.example")
        XCTAssertEqual(filter?.topOriginIdentity, "https://committed.example")
        XCTAssertEqual(filter?.displayDomain, "committed.example")
    }

    func testPrivacySiteSettingsFilterFallsBackToStoredURLAndRejectsInternalSurfaces() {
        let webTab = Tab(
            url: URL(string: "https://stored.example/path")!,
            name: "Stored",
            loadsCachedFaviconOnInit: false
        )
        let settingsTab = Tab(
            url: SettingsTabs.privacy.settingsSurfaceURL,
            name: "Settings",
            loadsCachedFaviconOnInit: false
        )

        XCTAssertEqual(
            BrowserPermissionSettingsRoutes.privacySiteSettingsFilter(
                focusing: webTab
            )?.requestingOriginIdentity,
            "https://stored.example"
        )
        XCTAssertNil(
            BrowserPermissionSettingsRoutes.privacySiteSettingsFilter(
                focusing: settingsTab
            )
        )
        XCTAssertNil(
            BrowserPermissionSettingsRoutes.privacySiteSettingsFilter(
                focusing: nil
            )
        )
    }

    func testPermissionPageWindowLookupNormalizesPageIdAndPrefersActiveWindow() {
        let registry = WindowRegistry()
        let firstWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        let firstTab = Tab(url: URL(string: "https://first.example")!, loadsCachedFaviconOnInit: false)
        let activeTab = Tab(url: URL(string: "https://active.example")!, loadsCachedFaviconOnInit: false)

        registry.register(firstWindow)
        registry.register(activeWindow)
        registry.setActive(activeWindow)

        let pageId = "  \(activeTab.currentPermissionPageId().uppercased())\n"
        let resolved = BrowserPermissionSettingsRoutes.windowState(
            displayingPermissionPageId: pageId,
            in: registry,
            tabsForDisplay: { windowState in
                if windowState === firstWindow {
                    return [firstTab, activeTab]
                }
                if windowState === activeWindow {
                    return [activeTab]
                }
                return []
            }
        )

        XCTAssertIdentical(resolved, activeWindow)
    }

    func testPermissionPageWindowLookupFallsBackToAllWindows() {
        let registry = WindowRegistry()
        let firstWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        let firstTab = Tab(url: URL(string: "https://first.example")!, loadsCachedFaviconOnInit: false)

        registry.register(firstWindow)
        registry.register(activeWindow)
        registry.setActive(activeWindow)

        let resolved = BrowserPermissionSettingsRoutes.windowState(
            displayingPermissionPageId: firstTab.currentPermissionPageId(),
            in: registry,
            tabsForDisplay: { windowState in
                windowState === firstWindow ? [firstTab] : []
            }
        )

        XCTAssertIdentical(resolved, firstWindow)
    }
}
