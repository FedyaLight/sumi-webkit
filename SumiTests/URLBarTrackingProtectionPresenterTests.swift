import XCTest

@testable import Sumi

final class URLBarTrackingProtectionPresenterTests: XCTestCase {
    func testURLHubSourceContainsOnlyUnifiedProtectionRow() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(source.contains("id: \"adblock-protection\""))
        XCTAssertTrue(source.contains("title: \"Adblock & Protection\""))
        XCTAssertFalse(source.contains("URLBarTrackingProtectionPresenter"))
        XCTAssertFalse(source.contains("URLBarAdblockPresenter"))
        XCTAssertFalse(source.contains("kind: .tracking("))
        XCTAssertFalse(source.contains("kind: .adBlocking("))
    }

    @MainActor
    func testURLHubWithoutCoordinatorDoesNotFallBackToLegacyProtectionRows() {
        let snapshot = SiteControlsSnapshot.resolve(
            url: URL(string: "https://example.com")!,
            profile: nil,
            protectionCoordinator: nil,
            trackingProtectionModule: nil,
            adBlockingModule: nil
        )

        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "tracking-protection" })
        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "ad-blocking" })
        XCTAssertFalse(snapshot.settingsRows.contains { $0.id == "adblock-protection" })
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
