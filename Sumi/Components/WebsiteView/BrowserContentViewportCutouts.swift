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

    private static let targetShadowOpacity = Float(BrowserContentViewportVisuals.shadowOpacity)

    var viewportRect: NSRect = .zero {
        didSet { updateLayerShape() }
    }

    var cornerRadii: ChromeCornerRadii = .uniform(0) {
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

    private func updateLayerShape() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2

        // Clamp each corner radius to the viewport's half-extents so oversized
        // radii degrade to a pill/half-pill rather than producing a degenerate path.
        let boundsRect = shadowSurfaceLayer.bounds
        let maxHalf = min(boundsRect.width, boundsRect.height) / 2
        func clamp(_ value: CGFloat) -> CGFloat {
            max(0, min(value, maxHalf))
        }
        let radii = ChromeCornerRadii(
            topLeading: clamp(cornerRadii.topLeading),
            topTrailing: clamp(cornerRadii.topTrailing),
            bottomLeading: clamp(cornerRadii.bottomLeading),
            bottomTrailing: clamp(cornerRadii.bottomTrailing)
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        shadowSurfaceLayer.contentsScale = scale
        shadowSurfaceLayer.frame = viewportRect

        let path = BrowserContentViewportShadowView.makeRoundedRectPath(
            in: boundsRect,
            radii: radii
        )
        shadowSurfaceLayer.path = path
        shadowSurfaceLayer.shadowPath = path
        CATransaction.commit()
    }

    /// Builds a rounded-rect path matching the supplied per-corner radii.
    /// Coordinates follow Core Animation's y-up convention (origin at the
    /// bottom-left), so the visually top corners live at the path's `maxY` edge.
    private static func makeRoundedRectPath(
        in rect: CGRect,
        radii: ChromeCornerRadii
    ) -> CGPath {
        // Uniform case: defer to the system primitive. This is the exact shape
        // the original implementation produced, so the default chrome shadow is
        // byte-for-byte unchanged.
        if radii.isUniform {
            let radius = max(0, min(radii.maxRadius, rect.width / 2, rect.height / 2))
            return CGPath(
                roundedRect: rect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        }

        return makeAsymmetricRoundedRectPath(in: rect, radii: radii)
    }

    /// Hand-built asymmetric path for the frameless (top-only) case. Traced
    /// clockwise in y-up space; corners with a zero radius produce a sharp angle.
    private static func makeAsymmetricRoundedRectPath(
        in rect: CGRect,
        radii: ChromeCornerRadii
    ) -> CGPath {
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY

        let path = CGMutablePath()

        // Bottom-leading corner (minX, minY).
        path.move(to: CGPoint(x: minX, y: minY + radii.bottomLeading))
        if radii.bottomLeading > 0 {
            path.addArc(
                center: CGPoint(x: minX + radii.bottomLeading, y: minY + radii.bottomLeading),
                radius: radii.bottomLeading,
                startAngle: .pi,
                endAngle: 1.5 * .pi,
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: minY))
        }

        // Bottom edge → bottom-trailing corner (maxX, minY).
        path.addLine(to: CGPoint(x: maxX - radii.bottomTrailing, y: minY))
        if radii.bottomTrailing > 0 {
            path.addArc(
                center: CGPoint(x: maxX - radii.bottomTrailing, y: minY + radii.bottomTrailing),
                radius: radii.bottomTrailing,
                startAngle: 1.5 * .pi,
                endAngle: 2 * .pi,
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: maxX, y: minY))
        }

        // Right edge → top-trailing corner (maxX, maxY).
        path.addLine(to: CGPoint(x: maxX, y: maxY - radii.topTrailing))
        if radii.topTrailing > 0 {
            path.addArc(
                center: CGPoint(x: maxX - radii.topTrailing, y: maxY - radii.topTrailing),
                radius: radii.topTrailing,
                startAngle: 0,
                endAngle: .pi / 2,
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: maxX, y: maxY))
        }

        // Top edge → top-leading corner (minX, maxY).
        path.addLine(to: CGPoint(x: minX + radii.topLeading, y: maxY))
        if radii.topLeading > 0 {
            path.addArc(
                center: CGPoint(x: minX + radii.topLeading, y: maxY - radii.topLeading),
                radius: radii.topLeading,
                startAngle: .pi / 2,
                endAngle: .pi,
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: minX, y: maxY))
        }

        path.closeSubpath()
        return path
    }

    private let shadowSurfaceLayer = CAShapeLayer()
}
