import AppKit
import QuartzCore

enum CollapsedSidebarShadowChrome {
    static let shadowOpacityAnimationKey = "collapsedSidebarShadow.opacity"

    @MainActor
    static func configure(_ view: CollapsedSidebarOverlayRootView) {
        SidebarColumnPaintlessChrome.configure(view)
        guard let layer = view.layer else { return }

        layer.masksToBounds = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = SidebarHoverOverlayMetrics.shadowRadius
        layer.shadowOffset = SidebarHoverOverlayMetrics.shadowOffset
    }

    @MainActor
    static func updatePath(for view: CollapsedSidebarOverlayRootView) {
        guard let layer = view.layer else { return }

        let bounds = view.bounds
        let radius = max(
            0,
            min(
                SidebarHoverOverlayMetrics.cornerRadius,
                bounds.width / 2,
                bounds.height / 2
            )
        )
        let path = CGPath(
            roundedRect: bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.contentsScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer.shadowPath = path
        CATransaction.commit()
    }

    @MainActor
    static func setShadowVisible(
        _ isVisible: Bool,
        for view: CollapsedSidebarOverlayRootView,
        animationDuration: TimeInterval
    ) {
        guard let layer = view.layer else { return }

        let targetOpacity: Float = isVisible ? SidebarHoverOverlayMetrics.shadowOpacity : 0
        let currentOpacity = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity
        layer.removeAnimation(forKey: shadowOpacityAnimationKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowOpacity = targetOpacity
        CATransaction.commit()

        guard animationDuration > 0,
              abs(currentOpacity - targetOpacity) > Float.ulpOfOne
        else {
            return
        }

        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = animationDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: shadowOpacityAnimationKey)
    }
}
