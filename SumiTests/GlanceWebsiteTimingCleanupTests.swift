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

    func testGlancePromotionHandoffStateHasDedicatedOwner() throws {
        let source = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayController.swift")
        let controllerSource = try Self.slice(
            source,
            from: "final class GlanceOverlayController",
            to: "private func webContentIsFocused()"
        )

        XCTAssertTrue(source.contains("private final class GlancePromotionHandoffOwner"))
        XCTAssertTrue(controllerSource.contains("private let promotionHandoff = GlancePromotionHandoffOwner()"))
        XCTAssertFalse(controllerSource.contains("private var isAnimatingPromotion"))
        XCTAssertFalse(controllerSource.contains("private var isCompletingPromotionHandoff"))
        XCTAssertTrue(controllerSource.contains("promotionHandoff.registerPreviewHost("))
        XCTAssertTrue(
            controllerSource.contains(
                "preservingPromotionHandoff: promotionHandoff.preservesPresentedHostDuringTeardown"
            )
        )
    }

    func testGlanceOverlayControllerDelegatesLayoutAndActionChromeToDedicatedOwners() throws {
        let controllerSource = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayController.swift")
        let layoutSource = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayLayout.swift")
        let actionChromeSource = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayActionChrome.swift")
        let rootViewSource = try Self.source(named: "Sumi/Components/Glance/GlanceOverlayRootView.swift")

        XCTAssertTrue(controllerSource.contains("private let overlayLayout = GlanceOverlayLayout()"))
        XCTAssertTrue(controllerSource.contains("private lazy var actionChrome = GlanceOverlayActionChrome"))
        XCTAssertTrue(layoutSource.contains("struct GlanceOverlayLayout"))
        XCTAssertTrue(actionChromeSource.contains("final class GlanceOverlayActionChrome"))
        XCTAssertTrue(rootViewSource.contains("enum GlanceOverlayCursorRegionLayout"))
        XCTAssertFalse(controllerSource.contains("private enum Metrics"))
        XCTAssertFalse(controllerSource.contains("private func targetContentFrame("))
        XCTAssertFalse(controllerSource.contains("private func handleActionButtonHit"))
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
