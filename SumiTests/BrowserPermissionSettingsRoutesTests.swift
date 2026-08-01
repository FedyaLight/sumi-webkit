import XCTest
import SumiDomain

@testable import Sumi

@MainActor
final class BrowserPermissionSettingsRoutesTests: XCTestCase {
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
        let historyTab = Tab(
            url: SumiSurface.historySurfaceURL(rangeQuery: "all"),
            name: "History",
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
                focusing: historyTab
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
