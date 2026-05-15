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
        shadowSurfaceLayer.shadowOpacity = Float(BrowserContentViewportVisuals.shadowOpacity)
        shadowSurfaceLayer.shadowRadius = BrowserContentViewportVisuals.shadowRadius
        shadowSurfaceLayer.shadowOffset = CGSize(
            width: BrowserContentViewportVisuals.shadowX,
            height: BrowserContentViewportVisuals.shadowY
        )
        updateLayerShape()
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
