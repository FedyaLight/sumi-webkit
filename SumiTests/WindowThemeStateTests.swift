import XCTest
@testable import Sumi

final class WindowThemeStateTests: XCTestCase {
    @MainActor
    func testInitialWorkspaceThemeSeedsWindowThemeBeforeSpaceSelection() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let initialTheme = WorkspaceTheme(
            gradient: SpaceGradient(
                angle: 90,
                nodes: [
                    GradientNode(colorHex: "#0A84FF", location: 0.0),
                    GradientNode(colorHex: "#FFD60A", location: 1.0)
                ],
                grain: 0.125,
                opacity: 0.78
            )
        )

        let windowState = BrowserWindowState(initialWorkspaceTheme: initialTheme)
        let context = windowState.resolvedThemeContext(global: .light, settings: settings)

        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertTrue(context.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertFalse(context.workspaceTheme.visuallyEquals(.default))
    }

    func testBeginInteractivePreservesInitialProgress() {
        let sourceTheme = WorkspaceTheme(gradient: .default)
        let targetTheme = WorkspaceTheme(gradient: .incognito)
        let sourceSpaceId = UUID()
        let destinationSpaceId = UUID()
        var state = WindowThemeState()

        state.beginInteractive(
            sourceSpaceId: sourceSpaceId,
            destinationSpaceId: destinationSpaceId,
            from: sourceTheme,
            to: targetTheme,
            initialProgress: 0.4
        )

        XCTAssertTrue(state.isInteractive)
        XCTAssertEqual(state.sourceSpaceId, sourceSpaceId)
        XCTAssertEqual(state.destinationSpaceId, destinationSpaceId)
        XCTAssertEqual(state.progress, 0.4, accuracy: 0.0001)
        let expectedOpacity = sourceTheme.gradient.opacity
            + (targetTheme.gradient.opacity - sourceTheme.gradient.opacity) * 0.4
        XCTAssertEqual(
            state.resolvedTheme.gradient.opacity,
            expectedOpacity,
            accuracy: 0.0001
        )
    }

    func testUpdateProgressDuringInteractiveChangesResolvedThemeContinuously() {
        let sourceTheme = WorkspaceTheme(gradient: .default)
        let targetTheme = WorkspaceTheme(gradient: .incognito)
        var state = WindowThemeState()

        state.beginInteractive(
            sourceSpaceId: UUID(),
            destinationSpaceId: UUID(),
            from: sourceTheme,
            to: targetTheme,
            initialProgress: 0.25
        )
        let firstResolvedTheme = state.resolvedTheme

        state.updateProgress(0.75)
        let secondResolvedTheme = state.resolvedTheme

        XCTAssertNotEqual(firstResolvedTheme.gradient.opacity, secondResolvedTheme.gradient.opacity)
        let firstExpectedOpacity = sourceTheme.gradient.opacity
            + (targetTheme.gradient.opacity - sourceTheme.gradient.opacity) * 0.25
        let secondExpectedOpacity = sourceTheme.gradient.opacity
            + (targetTheme.gradient.opacity - sourceTheme.gradient.opacity) * 0.75
        XCTAssertEqual(firstResolvedTheme.gradient.opacity, firstExpectedOpacity, accuracy: 0.0001)
        XCTAssertEqual(secondResolvedTheme.gradient.opacity, secondExpectedOpacity, accuracy: 0.0001)
        XCTAssertFalse(secondResolvedTheme.visuallyEquals(sourceTheme))
        XCTAssertFalse(secondResolvedTheme.visuallyEquals(targetTheme))
    }

    func testCancelRestoresSourceThemeWithoutIntermediateSnap() {
        let sourceTheme = WorkspaceTheme(gradient: .default)
        let targetTheme = WorkspaceTheme(gradient: .incognito)
        var state = WindowThemeState()

        state.beginInteractive(
            sourceSpaceId: UUID(),
            destinationSpaceId: UUID(),
            from: sourceTheme,
            to: targetTheme,
            initialProgress: 0.6
        )

        state.cancel()

        XCTAssertEqual(state.committedTheme, sourceTheme)
        XCTAssertTrue(state.resolvedTheme.visuallyEquals(sourceTheme))
        XCTAssertFalse(state.isTransitioning)
        XCTAssertFalse(state.isInteractive)
        XCTAssertEqual(state.progress, 1.0, accuracy: 0.0001)
    }

    func testRestartInteractiveTransitionCanSwitchToOppositeNeighborWithoutSnap() {
        let sourceTheme = WorkspaceTheme(gradient: .default)
        let firstTargetTheme = WorkspaceTheme(gradient: .incognito)
        let secondTargetTheme = WorkspaceTheme(
            gradient: SpaceGradient(
                angle: 45,
                nodes: [
                    GradientNode(colorHex: "#FF3B30", location: 0.0),
                    GradientNode(colorHex: "#FF9500", location: 1.0)
                ],
                grain: 0.1,
                opacity: 0.7
            )
        )
        let sourceSpaceId = UUID()
        var state = WindowThemeState()

        state.beginInteractive(
            sourceSpaceId: sourceSpaceId,
            destinationSpaceId: UUID(),
            from: sourceTheme,
            to: firstTargetTheme,
            initialProgress: 0.62
        )

        state.beginInteractive(
            sourceSpaceId: sourceSpaceId,
            destinationSpaceId: UUID(),
            from: sourceTheme,
            to: secondTargetTheme,
            initialProgress: 0.18
        )

        XCTAssertTrue(state.isInteractive)
        XCTAssertEqual(state.sourceSpaceId, sourceSpaceId)
        XCTAssertEqual(state.progress, 0.18, accuracy: 0.0001)
        XCTAssertEqual(state.committedTheme, sourceTheme)
        XCTAssertTrue(state.sourceTheme?.visuallyEquals(sourceTheme) == true)
        XCTAssertTrue(state.targetTheme?.visuallyEquals(secondTargetTheme) == true)
    }
}
