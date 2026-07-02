import AppKit
import QuartzCore

@MainActor
final class GlanceOverlayContentVisualStyleOwner {
    private struct Style {
        let cornerRadius: CGFloat
        let shadowOpacity: Float
        let shadowRadius: CGFloat
        let shadowOffset: CGSize
    }

    private let contentShadowView: NSView
    private let webClipView: NSView

    init(
        contentShadowView: NSView,
        webClipView: NSView
    ) {
        self.contentShadowView = contentShadowView
        self.webClipView = webClipView
    }

    func configureViews() {
        contentShadowView.wantsLayer = true
        contentShadowView.layer?.shadowColor = NSColor.black.cgColor
        contentShadowView.layer?.shadowOpacity = GlanceOverlayLayout.Metrics.glanceShadowOpacity
        contentShadowView.layer?.shadowRadius = GlanceOverlayLayout.Metrics.glanceShadowRadius
        contentShadowView.layer?.shadowOffset = GlanceOverlayLayout.Metrics.glanceShadowOffset
        if #available(macOS 10.15, *) {
            contentShadowView.layer?.cornerCurve = .continuous
        }

        webClipView.wantsLayer = true
        webClipView.layer?.masksToBounds = true
        webClipView.autoresizingMask = [.width, .height]
        if #available(macOS 10.15, *) {
            webClipView.layer?.cornerCurve = .continuous
        }
    }

    func applySurfaceColor(_ surfaceColor: NSColor) {
        contentShadowView.layer?.backgroundColor = surfaceColor.cgColor
        webClipView.layer?.backgroundColor = surfaceColor.cgColor
    }

    func applyGlanceStyle(for configuration: GlanceOverlayConfiguration) {
        apply(style: Self.glanceStyle(for: configuration))
    }

    func applyBrowserViewportStyle(for configuration: GlanceOverlayConfiguration) {
        apply(style: Self.browserViewportStyle(for: configuration))
    }

    func animateToBrowserViewportStyle(
        for configuration: GlanceOverlayConfiguration,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        animate(
            to: Self.browserViewportStyle(for: configuration),
            duration: duration,
            timingFunction: timingFunction
        )
    }

    func removeAnimations() {
        let keys = [
            "cornerRadius",
            "shadowOpacity",
            "shadowRadius",
            "shadowOffset",
        ]
        for key in keys {
            contentShadowView.layer?.removeAnimation(forKey: "glancePromotion.\(key)")
            webClipView.layer?.removeAnimation(forKey: "glancePromotion.\(key)")
        }
    }

    private static func glanceStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> Style {
        Style(
            cornerRadius: configuration.cornerRadius,
            shadowOpacity: GlanceOverlayLayout.Metrics.glanceShadowOpacity,
            shadowRadius: GlanceOverlayLayout.Metrics.glanceShadowRadius,
            shadowOffset: GlanceOverlayLayout.Metrics.glanceShadowOffset
        )
    }

    private static func browserViewportStyle(
        for configuration: GlanceOverlayConfiguration
    ) -> Style {
        Style(
            cornerRadius: configuration.browserContentCornerRadius,
            shadowOpacity: Float(BrowserContentViewportVisuals.shadowOpacity),
            shadowRadius: BrowserContentViewportVisuals.shadowRadius,
            shadowOffset: CGSize(
                width: BrowserContentViewportVisuals.shadowX,
                height: BrowserContentViewportVisuals.shadowY
            )
        )
    }

    private func apply(style: Style) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentShadowView.layer?.cornerRadius = style.cornerRadius
        contentShadowView.layer?.shadowOpacity = style.shadowOpacity
        contentShadowView.layer?.shadowRadius = style.shadowRadius
        contentShadowView.layer?.shadowOffset = style.shadowOffset
        webClipView.layer?.cornerRadius = style.cornerRadius
        CATransaction.commit()
    }

    private func animate(
        to style: Style,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        guard duration > 0,
              let shadowLayer = contentShadowView.layer,
              let clipLayer = webClipView.layer
        else {
            apply(style: style)
            return
        }

        let currentShadowLayer = shadowLayer.presentation() ?? shadowLayer
        let currentClipLayer = clipLayer.presentation() ?? clipLayer
        let fromShadowCornerRadius = currentShadowLayer.cornerRadius
        let fromClipCornerRadius = currentClipLayer.cornerRadius
        let fromShadowOpacity = currentShadowLayer.shadowOpacity
        let fromShadowRadius = currentShadowLayer.shadowRadius
        let fromShadowOffset = currentShadowLayer.shadowOffset

        addLayerAnimation(
            to: shadowLayer,
            keyPath: "cornerRadius",
            fromValue: fromShadowCornerRadius,
            toValue: style.cornerRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: clipLayer,
            keyPath: "cornerRadius",
            fromValue: fromClipCornerRadius,
            toValue: style.cornerRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowOpacity",
            fromValue: fromShadowOpacity,
            toValue: style.shadowOpacity,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowRadius",
            fromValue: fromShadowRadius,
            toValue: style.shadowRadius,
            duration: duration,
            timingFunction: timingFunction
        )
        addLayerAnimation(
            to: shadowLayer,
            keyPath: "shadowOffset",
            fromValue: NSValue(size: fromShadowOffset),
            toValue: NSValue(size: style.shadowOffset),
            duration: duration,
            timingFunction: timingFunction
        )
    }

    private func addLayerAnimation(
        to layer: CALayer,
        keyPath: String,
        fromValue: Any,
        toValue: Any,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = timingFunction
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "glancePromotion.\(keyPath)")
    }
}
