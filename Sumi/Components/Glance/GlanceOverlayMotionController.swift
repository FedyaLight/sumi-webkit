import AppKit
import QuartzCore

@MainActor
final class GlanceOverlayMotionController {
    enum Timing {
        static let glanceDuration: TimeInterval = 0.35
        static let reducedMotionDuration: TimeInterval = 0.08
        static let layoutDuration: TimeInterval = 0.16
        static let buttonDuration: TimeInterval = 0.2
        static let buttonOffset: CGFloat = 20
    }

    enum AnimationDirection {
        case opening
        case closing
    }

    private let contentShadowView: NSView
    private let webClipView: NSView

    init(contentShadowView: NSView, webClipView: NSView) {
        self.contentShadowView = contentShadowView
        self.webClipView = webClipView
    }

    func duration(
        reduceMotion: Bool,
        kind: DurationKind = .glance
    ) -> TimeInterval {
        if reduceMotion {
            return Timing.reducedMotionDuration
        }
        switch kind {
        case .glance:
            return Timing.glanceDuration
        case .button:
            return Timing.buttonDuration
        case .layout:
            return Timing.layoutDuration
        }
    }

    enum DurationKind {
        case glance
        case button
        case layout
    }

    func animateButtonsIn(
        actionChrome: GlanceOverlayActionChrome,
        configuration: GlanceOverlayConfiguration
    ) {
        let duration = duration(reduceMotion: configuration.reduceMotion, kind: .button)
        let finalFrame = actionChrome.frame
        if !configuration.reduceMotion {
            let xOffset = configuration.sidebarPosition == .right
                ? Timing.buttonOffset
                : -Timing.buttonOffset
            actionChrome.frame = finalFrame.offsetBy(dx: xOffset, dy: 0)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            actionChrome.setAnimatedFrame(finalFrame)
            actionChrome.setAnimatedAlphaValue(1)
        }
    }

    func animateContentFrame(
        from startFrame: CGRect,
        to endFrame: CGRect,
        direction: AnimationDirection,
        duration: TimeInterval,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        guard startFrame != endFrame, duration > 0 else {
            contentShadowView.frame = endFrame
            webClipView.frame = contentShadowView.bounds
            completion()
            return
        }

        contentShadowView.frame = startFrame
        webClipView.frame = contentShadowView.bounds

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction(for: direction)
            contentShadowView.animator().frame = endFrame
            webClipView.animator().frame = CGRect(origin: .zero, size: endFrame.size)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.contentShadowView.frame = endFrame
                self.webClipView.frame = self.contentShadowView.bounds
                completion()
            }
        }
    }

    func runLayoutUpdates(
        animated: Bool,
        updates: @escaping () -> Void
    ) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Timing.layoutDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                updates()
            }
        } else {
            updates()
        }
    }

    func runReducedMotionOpen(
        targetFrame: CGRect,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentShadowView.animator().frame = targetFrame
            contentShadowView.animator().alphaValue = 1
        }
    }

    func runReducedMotionClose(
        actionChrome: GlanceOverlayActionChrome,
        targetFrame: CGRect,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            actionChrome.setAnimatedAlphaValue(0)
            contentShadowView.animator().alphaValue = 0
            contentShadowView.animator().frame = targetFrame
        }
    }

    func fadeOutActionChrome(
        actionChrome: GlanceOverlayActionChrome,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            actionChrome.setAnimatedAlphaValue(0)
        }
    }

    func fadeOutActionChrome(
        actionChrome: GlanceOverlayActionChrome,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = timingFunction
            actionChrome.setAnimatedAlphaValue(0)
        }
    }

    func timingFunction(for direction: AnimationDirection) -> CAMediaTimingFunction {
        switch direction {
        case .opening:
            return CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        case .closing:
            return CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        }
    }

    var promotionTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    }

    func promotionDuration(reduceMotion: Bool) -> TimeInterval {
        min(duration(reduceMotion: reduceMotion, kind: .glance), 0.28)
    }
}
