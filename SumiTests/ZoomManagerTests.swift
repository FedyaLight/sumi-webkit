import WebKit
import XCTest
@testable import Sumi

@MainActor
final class ZoomManagerTests: XCTestCase {
    private let domain = "example.com"

    override func setUp() {
        super.setUp()
        clearZoomDefaults()
    }

    override func tearDown() {
        clearZoomDefaults()
        super.tearDown()
    }

    func testZoomUsesDuckDuckGoPresetSteps() {
        let manager = ZoomManager()
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
        let manager = ZoomManager()
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
        let manager = ZoomManager()
        let webView = WKWebView()
        let firstTabId = UUID()
        let secondTabId = UUID()

        manager.applyZoom(1.15, to: webView, domain: domain, tabId: firstTabId)
        manager.applyZoom(2.5, to: webView, domain: "other.example", tabId: secondTabId)

        XCTAssertEqual(manager.getZoomPercentageDisplay(for: firstTabId), "115%")
        XCTAssertEqual(manager.getZoomPercentageDisplay(for: secondTabId), "250%")
    }

    func testResetRemovesSavedDomainZoom() {
        let manager = ZoomManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.applyZoom(1.5, to: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(manager.getZoomLevel(for: domain), 1.5, accuracy: 0.001)

        manager.resetZoom(for: webView, domain: domain, tabId: tabId)
        XCTAssertEqual(manager.getZoomLevel(for: domain), 1.0, accuracy: 0.001)
        XCTAssertNil(UserDefaults.standard.object(forKey: "zoom.\(domain)"))
    }

    func testLoadSavedZoomAppliesPerSiteZoom() {
        let manager = ZoomManager()
        let webView = WKWebView()
        let tabId = UUID()

        manager.saveZoomLevel(2.5, for: domain)
        manager.loadSavedZoom(for: webView, domain: domain, tabId: tabId)

        XCTAssertEqual(webView.pageZoom, 2.5, accuracy: 0.001)
        XCTAssertEqual(manager.getZoomLevel(for: tabId), 2.5, accuracy: 0.001)
    }

    private func clearZoomDefaults() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("zoom.") {
            defaults.removeObject(forKey: key)
        }
    }
}
