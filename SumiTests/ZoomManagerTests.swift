import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ZoomManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let domain = "example.com"

    override func setUp() {
        super.setUp()

        suiteName = "ZoomManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testZoomUsesDuckDuckGoPresetSteps() {
        let manager = makeManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.applyZoom(0.75, to: webView, domain: domain, tabId: tabId)
        manager.zoomIn(for: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(webView.pageZoom, 0.85, accuracy: 0.001)
        XCTAssertEqual(manager.getZoomLevel(for: tabId), 0.85, accuracy: 0.001)

        manager.zoomIn(for: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(webView.pageZoom, 1.0, accuracy: 0.001)

        manager.zoomIn(for: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(webView.pageZoom, 1.15, accuracy: 0.001)
    }

    func testZoomClampsAtMinimumAndMaximum() {
        let manager = makeManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.applyZoom(0.1, to: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(webView.pageZoom, 0.5, accuracy: 0.001)
        XCTAssertTrue(manager.isAtMinimumZoom(for: tabId))

        manager.applyZoom(5.0, to: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(webView.pageZoom, 3.0, accuracy: 0.001)
        XCTAssertTrue(manager.isAtMaximumZoom(for: tabId))
    }

    func testPercentageDisplayUsesTabScopedZoom() {
        let manager = makeManager()
        let webView = WKWebView()
        let firstTabId = UUID()
        let secondTabId = UUID()

        manager.applyZoom(1.15, to: webView, domain: domain, tabId: firstTabId)
        manager.applyZoom(2.5, to: webView, domain: "other.example", tabId: secondTabId)

        XCTAssertEqual(manager.getZoomPercentageDisplay(for: firstTabId), "115%")
        XCTAssertEqual(manager.getZoomPercentageDisplay(for: secondTabId), "250%")
    }

    func testResetRemovesSavedDomainZoom() {
        let manager = makeManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.applyZoom(1.5, to: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(manager.getZoomLevel(for: domain), 1.5, accuracy: 0.001)

        manager.resetZoom(for: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(manager.getZoomLevel(for: domain), 1.0, accuracy: 0.001)
        XCTAssertNil(defaults.object(forKey: legacyZoomKey(for: domain)))
    }

    func testLoadSavedZoomAppliesPerSiteZoom() {
        let manager = makeManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.saveZoomLevel(2.5, for: domain)
        manager.loadSavedZoom(for: webView, domain: domain, tabId: tabId)

        XCTAssertEqual(webView.pageZoom, 2.5, accuracy: 0.001)
        XCTAssertEqual(manager.getZoomLevel(for: tabId), 2.5, accuracy: 0.001)
    }

    func testProfileScopedZoomUsesNormalizedKeyAndFallsBackToLegacy() {
        let manager = makeManager()
        let profileId = UUID()

        defaults.set(1.25, forKey: legacyZoomKey(for: domain))

        XCTAssertEqual(
            manager.getZoomLevel(for: domain, profileId: profileId),
            1.25,
            accuracy: 0.001
        )

        manager.saveZoomLevel(1.5, for: " .Example.COM ", profileId: profileId)

        XCTAssertEqual(
            manager.getZoomLevel(for: domain, profileId: profileId),
            1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(manager.getZoomLevel(for: domain), 1.25, accuracy: 0.001)
        XCTAssertNotNil(defaults.object(forKey: scopedZoomKey(for: domain, profileId: profileId)))
        XCTAssertNotNil(defaults.object(forKey: legacyZoomKey(for: domain)))
        XCTAssertEqual(defaults.double(forKey: scopedZoomKey(for: domain, profileId: profileId)), 1.5, accuracy: 0.001)
        XCTAssertEqual(defaults.double(forKey: legacyZoomKey(for: domain)), 1.25, accuracy: 0.001)
    }

    func testDefaultProfileScopedZoomRemovesScopedAndLegacyValues() {
        let manager = makeManager()
        let profileId = UUID()

        defaults.set(1.25, forKey: legacyZoomKey(for: domain))
        defaults.set(1.5, forKey: scopedZoomKey(for: domain, profileId: profileId))

        manager.saveZoomLevel(1.0, for: domain, profileId: profileId)

        XCTAssertEqual(manager.getZoomLevel(for: domain, profileId: profileId), 1.0, accuracy: 0.001)
        XCTAssertNil(defaults.object(forKey: scopedZoomKey(for: domain, profileId: profileId)))
        XCTAssertNil(defaults.object(forKey: legacyZoomKey(for: domain)))
    }

    func testLoadSavedZoomUsesProfileScopedZoomWhenAvailable() {
        let manager = makeManager()
        let webView = WKWebView()
        let tabId = UUID()
        let profileId = UUID()

        manager.saveZoomLevel(2.0, for: domain, profileId: profileId)
        manager.loadSavedZoom(for: webView, domain: domain, tabId: tabId, profileId: profileId)

        XCTAssertEqual(webView.pageZoom, 2.0, accuracy: 0.001)
        XCTAssertEqual(manager.getZoomLevel(for: tabId), 2.0, accuracy: 0.001)
        XCTAssertEqual(manager.getZoomLevel(for: domain, profileId: profileId), 2.0, accuracy: 0.001)
    }

    private func makeManager() -> ZoomManager {
        ZoomManager(userDefaults: defaults)
    }

    private func legacyZoomKey(for domain: String) -> String {
        "zoom.\(domain.normalizedWebsiteDataDomain)"
    }

    private func scopedZoomKey(for domain: String, profileId: UUID) -> String {
        "zoom.\(profileId.uuidString.lowercased()).\(domain.normalizedWebsiteDataDomain)"
    }
}
