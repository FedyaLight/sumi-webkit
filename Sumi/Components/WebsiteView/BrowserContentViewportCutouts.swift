import AppKit
import SwiftUI

enum BrowserContentViewportCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

struct BrowserContentViewportCutoutBackground: Equatable {
    var baseColor: NSColor
    var sourceGradient: SpaceGradient?
    var targetGradient: SpaceGradient?
    var transitionProgress: Double
    var usesTransitionLayers: Bool

    static func == (
        lhs: BrowserContentViewportCutoutBackground,
        rhs: BrowserContentViewportCutoutBackground
    ) -> Bool {
        lhs.baseColor.sumiSRGBA.isApproximatelyEqual(to: rhs.baseColor.sumiSRGBA)
            && lhs.sourceGradient == rhs.sourceGradient
            && lhs.targetGradient == rhs.targetGradient
            && abs(lhs.transitionProgress - rhs.transitionProgress) <= 0.000_1
            && lhs.usesTransitionLayers == rhs.usesTransitionLayers
    }

    static func solid(_ color: NSColor) -> Self {
        BrowserContentViewportCutoutBackground(
            baseColor: color,
            sourceGradient: nil,
            targetGradient: nil,
            transitionProgress: 1,
            usesTransitionLayers: false
        )
    }

    func draw(in view: NSView) {
        drawSampledChromeBackground(in: view)
    }

    private func drawSampledChromeBackground(in view: NSView) {
        let referenceView = view.window?.contentView ?? view.superview ?? view
        let referenceBounds = referenceView.bounds
        let originInReference = view.convert(NSPoint.zero, to: referenceView)
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelLength = 1 / max(scale, 1)
        let pixelWidth = max(1, Int(ceil(view.bounds.width * scale)))
        let pixelHeight = max(1, Int(ceil(view.bounds.height * scale)))
        let sampler = BrowserContentViewportCutoutBackgroundSampler(
            background: self,
            referenceBounds: referenceBounds
        )

        for yIndex in 0..<pixelHeight {
            let sampleY = min(view.bounds.height, (CGFloat(yIndex) + 0.5) * pixelLength)
            let rectY = CGFloat(yIndex) * pixelLength

            for xIndex in 0..<pixelWidth {
                let sampleX = min(view.bounds.width, (CGFloat(xIndex) + 0.5) * pixelLength)
                let rectX = CGFloat(xIndex) * pixelLength
                let referencePoint = NSPoint(
                    x: originInReference.x + sampleX,
                    y: originInReference.y + sampleY
                )
                sampler.sampledColor(
                    at: referencePoint
                ).setFill()
                NSRect(
                    x: rectX,
                    y: rectY,
                    width: pixelLength,
                    height: pixelLength
                ).fill()
            }
        }
    }

}

private struct BrowserContentViewportCutoutBackgroundSampler {
    let baseColor: SumiRGBA
    let sourceGradient: PreparedSpaceGradient?
    let targetGradient: PreparedSpaceGradient?
    let transitionProgress: CGFloat
    let usesTransitionLayers: Bool
    let referenceBounds: NSRect

    init(
        background: BrowserContentViewportCutoutBackground,
        referenceBounds: NSRect
    ) {
        baseColor = background.baseColor.sumiSRGBA
        sourceGradient = PreparedSpaceGradient(background.sourceGradient)
        targetGradient = PreparedSpaceGradient(background.targetGradient)
        transitionProgress = CGFloat(min(max(background.transitionProgress, 0), 1))
        usesTransitionLayers = background.usesTransitionLayers
        self.referenceBounds = referenceBounds
    }

