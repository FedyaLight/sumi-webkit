import AppKit
import QuartzCore

@MainActor
final class BrowserContentViewportShadowView: NSView {
    static var shadowOutset: CGFloat {
        ceil(
            BrowserContentViewportVisuals.shadowRadius * 3
                + max(
                    abs(BrowserContentViewportVisuals.shadowX),
                    abs(BrowserContentViewportVisuals.shadowY)
                )
        )
    }

    private static let shadowOpacityAnimationKey = "browserContentViewport.shadowOpacity"
    private static let targetShadowOpacity = Float(BrowserContentViewportVisuals.shadowOpacity)

    var viewportRect: NSRect = .zero {
        didSet { updateLayerShape() }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { updateLayerShape() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = []
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        configureLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updateLayerShape()
    }

    private func configureLayer() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.clear.cgColor
        layer.addSublayer(shadowSurfaceLayer)

        shadowSurfaceLayer.fillColor = NSColor.clear.cgColor
        shadowSurfaceLayer.shadowColor = NSColor.black.cgColor
        shadowSurfaceLayer.shadowOpacity = Self.targetShadowOpacity
        shadowSurfaceLayer.shadowRadius = BrowserContentViewportVisuals.shadowRadius
        shadowSurfaceLayer.shadowOffset = CGSize(
            width: BrowserContentViewportVisuals.shadowX,
            height: BrowserContentViewportVisuals.shadowY
        )
        updateLayerShape()
    }

    func setShadowOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowSurfaceLayer.removeAnimation(forKey: Self.shadowOpacityAnimationKey)
        shadowSurfaceLayer.shadowOpacity = min(max(opacity, 0), 1)
        CATransaction.commit()
    }

    func restoreShadowOpacity() {
        setShadowOpacity(Self.targetShadowOpacity)
    }

    func animateShadowOpacityReveal(
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction
    ) {
        let currentOpacity = shadowSurfaceLayer.presentation()?.shadowOpacity
            ?? shadowSurfaceLayer.shadowOpacity
        let targetOpacity = Self.targetShadowOpacity

        guard duration > 0, abs(currentOpacity - targetOpacity) > 0.000_1 else {
            restoreShadowOpacity()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowSurfaceLayer.shadowOpacity = targetOpacity
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = currentOpacity
        animation.toValue = targetOpacity
        animation.duration = duration
        animation.timingFunction = timingFunction
        shadowSurfaceLayer.add(animation, forKey: Self.shadowOpacityAnimationKey)
    }

    private func updateLayerShape() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let radius = max(
            0,
            min(cornerRadius, viewportRect.width / 2, viewportRect.height / 2)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        shadowSurfaceLayer.contentsScale = scale
        shadowSurfaceLayer.frame = viewportRect

        let path = CGPath(
            roundedRect: shadowSurfaceLayer.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        shadowSurfaceLayer.path = path
        shadowSurfaceLayer.shadowPath = path
        CATransaction.commit()
    }

    private let shadowSurfaceLayer = CAShapeLayer()
}
