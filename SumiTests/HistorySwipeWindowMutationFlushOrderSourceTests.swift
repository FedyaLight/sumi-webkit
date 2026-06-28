import XCTest

final class HistorySwipeWindowMutationFlushOrderSourceTests: XCTestCase {
    func testFlushOwnerPreparesVisibleWebViewsBeforeRefreshingCompositor() throws {
        let source = try Self.source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let flushSource = try Self.slice(
            source,
            from: "func flushPendingMutations",
            to: "func cancelPendingMutations"
        )

        let prepareRange = try XCTUnwrap(
            flushSource.range(of: "_ = prepareVisibleWebViews(pendingMutations.windowState)")
        )
        let refreshRange = try XCTUnwrap(
            flushSource.range(of: "pendingMutations.windowState.refreshCompositor()")
        )

        XCTAssertLessThan(prepareRange.lowerBound, refreshRange.lowerBound)
    }

    private static func source(named relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static func slice(
        _ source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound)
        return String(source[start..<end])
    }
}
