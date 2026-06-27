import AppKit
import QuartzCore

@MainActor
final class GlanceOverlayActionChrome: NSObject {
    enum Action {
        case close
        case open
        case split
    }

    private let stackView = GlanceActionButtonStack(
        buttonSize: GlanceOverlayLayout.Metrics.actionButtonSize,
        spacing: GlanceOverlayLayout.Metrics.actionButtonSpacing,
        hitOutset: GlanceOverlayLayout.Metrics.actionButtonHitOutset
    )
    private let closeButton = GlanceActionButton(symbolName: "xmark", toolTip: "Close Glance")
    private let openButton = GlanceActionButton(symbolName: "arrow.up.left.and.arrow.down.right", toolTip: "Open in Tab")
    private let splitButton = GlanceActionButton(symbolName: "square.split.2x1", toolTip: "Open in Split View")
    private let actionHandler: (Action) -> Void

    init(actionHandler: @escaping (Action) -> Void) {
        self.actionHandler = actionHandler
        super.init()
        configureButtons()
    }

    var isHidden: Bool {
        get { stackView.isHidden }
        set { stackView.isHidden = newValue }
    }

    var alphaValue: CGFloat {
        get { stackView.alphaValue }
        set { stackView.alphaValue = newValue }
    }

    var frame: CGRect {
        get { stackView.frame }
        set { stackView.frame = newValue }
    }

    var closeRequiresSecondPress: Bool {
        get { closeButton.requiresSecondPress }
        set { closeButton.requiresSecondPress = newValue }
    }

    var isSplitEnabled: Bool {
        get { splitButton.isEnabled }
        set { splitButton.isEnabled = newValue }
    }

    func install(in view: NSView) {
        if stackView.superview == nil {
            view.addSubview(stackView)
        }
    }

    func removeFromSuperview() {
        stackView.removeFromSuperview()
    }

    func apply(accentColor: NSColor) {
        [closeButton, openButton, splitButton].forEach {
            $0.apply(accentColor: accentColor)
        }
    }

    func setButtonsEnabled(_ isEnabled: Bool) {
        [closeButton, openButton, splitButton].forEach {
            $0.isEnabled = isEnabled
        }
    }

    func layout(
        for contentFrame: CGRect,
        in rootBounds: CGRect,
        sidebarPosition: SidebarPosition,
        using layout: GlanceOverlayLayout
    ) -> CGRect {
        stackView.frame = layout.actionChromeFrame(
            for: contentFrame,
            in: rootBounds,
            buttonCount: stackView.arrangedSubviews.count,
            sidebarPosition: sidebarPosition
        )
        stackView.needsLayout = true
        stackView.layoutSubtreeIfNeeded()
        return stackView.frame.insetBy(
            dx: -GlanceOverlayLayout.Metrics.actionButtonHitOutset,
            dy: -GlanceOverlayLayout.Metrics.actionButtonHitOutset
        )
    }

    func setAnimatedFrame(_ frame: CGRect) {
        stackView.animator().frame = frame
    }

    func setAnimatedAlphaValue(_ alphaValue: CGFloat) {
        stackView.animator().alphaValue = alphaValue
    }

    func handleMouseDown(at rootPoint: CGPoint, from rootView: NSView?) -> Bool {
        guard stackView.superview != nil,
              !stackView.isHidden
        else { return false }

        let localPoint = stackView.convert(rootPoint, from: rootView)
        let stackHitFrame = stackView.bounds.insetBy(
            dx: -GlanceOverlayLayout.Metrics.actionButtonHitOutset,
            dy: -GlanceOverlayLayout.Metrics.actionButtonHitOutset
        )
        guard stackHitFrame.contains(localPoint) else { return false }

        if handleButtonHit(splitButton, at: localPoint, action: .split) {
            return true
        }
        if handleButtonHit(openButton, at: localPoint, action: .open) {
            return true
        }
        if handleButtonHit(closeButton, at: localPoint, action: .close) {
            return true
        }

        return true
    }

    private func configureButtons() {
        [closeButton, openButton, splitButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = true
            stackView.addArrangedSubview($0)
        }

        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        openButton.target = self
        openButton.action = #selector(openButtonPressed)
        splitButton.target = self
        splitButton.action = #selector(splitButtonPressed)
    }

    private func handleButtonHit(
        _ button: GlanceActionButton,
        at localPoint: CGPoint,
        action: Action
    ) -> Bool {
        let expandedFrame = button.frame.insetBy(
            dx: -GlanceOverlayLayout.Metrics.actionButtonHitOutset,
            dy: -GlanceOverlayLayout.Metrics.actionButtonHitOutset
        )
        guard expandedFrame.contains(localPoint) else { return false }
        guard button.isEnabled else { return true }

        actionHandler(action)
        return true
    }