    func sampledColor(at point: NSPoint) -> NSColor {
        let base = baseColor
        var result = SumiRGBA(red: base.red, green: base.green, blue: base.blue, alpha: 1)

        let uv = normalizedSwiftUIUnitPoint(for: point, in: referenceBounds)
        if usesTransitionLayers {
            result = composite(
                sampleGradient(sourceGradient, at: uv),
                opacity: 1 - transitionProgress,
                over: result
            )
            result = composite(
                sampleGradient(targetGradient, at: uv),
                opacity: transitionProgress,
                over: result
            )
        } else {
            result = composite(
                sampleGradient(targetGradient ?? sourceGradient, at: uv),
                opacity: 1,
                over: result
            )
        }

        return NSColor(
            srgbRed: result.red,
            green: result.green,
            blue: result.blue,
            alpha: result.alpha
        )
    }

    func normalizedSwiftUIUnitPoint(
        for point: NSPoint,
        in referenceBounds: NSRect
    ) -> CGPoint {
        guard referenceBounds.width > 0, referenceBounds.height > 0 else {
            return CGPoint(x: 0, y: 0)
        }

        let x = (point.x - referenceBounds.minX) / referenceBounds.width
        // NSHostingView exposes the same top-to-bottom unit space that SwiftUI gradients render in here.
        let y = (point.y - referenceBounds.minY) / referenceBounds.height
        return CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }

    private func sampleGradient(
        _ gradient: PreparedSpaceGradient?,
        at uv: CGPoint
    ) -> (color: SumiRGBA, opacity: CGFloat)? {
        guard let gradient else { return nil }
        let nodes = gradient.nodes

        let color: SumiRGBA
        if nodes.count == 1 {
            color = nodes[0].color
        } else if nodes.count == 2 {
            color = sampleLinearGradient(nodes: nodes, angle: gradient.angle, at: uv)
        } else {
            color = sampleBarycentricGradient(nodes: nodes, at: uv)
        }

        return (color, gradient.opacity)
    }

    private func sampleLinearGradient(
        nodes: [PreparedGradientNode],
        angle: CGFloat,
        at uv: CGPoint
    ) -> SumiRGBA {
        let theta = angle * .pi / 180
        let dx = cos(theta)
        let dy = sin(theta)
        let start = CGPoint(x: 0.5 - 0.5 * dx, y: 0.5 - 0.5 * dy)
        let end = CGPoint(x: 0.5 + 0.5 * dx, y: 0.5 + 0.5 * dy)
        let lineX = end.x - start.x
        let lineY = end.y - start.y
        let denominator = max(lineX * lineX + lineY * lineY, 0.000_001)
        let projected = ((uv.x - start.x) * lineX + (uv.y - start.y) * lineY) / denominator
        let location = min(max(projected, 0), 1)
        return sampleStops(nodes: nodes, at: location)
    }

    private func sampleStops(nodes: [PreparedGradientNode], at location: CGFloat) -> SumiRGBA {
        guard let first = nodes.first else { return .clear }
        guard nodes.count > 1 else { return first.color }

        if location <= first.location {
            return first.color
        }

        for index in 1..<nodes.count {
            let previous = nodes[index - 1]
            let current = nodes[index]
            let previousLocation = previous.location
            let currentLocation = current.location
            guard location <= currentLocation else { continue }

            let span = max(currentLocation - previousLocation, 0.000_001)
            let amount = (location - previousLocation) / span
            return previous.color.mixed(
                with: current.color,
                amount: amount
            )
        }

        return nodes[nodes.count - 1].color
    }

    private func sampleBarycentricGradient(
        nodes: [PreparedGradientNode],
        at uv: CGPoint
    ) -> SumiRGBA {
        let pA = CGPoint(x: 0.08, y: 0.08)
        let pB = CGPoint(x: 0.92, y: 0.08)
        let pC = CGPoint(x: 0.5, y: 0.92)
        let v0 = CGPoint(x: pB.x - pA.x, y: pB.y - pA.y)
        let v1 = CGPoint(x: pC.x - pA.x, y: pC.y - pA.y)
        let v2 = CGPoint(x: uv.x - pA.x, y: uv.y - pA.y)

        let d00 = v0.x * v0.x + v0.y * v0.y
        let d01 = v0.x * v1.x + v0.y * v1.y
        let d11 = v1.x * v1.x + v1.y * v1.y
        let d20 = v2.x * v0.x + v2.y * v0.y
        let d21 = v2.x * v1.x + v2.y * v1.y
        let denominator = max(d00 * d11 - d01 * d01, 0.000_001)
        var v = (d11 * d20 - d01 * d21) / denominator
        var w = (d00 * d21 - d01 * d20) / denominator
        var u = 1 - v - w

        u = max(0, u)
        v = max(0, v)
        w = max(0, w)
        let sum = max(u + v + w, 0.000_001)
        u /= sum
        v /= sum
        w /= sum

        return nodes[0].color
            .scaled(by: u)
            .adding(nodes[1].color.scaled(by: v))
            .adding(nodes[2].color.scaled(by: w))
    }

