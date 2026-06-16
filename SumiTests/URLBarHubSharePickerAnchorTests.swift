import XCTest

final class URLBarHubSharePickerAnchorTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testURLHubSharePickerUsesShareButtonAnchor() throws {
        let hubSource = try source("Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(
            hubSource.contains("@StateObject private var shareButtonAnchor")
        )
        XCTAssertTrue(
            hubSource.contains(".background(URLBarHubShareAnchorView(anchor: shareButtonAnchor))")
        )
        XCTAssertTrue(
            hubSource.contains("ownerView: shareButtonAnchor.view"),
            "URL Hub sharing must pass the Share button view as the presentation source owner"
        )
    }

    func testSharingServicePickerPrefersPresentationSourceOwnerView() throws {
        let dialogSource = try source(
            "Sumi/Managers/BrowserManager/BrowserManager+DialogsUtilities.swift"
        )

        XCTAssertTrue(
            dialogSource.contains("if let ownerView = source.originOwnerView"),
            "Sharing picker should anchor to the originating control when available"
        )
        XCTAssertTrue(
            dialogSource.contains("picker.show(relativeTo: anchorRect, of: anchorView"),
            "Sharing picker should use the resolved anchor view instead of always using contentView"
        )
    }
}
