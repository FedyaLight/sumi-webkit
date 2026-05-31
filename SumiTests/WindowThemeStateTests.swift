import SwiftUI
import XCTest
@testable import Sumi

final class WindowThemeStateTests: XCTestCase {
    @MainActor
    func testInitialWorkspaceThemeSeedsWindowThemeBeforeSpaceSelection() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = SumiSettingsService(userDefaults: harness.defaults)
        let initialTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#0A84FF",
                        isPrimary: true,
                        position: .topLeft
                    ),
                    WorkspaceThemeColor(
                        hex: "#FFD60A",
                        position: .bottom
                    )
                ],
                opacity: 0.78,
                texture: 0.125
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
        let sourceTheme = WorkspaceTheme(gradientTheme: .default)
        let targetTheme = WorkspaceTheme(gradientTheme: .incognito)
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
        XCTAssertTrue(state.resolvedTheme.visuallyEquals(sourceTheme))
    }

    func testUpdateProgressDuringInteractiveChangesResolvedThemeContinuously() {
        let sourceTheme = WorkspaceTheme(gradientTheme: .default)
        let targetTheme = WorkspaceTheme(gradientTheme: .incognito)
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

        XCTAssertTrue(firstResolvedTheme.visuallyEquals(sourceTheme))
        XCTAssertTrue(secondResolvedTheme.visuallyEquals(targetTheme))
    }

    func testResolvedThemeContextOnlySkipsNativeMaterialWhenChromeIsFullyCovered() {
        let opaqueTheme = makeTheme(opacity: 0.98)
        let translucentTheme = makeTheme(opacity: 0.72)

        let idleOpaque = makeContext(
            workspaceTheme: opaqueTheme,
            sourceWorkspaceTheme: opaqueTheme,
            targetWorkspaceTheme: opaqueTheme,
            isInteractiveTransition: false
        )
        XCTAssertTrue(idleOpaque.rendersOpaqueCustomChromeTheme)

        let mixedTransition = makeContext(
            workspaceTheme: translucentTheme,
            sourceWorkspaceTheme: opaqueTheme,
            targetWorkspaceTheme: translucentTheme,
            isInteractiveTransition: true
        )
        XCTAssertFalse(mixedTransition.rendersOpaqueCustomChromeTheme)

        let opaqueTransition = makeContext(
            workspaceTheme: opaqueTheme,
            sourceWorkspaceTheme: opaqueTheme,
            targetWorkspaceTheme: opaqueTheme,
            isInteractiveTransition: true
        )
        XCTAssertTrue(opaqueTransition.rendersOpaqueCustomChromeTheme)
    }

    @MainActor
    func testNativeSurfaceSchemeFollowsWorkspaceChromeInsteadOfDarkGlobalScheme() {
        let lightWorkspaceContext = ResolvedThemeContext(
            globalColorScheme: .dark,
            chromeColorScheme: .light,
            sourceChromeColorScheme: .light,
            targetChromeColorScheme: .light,
            workspaceTheme: makeTheme(opacity: 0.72),
            sourceWorkspaceTheme: makeTheme(opacity: 0.72),
            targetWorkspaceTheme: makeTheme(opacity: 0.72),
            isInteractiveTransition: false,
            transitionProgress: 1
        )

        let nativeSurfaceScheme = lightWorkspaceContext.nativeSurfaceColorScheme
        let nativeSurfaceThemeContext = lightWorkspaceContext.nativeSurfaceThemeContext

        XCTAssertEqual(nativeSurfaceScheme, .light)
        XCTAssertEqual(nativeSurfaceThemeContext.globalColorScheme, .light)
        XCTAssertEqual(nativeSurfaceThemeContext.chromeColorScheme, .light)
    }

    @MainActor
    func testNativeSurfaceSchemeStaysDarkWhenTransitionIncludesDarkChrome() {
        let mixedTransitionContext = ResolvedThemeContext(
            globalColorScheme: .light,
            chromeColorScheme: .light,
            sourceChromeColorScheme: .dark,
            targetChromeColorScheme: .light,
            workspaceTheme: makeTheme(opacity: 0.72),
            sourceWorkspaceTheme: .incognito,
            targetWorkspaceTheme: makeTheme(opacity: 0.72),
            isInteractiveTransition: true,
            transitionProgress: 0.5
        )

        let nativeSurfaceScheme = mixedTransitionContext.nativeSurfaceColorScheme

        XCTAssertEqual(nativeSurfaceScheme, .dark)
    }

    func testCancelRestoresSourceThemeWithoutIntermediateSnap() {
        let sourceTheme = WorkspaceTheme(gradientTheme: .default)
        let targetTheme = WorkspaceTheme(gradientTheme: .incognito)
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

    private func makeTheme(opacity: Double) -> WorkspaceTheme {
        WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#F4EFDF",
                        isPrimary: true,
                        position: .topLeft
                    ),
                    WorkspaceThemeColor(
                        hex: "#F0B8CD",
                        position: .bottom
                    )
                ],
                opacity: opacity,
                texture: 0.125
            )
        )
    }

    private func makeContext(
        workspaceTheme: WorkspaceTheme,
        sourceWorkspaceTheme: WorkspaceTheme,
        targetWorkspaceTheme: WorkspaceTheme,
        isInteractiveTransition: Bool
    ) -> ResolvedThemeContext {
        ResolvedThemeContext(
            globalColorScheme: .dark,
            chromeColorScheme: .dark,
            sourceChromeColorScheme: .dark,
            targetChromeColorScheme: .dark,
            workspaceTheme: workspaceTheme,
            sourceWorkspaceTheme: sourceWorkspaceTheme,
            targetWorkspaceTheme: targetWorkspaceTheme,
            isInteractiveTransition: isInteractiveTransition,
            transitionProgress: isInteractiveTransition ? 0.5 : 1
        )
    }

    func testRestartInteractiveTransitionCanSwitchToOppositeNeighborWithoutSnap() {
        let sourceTheme = WorkspaceTheme(gradientTheme: .default)
        let firstTargetTheme = WorkspaceTheme(gradientTheme: .incognito)
        let secondTargetTheme = WorkspaceTheme(
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .topLeft
                    ),
                    WorkspaceThemeColor(
                        hex: "#FF9500",
                        position: .bottom
                    )
                ],
                opacity: 0.7,
                texture: 0.1
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
