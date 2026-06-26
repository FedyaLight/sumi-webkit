import XCTest

final class SidebarSpaceBodySourceGuardTests: XCTestCase {
    func testSpaceViewUsesNamedStructuralRevisionReader() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceView.swift")

        XCTAssertTrue(source.contains("SidebarTabStructuralRevisionReader"))
        XCTAssertFalse(source.contains("let _ = browserManager.tabStructuralRevision"))
    }

    func testTabFolderBodyUsesProjectionInsteadOfManagerBackedGetters() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let bodySource = try Self.sourceRange(
            in: source,
            from: "var body: some View",
            to: "private func refreshLiveFolderIfNeeded"
        )

        XCTAssertTrue(bodySource.contains("SidebarFolderViewProjectionReader"))
        XCTAssertTrue(source.contains("SidebarFolderViewProjection"))

        for forbidden in [
            "browserManager.tabManager",
            "browserManager.liveFolderManager",
            "browserManager.profileManager",
            "baseFolderItems",
            "liveFolderItems",
            "sortedFolderItems("
        ] {
            XCTAssertFalse(bodySource.contains(forbidden), "TabFolderView.body should not contain \(forbidden)")
        }

        XCTAssertFalse(source.contains("private var baseFolderItems"))
        XCTAssertFalse(source.contains("private var liveFolderItems"))
        XCTAssertFalse(source.contains("private func sortedFolderItems"))
    }

    func testSpaceScrollChromeNotificationsKeepSynchronousMainActorBoundary() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceScrollChrome.swift")
        let observationSource = try Self.sourceRange(
            in: source,
            from: "private func syncScrollBoundsObservation",
            to: "private func configurePassiveScrollIndicator"
        )

        XCTAssertTrue(observationSource.contains("forName: NSView.boundsDidChangeNotification"))
        XCTAssertTrue(observationSource.contains("forName: NSView.frameDidChangeNotification"))
        XCTAssertEqual(observationSource.components(separatedBy: "queue: nil").count - 1, 2)
        XCTAssertEqual(observationSource.components(separatedBy: "MainActor.assumeIsolated").count - 1, 2)
        XCTAssertFalse(observationSource.contains("Task { @MainActor"))
    }

    private static func sourceRange(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return String(source[start..<end])
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}