    @objc private func closeButtonPressed() {
        actionHandler(.close)
    }

    @objc private func openButtonPressed() {
        actionHandler(.open)
    }

    @objc private func splitButtonPressed() {
        actionHandler(.split)
    }
}

private final class GlanceActionButtonStack: NSView {
    let spacing: CGFloat
    private let buttonSize: CGFloat
    private let hitOutset: CGFloat
    private(set) var arrangedSubviews: [NSView] = []

    init(buttonSize: CGFloat, spacing: CGFloat, hitOutset: CGFloat) {
        self.buttonSize = buttonSize
        self.spacing = spacing
        self.hitOutset = hitOutset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addArrangedSubview(_ view: NSView) {
        arrangedSubviews.append(view)
        addSubview(view)
    }

    override func layout() {
        super.layout()

        let x = ((bounds.width - buttonSize) / 2).rounded(.toNearestOrAwayFromZero)
        var y = bounds.maxY - buttonSize
        for view in arrangedSubviews {
            view.frame = CGRect(
                x: x,
                y: y.rounded(.toNearestOrAwayFromZero),
                width: buttonSize,
                height: buttonSize
            )
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            y -= buttonSize + spacing
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else { return nil }
        for subview in subviews.reversed() {
            let convertedPoint = subview.convert(point, from: self)
            if let hitView = subview.hitTest(convertedPoint) {
                return hitView
            }
            let expandedFrame = subview.frame.insetBy(
                dx: -hitOutset,
                dy: -hitOutset
            )
            if expandedFrame.contains(point) {
                return subview
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func resetCursorRects() {}
}

private final class GlanceActionButton: NSButton {
    private let symbolName: String
    private var accentColor: NSColor = .controlAccentColor
    private var trackingArea: NSTrackingArea?
    private var currentScale: CGFloat = 1
    private var cursorInvalidationBounds: CGRect = .null
    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            updateAppearance()
            updateScale()
        }
    }
    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            updateScale()
        }
    }
    var requiresSecondPress: Bool = false {
        didSet {
            guard requiresSecondPress != oldValue else { return }
            updateAppearance()
        }
    }

    init(symbolName: String, toolTip: String) {
        self.symbolName = symbolName
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        refusesFirstResponder = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        self.toolTip = toolTip
        setButtonType(.momentaryChange)
        updateImage()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(accentColor: NSColor) {
        guard !self.accentColor.isEqual(accentColor) else { return }
        self.accentColor = accentColor
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        self.trackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        setPointingHandCursorIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        isPressed = false
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setPointingHandCursorIfNeeded()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isEnabled else {
            super.cursorUpdate(with: event)
            return
        }
        setPointingHandCursorIfNeeded()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            super.mouseDown(with: event)
            return
        }
        isPressed = true
        super.mouseDown(with: event)
        isPressed = false
    }

    override var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            updateAppearance()
            window?.invalidateCursorRects(for: self)
            setPointingHandCursorIfNeeded()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEnabled else { return }
        sumi_chromeAddCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateLayer() {
        super.updateLayer()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        let cornerRadius = min(bounds.width, bounds.height) / 2
        if layer?.cornerRadius != cornerRadius {
            layer?.cornerRadius = cornerRadius
        }
        if cursorInvalidationBounds != bounds {
            cursorInvalidationBounds = bounds
            window?.invalidateCursorRects(for: self)
        }
    }

    private func updateImage() {
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(symbolConfiguration)
    }

    private func updateAppearance() {
        let background: NSColor
        let foreground: NSColor
        if !isEnabled {
            background = NSColor.controlBackgroundColor.withAlphaComponent(0.74)
            foreground = .tertiaryLabelColor
        } else if requiresSecondPress {
            background = NSColor.systemRed
            foreground = .white
        } else if isHovered {
            background = NSColor.textColor.withAlphaComponent(0.84)
            foreground = accentColor
        } else {
            background = NSColor.textColor.withAlphaComponent(0.92)
            foreground = accentColor
        }

        layer?.backgroundColor = background.cgColor
        contentTintColor = foreground
    }

    private func updateScale() {
        let scale: CGFloat
        if !isEnabled {
            scale = 1
        } else if isPressed {
            scale = 0.95
        } else if isHovered {
            scale = 1.05
        } else {
            scale = 1
        }

        guard let layer else { return }
        guard currentScale != scale else { return }
        currentScale = scale
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.05)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    private func setPointingHandCursorIfNeeded() {
        guard isEnabled else { return }
        sumi_chromeSetCursorIfMouseInside(.pointingHand)
    }
}