    private func composite(
        _ sample: (color: SumiRGBA, opacity: CGFloat)?,
        opacity: CGFloat,
        over base: SumiRGBA
    ) -> SumiRGBA {
        guard let sample else { return base }
        let alpha = min(max(sample.opacity * opacity, 0), 1)
        return sample.color.composited(alpha: alpha, over: base)
    }

}

private struct PreparedSpaceGradient {
    let angle: CGFloat
    let opacity: CGFloat
    let nodes: [PreparedGradientNode]

    init?(_ gradient: SpaceGradient?) {
        guard let gradient else { return nil }
        let preparedNodes = gradient.sortedNodes.prefix(3).map(PreparedGradientNode.init)
        guard preparedNodes.isEmpty == false else { return nil }

        angle = CGFloat(gradient.angle)
        opacity = CGFloat(min(max(gradient.opacity, 0), 1))
        nodes = preparedNodes
    }
}

private struct PreparedGradientNode {
    let color: SumiRGBA
    let location: CGFloat

    init(_ node: GradientNode) {
        color = (NSColor(Color(hex: node.colorHex)).usingColorSpace(.sRGB) ?? .clear).sumiSRGBA
        location = CGFloat(node.location)
    }
}

private struct SumiRGBA {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    static let clear = SumiRGBA(red: 0, green: 0, blue: 0, alpha: 0)

    func isApproximatelyEqual(to other: SumiRGBA) -> Bool {
        abs(red - other.red) <= 0.000_1
            && abs(green - other.green) <= 0.000_1
            && abs(blue - other.blue) <= 0.000_1
            && abs(alpha - other.alpha) <= 0.000_1
    }

    func mixed(with other: SumiRGBA, amount: CGFloat) -> SumiRGBA {
        let ratio = min(max(amount, 0), 1)
        return SumiRGBA(
            red: red * (1 - ratio) + other.red * ratio,
            green: green * (1 - ratio) + other.green * ratio,
            blue: blue * (1 - ratio) + other.blue * ratio,
            alpha: alpha * (1 - ratio) + other.alpha * ratio
        )
    }

    func scaled(by amount: CGFloat) -> SumiRGBA {
        SumiRGBA(
            red: red * amount,
            green: green * amount,
            blue: blue * amount,
            alpha: alpha * amount
        )
    }

    func adding(_ other: SumiRGBA) -> SumiRGBA {
        SumiRGBA(
            red: red + other.red,
            green: green + other.green,
            blue: blue + other.blue,
            alpha: alpha + other.alpha
        )
    }

    func composited(alpha: CGFloat, over base: SumiRGBA) -> SumiRGBA {
        let sourceAlpha = min(max(alpha, 0), 1)
        let inverseAlpha = 1 - sourceAlpha
        return SumiRGBA(
            red: red * sourceAlpha + base.red * inverseAlpha,
            green: green * sourceAlpha + base.green * inverseAlpha,
            blue: blue * sourceAlpha + base.blue * inverseAlpha,
            alpha: sourceAlpha + base.alpha * inverseAlpha
        )
    }
}

