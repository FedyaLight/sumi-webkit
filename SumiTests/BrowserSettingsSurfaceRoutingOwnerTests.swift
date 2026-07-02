import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserSettingsSurfaceRoutingOwnerTests: XCTestCase {
    func testOpenSettingsTabUsesExplicitWindowAndPaneURL() {
        let windowState = BrowserWindowState()
        let harness = Harness(activeWindow: BrowserWindowState())
        let owner = harness.makeOwner()

        owner.openSettingsTab(selecting: .about, in: windowState)

        XCTAssertEqual(harness.openRequests.map(\.kind), [.settings])
        XCTAssertEqual(harness.openRequests.map(\.url), [Harness.aboutURL])
        XCTAssertEqual(harness.openRequests.map(\.windowId), [windowState.id])
    }

    func testOpenSettingsTabFallsBackToActiveWindow() {
        let activeWindow = BrowserWindowState()
        let harness = Harness(activeWindow: activeWindow)
        let owner = harness.makeOwner()

        owner.openSettingsTab(selecting: .privacy)

        XCTAssertEqual(harness.openRequests.map(\.kind), [.settings])
        XCTAssertEqual(harness.openRequests.map(\.url), [Harness.privacyURL])
        XCTAssertEqual(harness.openRequests.map(\.windowId), [activeWindow.id])
    }

    func testOpenSettingsTabDoesNothingWithoutWindow() {
        let harness = Harness(activeWindow: nil)
        let owner = harness.makeOwner()

        owner.openSettingsTab(selecting: .about)

        XCTAssertTrue(harness.openRequests.isEmpty)
    }

    func testOpenSiteSettingsUsesExplicitFocusedTab() {
        let windowState = BrowserWindowState()
        let currentTab = Self.makeTab(url: "https://current.example")
        let focusedTab = Self.makeTab(url: "https://focused.example")
        let harness = Harness(activeWindow: windowState, currentTab: currentTab)
        let owner = harness.makeOwner()

        owner.openSiteSettingsTab(focusing: focusedTab, in: windowState)

        XCTAssertEqual(harness.privacyURLTabIds, [focusedTab.id])
        XCTAssertEqual(harness.openRequests.map(\.url), [Harness.siteSettingsURL])
        XCTAssertEqual(harness.openRequests.map(\.windowId), [windowState.id])
    }

    func testOpenSiteSettingsFallsBackToActiveWindowCurrentTab() {
        let activeWindow = BrowserWindowState()
        let currentTab = Self.makeTab(url: "https://current.example")
        let harness = Harness(activeWindow: activeWindow, currentTab: currentTab)
        let owner = harness.makeOwner()

        owner.openSiteSettingsTab()

        XCTAssertEqual(harness.privacyURLTabIds, [currentTab.id])
        XCTAssertEqual(harness.openRequests.map(\.url), [Harness.siteSettingsURL])
        XCTAssertEqual(harness.openRequests.map(\.windowId), [activeWindow.id])
    }

    private static func makeTab(url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: "Tab",
            loadsCachedFaviconOnInit: false
        )
    }

    @MainActor
    private final class Harness {
        static let aboutURL = URL(string: "sumi://settings?pane=about")!
        static let privacyURL = URL(string: "sumi://settings?pane=privacy")!
        static let siteSettingsURL = URL(string: "sumi://settings?pane=privacy&section=siteSettings")!

        var activeWindow: BrowserWindowState?
        var currentTab: Tab?
        var privacyURLTabIds: [UUID?] = []
        var openRequests: [(kind: SumiNativeBrowserSurfaceKind, url: URL, windowId: UUID)] = []

        init(activeWindow: BrowserWindowState?, currentTab: Tab? = nil) {
            self.activeWindow = activeWindow
            self.currentTab = currentTab
        }

        func makeOwner() -> BrowserSettingsSurfaceRoutingOwner {
            BrowserSettingsSurfaceRoutingOwner(
                dependencies: BrowserSettingsSurfaceRoutingOwner.Dependencies(
                    activeWindow: { self.activeWindow },
                    currentTab: { _ in self.currentTab },
                    settingsSurfaceURL: { pane in
                        switch pane {
                        case .about:
                            return Self.aboutURL
                        case .privacy:
                            return Self.privacyURL
                        default:
                            return pane.settingsSurfaceURL
                        }
                    },
                    privacySiteSettingsSurfaceURL: { tab in
                        self.privacyURLTabIds.append(tab?.id)
                        return Self.siteSettingsURL
                    },
                    openNativeBrowserSurface: { kind, url, windowState in
                        self.openRequests.append(
                            (kind: kind, url: url, windowId: windowState.id)
                        )
                    }
                )
            )
        }
    }
}
