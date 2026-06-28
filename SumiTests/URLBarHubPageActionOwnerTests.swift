import XCTest

@testable import Sumi

@MainActor
final class URLBarHubPageActionOwnerTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testPopoverDelegatesScreenshotAndShareSideEffectsToActionOwner() throws {
        let popover = try source("Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(popover.contains("@StateObject private var pageActionOwner = URLBarHubPageActionOwner()"))
        XCTAssertTrue(popover.contains("pageActionOwner.captureCurrentPageUsingSavedSettings("))
        XCTAssertTrue(popover.contains("pageActionOwner.presentScreenshotSettings("))
        XCTAssertTrue(popover.contains("pageActionOwner.shareCurrentPage("))
        XCTAssertFalse(popover.contains("NSSavePanel()"))
        XCTAssertFalse(popover.contains("URLBarHubScreenshotRegionSelector.selectRegion"))
        XCTAssertFalse(popover.contains("URLBarHubScreenshotCapture.writeVisibleSnapshot"))
        XCTAssertFalse(popover.contains("presentSharingServicePicker([url]"))
    }

    func testPageActionOwnerKeepsScreenshotAndShareActionFlow() throws {
        let actionOwner = try source("Sumi/Components/Sidebar/URLBarHubPageActionOwner.swift")

        XCTAssertTrue(actionOwner.contains("@Published private(set) var isCapturingScreenshot"))
        XCTAssertTrue(actionOwner.contains("ownerView: shareButtonAnchor.view"))
        XCTAssertTrue(actionOwner.contains("browserManager.presentSharingServicePicker([url], source: source)"))
        XCTAssertTrue(actionOwner.contains("browserManager.getWebView("))
        XCTAssertTrue(actionOwner.contains("URLBarHubScreenshotSettingsPresenter.present("))
        XCTAssertTrue(actionOwner.contains("URLBarHubScreenshotRegionSelector.selectRegion(in: webView)"))
        XCTAssertTrue(actionOwner.contains("NSSavePanel()"))
        XCTAssertTrue(actionOwner.contains("DownloadFileUtilities.uniqueDestination(for: suggestedFilename)"))
        XCTAssertTrue(actionOwner.contains("URLBarHubScreenshotCapture.writeVisibleSnapshot("))
        XCTAssertFalse(actionOwner.contains("[weak self]"))
    }

    func testScreenshotFilenameSanitizesTitleAndScale() {
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example: One/Two")

        XCTAssertEqual(
            URLBarHubSnapshotActions.suggestedFilename(for: tab, quality: .fourX),
            "Example- One-Two@4x.png"
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
