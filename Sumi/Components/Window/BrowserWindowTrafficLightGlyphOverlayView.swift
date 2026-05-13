import AppKit

@MainActor
final class BrowserWindowTrafficLightGlyphOverlayView: NSView {
    var isClusterHovered = false {
        didSet {
            guard isClusterHovered != oldValue else { return }
            needsDisplay = true
        }
    }
    var buttonFramesByAction: [BrowserWindowTrafficLightAction: NSRect] = [:] {
        didSet {
            needsDisplay = true
        }
    }
    var enabledActions: Set<BrowserWindowTrafficLightAction> = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.clear(bounds)

        guard isClusterHovered, enabledActions.isEmpty == false else { return }

        for action in BrowserWindowTrafficLightAction.allCases {
            guard enabledActions.contains(action),
                  let frame = buttonFramesByAction[action]
            else { continue }

            drawGlyph(action, in: frame, context: context)
        }
    }

    private func drawGlyph(
        _ action: BrowserWindowTrafficLightAction,
        in frame: NSRect,
        context: CGContext
    ) {
        let rect = frame.insetBy(
            dx: max(0, (frame.width - BrowserWindowTrafficLightMetrics.buttonDiameter) / 2),
            dy: max(0, (frame.height - BrowserWindowTrafficLightMetrics.buttonDiameter) / 2)
        )

        context.setStrokeColor(glyphColor(for: action).cgColor)
        context.setFillColor(glyphColor(for: action).cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch action {
        case .close:
            context.setLineWidth(max(1.1, rect.width * 0.11))
            let inset = rect.width * 0.32
            context.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
            context.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
            context.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
            context.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
            context.strokePath()

        case .minimize:
            context.setLineWidth(max(1.2, rect.width * 0.11))
            let xInset = rect.width * 0.28
            context.move(to: CGPoint(x: rect.minX + xInset, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.maxX - xInset, y: rect.midY))
            context.strokePath()

        case .zoom:
            drawZoomGlyph(in: rect, context: context)
        }
    }

    private func drawZoomGlyph(in rect: NSRect, context: CGContext) {
        let referenceSize: CGFloat = 85.4
        let scale = min(rect.width, rect.height) / referenceSize
        let origin = CGPoint(
            x: rect.midX - referenceSize * scale / 2,
            y: rect.midY - referenceSize * scale / 2
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        context.move(to: point(31.2, 20.8))
        context.addLine(to: point(57.9, 20.8))
        context.addCurve(
            to: point(64.4, 27.3),
            control1: point(61.5, 20.8),
            control2: point(64.4, 23.7)
        )
        context.addLine(to: point(64.4, 54.0))
        context.closePath()
        context.fillPath()

        context.move(to: point(54.4, 64.5))
        context.addLine(to: point(27.6, 64.5))
        context.addCurve(
            to: point(21.1, 58.0),
            control1: point(24.0, 64.5),
            control2: point(21.1, 61.6)
        )
        context.addLine(to: point(21.1, 31.2))
        context.closePath()
        context.fillPath()
    }

    private func glyphColor(for action: BrowserWindowTrafficLightAction) -> NSColor {
        switch action {
        case .close:
            return NSColor(calibratedRed: 0.43, green: 0.03, blue: 0.01, alpha: 0.86)
        case .minimize:
            return NSColor(calibratedRed: 0.50, green: 0.33, blue: 0.00, alpha: 0.86)
        case .zoom:
            return NSColor(calibratedRed: 0.16, green: 0.38, blue: 0.09, alpha: 0.86)
        }
    }
}