private extension NSColor {
    var sumiSRGBA: SumiRGBA {
        let converted = usingColorSpace(.sRGB) ?? .clear
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        converted.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return SumiRGBA(red: red, green: green, blue: blue, alpha: alpha)
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

    var viewportRect: NSRect = .zero {
        didSet {
            updateLayerShape()
        }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            updateLayerShape()
        }
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
        shadowSurfaceLayer.fillColor = NSColor.black.cgColor
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

@MainActor
final class BrowserContentCornerCutoutView: NSView {
    let corner: BrowserContentViewportCorner

    var cornerRadius: CGFloat = 0 {
        didSet {
            guard abs(cornerRadius - oldValue) > 0.000_1 else { return }
            needsDisplay = true
        }
    }

    var cutoutBackground: BrowserContentViewportCutoutBackground = .solid(.clear) {
        didSet {
            guard cutoutBackground != oldValue else { return }
            needsDisplay = true
        }
    }

    init(corner: BrowserContentViewportCorner) {
        self.corner = corner
        super.init(frame: .zero)
        autoresizingMask = []
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let radius = max(0, cornerRadius)
        guard radius > 0,
              bounds.width > 0,
              bounds.height > 0
        else { return }

        let cutoutPath = NSBezierPath(rect: bounds)
        cutoutPath.append(NSBezierPath(ovalIn: ovalRect(radius: radius)))
        cutoutPath.windingRule = .evenOdd

        NSGraphicsContext.saveGraphicsState()
        cutoutPath.addClip()
        cutoutBackground.draw(in: self)
        NSGraphicsContext.restoreGraphicsState()

        drawViewportShadow(in: cutoutPath, radius: radius)
    }

    private func drawViewportShadow(
        in cutoutPath: NSBezierPath,
        radius: CGFloat
    ) {
        let oval = ovalRect(radius: radius)
        let center = NSPoint(x: oval.midX, y: oval.midY)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelLength = 1 / max(scale, 1)
        let pixelWidth = max(1, Int(ceil(bounds.width * scale)))
        let pixelHeight = max(1, Int(ceil(bounds.height * scale)))
        let blurRadius = max(
            BrowserContentViewportVisuals.shadowRadius
                * BrowserContentViewportVisuals.cornerCutoutShadowRadiusMultiplier,
            pixelLength
        )
        let shadowOpacity = CGFloat(BrowserContentViewportVisuals.shadowOpacity)
            * BrowserContentViewportVisuals.cornerCutoutShadowOpacityMultiplier

        NSGraphicsContext.saveGraphicsState()
        cutoutPath.addClip()

        for yIndex in 0..<pixelHeight {
            let sampleY = min(bounds.height, (CGFloat(yIndex) + 0.5) * pixelLength)
            let rectY = CGFloat(yIndex) * pixelLength

            for xIndex in 0..<pixelWidth {
                let sampleX = min(bounds.width, (CGFloat(xIndex) + 0.5) * pixelLength)
                let rectX = CGFloat(xIndex) * pixelLength
                let distance = hypot(sampleX - center.x, sampleY - center.y) - radius
                guard distance >= 0 else { continue }

                let falloff = max(0, 1 - distance / blurRadius)
                let alpha = shadowOpacity * falloff * falloff
                guard alpha > 0.001 else { continue }

                NSColor.black.withAlphaComponent(alpha).setFill()
                NSRect(
                    x: rectX,
                    y: rectY,
                    width: pixelLength,
                    height: pixelLength
                ).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func ovalRect(radius: CGFloat) -> NSRect {
        switch corner {
        case .topLeft:
            NSRect(
                x: bounds.maxX - radius,
                y: bounds.minY - radius,
                width: radius * 2,
                height: radius * 2
            )
        case .topRight:
            NSRect(
                x: bounds.minX - radius,
                y: bounds.minY - radius,
                width: radius * 2,
                height: radius * 2
            )
        case .bottomLeft:
            NSRect(
                x: bounds.maxX - radius,
                y: bounds.maxY - radius,
                width: radius * 2,
                height: radius * 2
            )
        case .bottomRight:
            NSRect(
                x: bounds.minX - radius,
                y: bounds.maxY - radius,
                width: radius * 2,
                height: radius * 2
            )
        }
    }
}
