import XCTest

final class GlanceWebsiteTimingCleanupTests: XCTestCase {
    func testGlancePostAnimationCallbacksUseCancellableTaskState() throws {
        let source = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayController.swift")
        let animationSource = try Self.slice(
            source,
            from: "private func present(",
            to: "private func animateContentFrame("
        )

        XCTAssertFalse(animationSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + duration)"))
        XCTAssertTrue(source.contains("private var postAnimationCompletionTask: Task<Void, Never>?"))
        XCTAssertTrue(source.contains("postAnimationCompletionTask?.cancel()"))
        XCTAssertTrue(source.contains("try? await Task.sleep(nanoseconds: Self.nanoseconds(for: duration))"))
        XCTAssertTrue(source.contains("self.session?.id == sessionID"))
        XCTAssertTrue(source.contains("scheduleOpeningCompletion("))
        XCTAssertTrue(source.contains("scheduleClosingCompletion("))
    }

    func testGlanceCloseConfirmationTimeoutRemainsCancellableDispatchWorkItem() throws {
        let source = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayController.swift")
        let resetSource = try Self.slice(
            source,
            from: "private func scheduleCloseConfirmationReset()",
            to: "private func resetCloseConfirmation()"
        )

        XCTAssertTrue(resetSource.contains("closeConfirmationWorkItem?.cancel()"))
        XCTAssertTrue(resetSource.contains("let item = DispatchWorkItem"))
        XCTAssertTrue(resetSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)"))
    }

    func testSplitPreviewFadeOutCleanupIsCancellableAndGenerationGuarded() throws {
        let source = try Self.source(named: "Sumi/Components/WebsiteView/WebsiteView.swift")
        let overlaySource = try Self.slice(
            source,
            from: "private struct SplitPreviewOverlay",
            to: "private struct SplitPreviewZone"
        )

        XCTAssertFalse(overlaySource.contains("DispatchQueue.main.asyncAfter"))
        XCTAssertTrue(overlaySource.contains("@State private var fadeOutCleanupTask: Task<Void, Never>?"))
        XCTAssertTrue(overlaySource.contains("fadeOutCleanupTask?.cancel()"))
        XCTAssertTrue(overlaySource.contains(".onDisappear"))
        XCTAssertTrue(overlaySource.contains("try? await Task.sleep(nanoseconds: 180_000_000)"))
        XCTAssertTrue(overlaySource.contains("generation == renderGeneration"))
        XCTAssertTrue(overlaySource.contains("renderedOpacity == 0"))
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
