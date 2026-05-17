import XCTest
import WebKit

@testable import Sumi

@MainActor
final class GlanceManagerTests: XCTestCase {
    func testSameURLPresentationIsNoOp() throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)

        XCTAssertTrue(browserManager.glanceManager.currentSession === session)
        XCTAssertEqual(browserManager.glanceManager.phase, .opening)
    }

    func testDifferentURLPresentationReplacesAndCleansOldPreview() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let firstURL = URL(string: "https://first.example/page")!
        let secondURL = URL(string: "https://second.example/page")!

        browserManager.glanceManager.presentExternalURL(firstURL, from: sourceTab)
        let firstSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let firstPreviewTab = firstSession.previewTab
        _ = try await waitForPreviewWebView(in: firstSession)
        XCTAssertNotNil(firstPreviewTab.existingWebView)

        browserManager.glanceManager.presentExternalURL(secondURL, from: sourceTab)

        let secondSession = try XCTUnwrap(browserManager.glanceManager.currentSession)
        XCTAssertNotEqual(secondSession.id, firstSession.id)
        XCTAssertEqual(secondSession.currentURL, secondURL)
        XCTAssertNil(firstPreviewTab.existingWebView)
    }

    func testDismissCleansPreviewAndReturnsIdle() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        _ = try await waitForPreviewWebView(in: session)
        XCTAssertNotNil(previewTab.existingWebView)

        browserManager.glanceManager.finishAnimatedDismissal(sessionID: session.id)

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertFalse(browserManager.glanceManager.isActive)
        XCTAssertNil(previewTab.existingWebView)
    }

    func testMoveToNewTabAdoptsSamePreviewTabAndWebView() async throws {
        let browserManager = BrowserManager()
        let sourceTab = makeSourceTab(in: browserManager)
        let url = URL(string: "https://destination.example/page")!

        browserManager.glanceManager.presentExternalURL(url, from: sourceTab)
        let session = try XCTUnwrap(browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        let webView = try await waitForPreviewWebView(in: session)

        browserManager.glanceManager.moveToNewTab()

        XCTAssertNil(browserManager.glanceManager.currentSession)
        XCTAssertEqual(browserManager.glanceManager.phase, .idle)
        XCTAssertTrue(browserManager.tabManager.tab(for: previewTab.id) === previewTab)
        XCTAssertTrue(previewTab.existingWebView === webView)
    }

    private func makeSourceTab(in browserManager: BrowserManager) -> Tab {
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Glance Tests")
        return browserManager.tabManager.createNewTab(
            url: "https://source.example/page",
            in: space,
            activate: true
        )
    }

    private func waitForPreviewWebView(
        in session: GlanceSession,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WKWebView {
        for _ in 0..<20 {
            if let webView = session.previewTab.existingWebView {
                return webView
            }
            await Task.yield()
        }
        return try XCTUnwrap(session.previewTab.existingWebView, file: file, line: line)
    }
}
