import AppKit

@MainActor
final class WebKitTransientChromeInteractionShieldOwner {
    private let isSuppressionExempt: @MainActor () -> Bool
    private let currentClientPoint: @MainActor () -> CGPoint?
    private let evaluateJavaScript: @MainActor (String) -> Void
    private let refreshMouseTracking: @MainActor () -> Void
    private let clearHoveredLink: @MainActor () -> Void
    private var isInteractionShieldApplied = false
    private var interactionShieldRects: [SumiTransientChromeInteractionShieldRect] = []

    private(set) var isMouseTrackingSuppressed = false

    init(
        isSuppressionExempt: @escaping @MainActor () -> Bool,
        currentClientPoint: @escaping @MainActor () -> CGPoint?,
        evaluateJavaScript: @escaping @MainActor (String) -> Void,
        refreshMouseTracking: @escaping @MainActor () -> Void,
        clearHoveredLink: @escaping @MainActor () -> Void
    ) {
        self.isSuppressionExempt = isSuppressionExempt
        self.currentClientPoint = currentClientPoint
        self.evaluateJavaScript = evaluateJavaScript
        self.refreshMouseTracking = refreshMouseTracking
        self.clearHoveredLink = clearHoveredLink
    }

    func setMouseTrackingSuppressed(
        _ isSuppressed: Bool,
        shieldRects: [SumiTransientChromeInteractionShieldRect] = []
    ) {
        let shouldSuppress = isSuppressed && !isSuppressionExempt()
        setInteractionShieldApplied(
            shouldSuppress,
            shieldRects: shouldSuppress ? shieldRects : []
        )

        guard isMouseTrackingSuppressed != shouldSuppress else { return }

        isMouseTrackingSuppressed = shouldSuppress
        refreshMouseTracking()

        if shouldSuppress {
            clearHoveredLink()
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
            clientPoint: currentClientPoint(),
            rects: activeShieldRects
        )
        evaluateJavaScript(script)
    }
}
