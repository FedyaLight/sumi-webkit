import AppKit
import QuartzCore
import SwiftUI

extension ChromeCornerRadii {
    /// Maps the semantic shape to Core Animation's y-up corner mask.
    var caCornerMask: CACornerMask {
        guard maxRadius > 0 else { return [] }

        var mask: CACornerMask = [
            .layerMinXMaxYCorner,
            .layerMaxXMaxYCorner,
        ]
        if isUniform {
            mask.insert(.layerMinXMinYCorner)
            mask.insert(.layerMaxXMinYCorner)
        }
        return mask
    }
}

enum BrowserContentViewportShape {
    static func path(
        in rect: CGRect,
        cornerRadii: ChromeCornerRadii
    ) -> CGPath {
        let radii = cornerRadii.clamped(to: rect.size)
        // SwiftUI names corners in y-down screen space. AppKit is y-up, so swap
        // top and bottom while preserving leading/trailing.
        let corners = RectangleCornerRadii(
            topLeading: radii.bottomLeading,
            bottomLeading: radii.topLeading,
            bottomTrailing: radii.topTrailing,
            topTrailing: radii.bottomTrailing
        )
        return Path(
            roundedRect: rect,
            cornerRadii: corners,
            style: .continuous
        ).cgPath
    }
}

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

    private struct ShapeSignature: Equatable {
        let viewportRect: NSRect
        let cornerRadii: ChromeCornerRadii
        let scale: CGFloat
    }

    private static let targetShadowOpacity = Float(BrowserContentViewportVisuals.shadowOpacity)
    private let shadowSurfaceLayer = CAShapeLayer()
    private var viewportRect: NSRect = .zero
    private var cornerRadii: ChromeCornerRadii = .uniform(0)
    private var appliedShape: ShapeSignature?

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
        updateLayerShapeIfNeeded()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerShapeIfNeeded()
    }

    func apply(viewportRect: NSRect, cornerRadii: ChromeCornerRadii) {
        self.viewportRect = viewportRect
        self.cornerRadii = cornerRadii
        updateLayerShapeIfNeeded()
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
    }

    private func updateLayerShapeIfNeeded() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let signature = ShapeSignature(
            viewportRect: viewportRect,
            cornerRadii: cornerRadii.clamped(to: viewportRect.size),
            scale: scale
        )
        guard appliedShape != signature else { return }
        appliedShape = signature

        let pathBounds = CGRect(origin: .zero, size: signature.viewportRect.size)
        let path = BrowserContentViewportShape.path(
            in: pathBounds,
            cornerRadii: signature.cornerRadii
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        shadowSurfaceLayer.contentsScale = scale
        shadowSurfaceLayer.frame = signature.viewportRect
        shadowSurfaceLayer.path = path
        shadowSurfaceLayer.shadowPath = path
        CATransaction.commit()
    }
}

@MainActor
final class BrowserContentViewportClipView: NSView {
    private var style: BrowserContentSurfaceStyle
    private var hitPath: CGPath?
    private var hitPathBounds: CGRect = .null
    private var hitPathCornerRadii: ChromeCornerRadii = .uniform(0)

    init(style: BrowserContentSurfaceStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        autoresizingMask = []
        applyLayerStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        updateHitPathIfNeeded()
        guard hitPath?.contains(point) == true else {
            return nil
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        updateHitPathIfNeeded()
    }

    func apply(style: BrowserContentSurfaceStyle) {
        guard self.style != style else { return }
        self.style = style
        applyLayerStyle()
        hitPath = nil
    }

    private func applyLayerStyle() {
        guard let layer else { return }
        let radii = style.geometry.contentCornerRadii

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = style.backgroundColor.cgColor
        layer.cornerRadius = radii.maxRadius
        layer.maskedCorners = radii.caCornerMask
        layer.cornerCurve = .continuous
        CATransaction.commit()
    }

    private func updateHitPathIfNeeded() {
        let radii = style.geometry.contentCornerRadii.clamped(to: bounds.size)
        guard hitPath == nil
            || hitPathBounds != bounds
            || hitPathCornerRadii != radii
        else { return }

        hitPathBounds = bounds
        hitPathCornerRadii = radii
        hitPath = BrowserContentViewportShape.path(
            in: bounds,
            cornerRadii: radii
        )
    }
}
