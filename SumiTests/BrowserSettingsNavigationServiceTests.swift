import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserSettingsNavigationServiceTests: XCTestCase {
    func testOpenSettingsSelectsPaneAndPresentsStandaloneWindow() {
        let harness = Harness()

        harness.commands.openSettings(selecting: .about, in: BrowserWindowState())

        XCTAssertEqual(harness.settings.currentSettingsTab, .about)
        XCTAssertEqual(harness.presentationCount, 1)
    }

    func testOpenSettingsDoesNotCreateOrRequireBrowserWindow() {
        let harness = Harness()

        harness.commands.openSettings(selecting: .privacy)

        XCTAssertEqual(harness.settings.currentSettingsTab, .privacy)
        XCTAssertEqual(harness.settings.privacySettingsRoute, .overview)
        XCTAssertEqual(harness.presentationCount, 1)
    }

    func testOpenSettingsDoesNothingWhenSettingsAreDetached() {
        let commands = BrowserSettingsNavigationService(
            settings: { nil },
            currentTab: { _ in nil }
        )

        commands.openSettings(selecting: .about)
    }

    func testOpenSiteSettingsUsesExplicitFocusedTab() {
        let harness = Harness()
        let focusedTab = Self.makeTab(url: "https://focused.example/page")

        harness.commands.openSiteSettings(
            focusing: focusedTab,
            in: BrowserWindowState()
        )

        XCTAssertEqual(harness.settings.currentSettingsTab, .privacy)
        XCTAssertEqual(
            harness.settings.privacySettingsRoute.siteSettingsFilter?.displayDomain,
            "focused.example"
        )
        XCTAssertEqual(harness.presentationCount, 1)
    }

    func testOpenSiteSettingsUsesCurrentTabFromExplicitWindow() {
        let currentTab = Self.makeTab(url: "https://current.example")
        let harness = Harness(currentTab: currentTab)

        harness.commands.openSiteSettings(in: BrowserWindowState())

        XCTAssertEqual(
            harness.settings.privacySettingsRoute.siteSettingsFilter?.requestingOriginIdentity,
            "https://current.example"
        )
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
        let settings: SumiSettingsService
        let currentTab: Tab?
        private(set) var presentationCount = 0

        lazy var commands = BrowserSettingsNavigationService(
            settings: { [settings] in settings },
            currentTab: { [currentTab] _ in currentTab }
        )

        init(currentTab: Tab? = nil) {
            self.currentTab = currentTab
            let defaults = UserDefaults(
                suiteName: "BrowserSettingsNavigationServiceTests-\(UUID().uuidString)"
            )!
            settings = SumiSettingsService(userDefaults: defaults)
            settings.navigation.installPresentationAction { [weak self] in
                self?.presentationCount += 1
            }
        }
    }
}
