import AppKit

@MainActor
class MouseOverButton: NSButton {
    private enum Animation {
        static let duration: TimeInterval = 0.15
    }

    @IBInspectable var backgroundColor: NSColor? {
        didSet { updateHoverLayer(animated: false) }
    }
    @IBInspectable var mouseOverColor: NSColor? {
        didSet { updateHoverLayer(animated: false) }
    }
    @IBInspectable var mouseDownColor: NSColor? {
        didSet { updateHoverLayer(animated: false) }
    }
    @IBInspectable var cornerRadius: CGFloat = 0 {
        didSet { updateHoverLayer(animated: false) }
    }
    @IBInspectable var mustAnimateOnMouseOver = false

    @IBInspectable var mouseOverTintColor: NSColor? {
        didSet { updateTintColor() }
    }
    @IBInspectable var mouseDownTintColor: NSColor? {
        didSet { updateTintColor() }
    }
    var normalTintColor: NSColor? {
        didSet { updateTintColor() }
    }

    private var hoverBackgroundLayer: CALayer?
    private var hoverTrackingArea: NSTrackingArea?
    private var didCaptureNormalTintColorAfterNibLoad = false
    private var eventTypeMask: NSEvent.EventTypeMask = .leftMouseUp

    private(set) var isMouseOver = false {
        didSet {
            guard isMouseOver != oldValue else { return }
            updateTintColor()
            updateHoverLayer(animated: !isMouseOver || mustAnimateOnMouseOver)
        }
    }

    var isMouseDown = false {
        didSet {
            guard isMouseDown != oldValue else { return }
            updateTintColor()
            updateHoverLayer(animated: !isMouseDown)
        }
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            updateHoverLayer(animated: false)
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    func configureAfterNibLoadIfNeeded() {
        guard !didCaptureNormalTintColorAfterNibLoad else { return }
        didCaptureNormalTintColorAfterNibLoad = true
        normalTintColor = contentTintColor
    }

    @discardableResult
    override func sendAction(on mask: NSEvent.EventTypeMask) -> Int {
        eventTypeMask = mask
        return Int(truncatingIfNeeded: mask.rawValue)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            isMouseOver = false
        }
        isMouseDown = false
        super.viewWillMove(toWindow: newWindow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        hoverTrackingArea = trackingArea
        addTrackingArea(trackingArea)
        isMouseOver = isMouseLocationInsideVisibleBounds
        updateHoverLayer(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseOver = true
    }

    override func mouseMoved(with event: NSEvent) {
        if !isMouseOver {
            isMouseOver = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseOver = false
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
        super.mouseDown(with: event)
        isMouseDown = false
        isMouseOver = isMouseLocationInsideVisibleBounds
    }

    override func otherMouseDown(with event: NSEvent) {
        guard eventTypeMask.contains(.init(type: event.type)), let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard eventTypeMask.contains(.init(type: event.type)), let action else { return }
        NSApp.sendAction(action, to: target, from: self)
    }

    override func updateLayer() {
        super.updateLayer()
        updateHoverLayer(animated: false)
    }

    func updateTintColor() {
        NSAppearance.sumi_chromeWithAppAppearance {
            contentTintColor = currentTintColor
        }
    }

    private var currentTintColor: NSColor? {
        if isMouseDown {
            return mouseDownTintColor ?? normalTintColor
        }
        if isMouseOver {
            return mouseOverTintColor ?? normalTintColor
        }
        return normalTintColor
    }

    private var currentBackgroundColor: NSColor? {
        guard isEnabled else { return nil }
        if isMouseDown {
            return mouseDownColor ?? mouseOverColor ?? backgroundColor
        }
        if isMouseOver {
            return mouseOverColor ?? backgroundColor
        }
        return backgroundColor
    }

    private var isMouseLocationInsideVisibleBounds: Bool {
        guard let window else { return false }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.intersection(visibleRect).contains(location)
    }

    private func updateHoverLayer(animated: Bool) {
        let color = currentBackgroundColor ?? .clear
        guard let backgroundLayer = backgroundLayer(createIfNeeded: color != .clear) else { return }

        backgroundLayer.cornerRadius = cornerRadius
        backgroundLayer.frame = bounds

        NSAppearance.sumi_chromeWithAppAppearance {
            NSAnimationContext.runAnimationGroup { context in
                context.allowsImplicitAnimation = true
                if !animated || isMouseDown || isMouseOver && !mustAnimateOnMouseOver {
                    backgroundLayer.removeAllAnimations()
                    context.duration = 0
                } else {
                    context.duration = Animation.duration
                }
                backgroundLayer.backgroundColor = color.cgColor
            }
        }
    }

    private func backgroundLayer(createIfNeeded: Bool) -> CALayer? {
        guard hoverBackgroundLayer == nil, createIfNeeded else {
            return hoverBackgroundLayer
        }

        wantsLayer = true
        guard let layer else { return nil }
        let backgroundLayer = CALayer()
        backgroundLayer.masksToBounds = true
        layer.insertSublayer(backgroundLayer, at: 0)
        hoverBackgroundLayer = backgroundLayer
        return backgroundLayer
    }
}
