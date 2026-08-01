import XCTest
import WebKit
import SumiDomain

@testable import Sumi

@MainActor
final class URLBarHubPageActionOwnerTests: XCTestCase {
    func testScreenshotFilenameSanitizesTitleAndScale() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example: One/Two")

        XCTAssertEqual(
            URLBarHubSnapshotActions.suggestedFilename(for: tab, quality: .fourX),
            "Example- One-Two@4x.png"
        )
    }

    func testScreenshotPreferencesMatchTheHubDefaultsAndSavedValues() throws {
        let suiteName = "URLBarHubPageActionOwnerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertEqual(
            URLBarHubScreenshotPreferences.options(in: defaults),
            URLBarHubScreenshotOptions(
                target: .visiblePage,
                destination: .askEveryTime,
                scale: .twoX
            )
        )

        defaults.set(
            URLBarHubScreenshotCaptureTarget.selectedArea.rawValue,
            forKey: URLBarHubScreenshotPreferences.captureTargetKey
        )
        defaults.set(
            URLBarHubScreenshotDestination.downloads.rawValue,
            forKey: URLBarHubScreenshotPreferences.destinationKey
        )
        defaults.set(
            URLBarHubScreenshotQuality.fourX.rawValue,
            forKey: URLBarHubScreenshotPreferences.qualityKey
        )

        XCTAssertEqual(
            URLBarHubScreenshotPreferences.options(in: defaults),
            URLBarHubScreenshotOptions(
                target: .selectedArea,
                destination: .downloads,
                scale: .fourX
            )
        )
    }

    func testScreenshotAvailabilityRequiresAWebPagePresentation() {
        let owner = URLBarHubPageActionOwner()
        let windowState = BrowserWindowState()
        let webTab = Tab(url: URL(string: "https://example.com")!)
        let webPage = ActivePageResolution(
            source: .selectedTab,
            windowState: windowState,
            tab: webTab,
            url: webTab.url,
            canonicalWebView: WKWebView()
        )
        XCTAssertTrue(owner.canCapture(webPage))

        let historyTab = Tab(url: SumiSurface.historySurfaceURL(rangeQuery: "all"))
        let historyPage = ActivePageResolution(
            source: .selectedTab,
            windowState: windowState,
            tab: historyTab,
            url: historyTab.url,
            canonicalWebView: WKWebView()
        )
        XCTAssertFalse(owner.canCapture(historyPage))
    }
}
