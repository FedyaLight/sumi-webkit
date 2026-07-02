import AppKit

@MainActor
final class WebKitTransientChromeInteractionShieldOwner {
    struct Dependencies {
        let isSuppressionExempt: @MainActor () -> Bool
        let currentClientPoint: @MainActor () -> CGPoint?
        let evaluateJavaScript: @MainActor (String) -> Void
        let refreshMouseTracking: @MainActor () -> Void
        let clearHoveredLink: @MainActor () -> Void
    }

    private let dependencies: Dependencies
    private var isInteractionShieldApplied = false
    private var interactionShieldRects: [SumiTransientChromeInteractionShieldRect] = []

    private(set) var isMouseTrackingSuppressed = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func setMouseTrackingSuppressed(
        _ isSuppressed: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect] = []
    ) {
        let shouldSuppress = isSuppressed && !dependencies.isSuppressionExempt()
        setInteractionShieldApplied(
            shouldSuppress,
            shieldRects: shouldSuppress ? shieldRects : []
        )

        guard isMouseTrackingSuppressed != shouldSuppress else { return }

        isMouseTrackingSuppressed = shouldSuppress
        dependencies.refreshMouseTracking()

        if shouldSuppress {
            dependencies.clearHoveredLink()
        }
    }

    private func setInteractionShieldApplied(
        _ isApplied: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect]
    ) {
        let activeShieldRects = isApplied ? shieldRects : []
        guard isInteractionShieldApplied != isApplied ||
            interactionShieldRects != activeShieldRects
        else { return }

        isInteractionShieldApplied = isApplied
        interactionShieldRects = activeShieldRects
        let script = SumiTransientChromeInteractionShieldUserScript.makeSetActiveSource(
            isApplied,
            clientPoint: dependencies.currentClientPoint(),
            rects: activeShieldRects
        )
        dependencies.evaluateJavaScript(script)
    }
}
