import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
    static let miniBrowserWindow = "mini-browser-window"

    static func identifier(for buttonType: NSWindow.ButtonType) -> String? {
        switch buttonType {
        case .closeButton:
            return closeButton
        case .miniaturizeButton:
            return minimizeButton
        case .zoomButton:
            return zoomButton
        default:
            return nil
        }
    }
}

enum BrowserWindowTrafficLightMetrics {
    static var buttonDiameter: CGFloat {
        if #available(macOS 26.0, *) {
            return 14
        } else {
            return 12
        }
    }

    static let buttonCenterSpacing: CGFloat = 20
    static var buttonSpacing: CGFloat {
        buttonCenterSpacing - buttonDiameter
    }
    static let clusterHeight: CGFloat = 30
    static let clusterTrailingInset: CGFloat = 14
    static let clusterHorizontalOffset: CGFloat = -1

    static var clusterWidth: CGFloat {
        buttonDiameter * 3 + buttonSpacing * 2
    }

    static var sidebarReservedWidth: CGFloat {
        clusterWidth + clusterTrailingInset
    }
}

enum BrowserWindowTrafficLightAction: CaseIterable, Hashable {
    case close
    case minimize
    case zoom

    var buttonType: NSWindow.ButtonType {
        switch self {
        case .close:
            return .closeButton
        case .minimize:
            return .miniaturizeButton
        case .zoom:
            return .zoomButton
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .close:
            return BrowserWindowControlsAccessibilityIdentifiers.closeButton
        case .minimize:
            return BrowserWindowControlsAccessibilityIdentifiers.minimizeButton
        case .zoom:
            return BrowserWindowControlsAccessibilityIdentifiers.zoomButton
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .close:
            return "Close"
        case .minimize:
            return "Minimize"
        case .zoom:
            return "Enter Full Screen"
        }
    }
}

@MainActor
struct BrowserWindowTrafficLightActionProvider {
    weak var targetWindow: NSWindow?

    init(targetWindow: NSWindow?) {
        self.targetWindow = targetWindow
    }

    static func browserWindow(_ window: NSWindow?) -> BrowserWindowTrafficLightActionProvider {
        BrowserWindowTrafficLightActionProvider(targetWindow: window)
    }

    func isEnabled(_ action: BrowserWindowTrafficLightAction) -> Bool {
        guard let targetWindow else { return false }

        switch action {
        case .close:
            return targetWindow.styleMask.contains(.closable)
        case .minimize:
            return targetWindow.styleMask.contains(.miniaturizable)
                && targetWindow.isMiniaturized == false
        case .zoom:
            return targetWindow.styleMask.contains(.resizable)
        }
    }

    func accessibilityLabel(for action: BrowserWindowTrafficLightAction) -> String {
        guard action == .zoom, targetWindow?.styleMask.contains(.fullScreen) == true else {
            return action.accessibilityLabel
        }
        return "Exit Full Screen"
    }
}

struct BrowserWindowTrafficLights: View {
    var actionProvider: BrowserWindowTrafficLightActionProvider
    var isVisible: Bool = true

    init(
        actionProvider: BrowserWindowTrafficLightActionProvider,
        isVisible: Bool = true
    ) {
        self.actionProvider = actionProvider
        self.isVisible = isVisible
    }

    var body: some View {
        BrowserWindowStandardTrafficLightCluster(
            actionProvider: actionProvider,
            isVisible: isVisible
        )
        .frame(
            width: isVisible ? BrowserWindowTrafficLightMetrics.sidebarReservedWidth : 0,
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .offset(x: BrowserWindowTrafficLightMetrics.clusterHorizontalOffset)
        .opacity(isVisible ? 1 : 0)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private struct BrowserWindowStandardTrafficLightCluster: NSViewRepresentable {
    var actionProvider: BrowserWindowTrafficLightActionProvider
    var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(actionProvider: actionProvider)
    }

    func makeNSView(context: Context) -> BrowserWindowStandardTrafficLightClusterView {
        let view = BrowserWindowStandardTrafficLightClusterView()
        view.configure(target: context.coordinator)
        view.update(actionProvider: actionProvider, isVisible: isVisible)
        return view
    }

    func updateNSView(_ nsView: BrowserWindowStandardTrafficLightClusterView, context: Context) {
        context.coordinator.actionProvider = actionProvider
        nsView.retargetButtons(to: context.coordinator)
        nsView.update(actionProvider: actionProvider, isVisible: isVisible)
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowStandardTrafficLightClusterView,
        coordinator: Coordinator
    ) {
        nsView.clearTargets()
    }

    @MainActor
    final class Coordinator: NSObject {
        var actionProvider: BrowserWindowTrafficLightActionProvider

        init(actionProvider: BrowserWindowTrafficLightActionProvider) {
            self.actionProvider = actionProvider
        }

        @objc func closeWindow(_ sender: NSButton) {
            actionProvider.targetWindow?.performClose(sender)
        }

        @objc func minimizeWindow(_ sender: NSButton) {
            actionProvider.targetWindow?.miniaturize(sender)
        }

        @objc func zoomWindow(_ sender: NSButton) {
            actionProvider.targetWindow?.toggleFullScreen(sender)
        }
    }
}

@MainActor
private final class BrowserWindowStandardTrafficLightClusterView: NSView {
    private var buttonsByAction: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private let glyphOverlayView = BrowserWindowTrafficLightGlyphOverlayView()
    private var trackingArea: NSTrackingArea?
    private var actionProvider: BrowserWindowTrafficLightActionProvider?
    private var pressedAction: BrowserWindowTrafficLightAction? {
        didSet {
            guard pressedAction != oldValue else { return }
            updateHoverGlyphRendering()
        }
    }
    private var isClusterHovered = false {
        didSet {
            guard isClusterHovered != oldValue else { return }
            updateHoverGlyphRendering()
        }
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        updateHoverStateFromCurrentMouseLocation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateHoverStateFromCurrentMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        isClusterHovered = true
    }

    override func mouseMoved(with event: NSEvent) {
        isClusterHovered = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        isClusterHovered = false
        pressedAction = nil
    }

    override func mouseDown(with event: NSEvent) {
        pressedAction = action(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        pressedAction = nil
    }

    func configure(target: BrowserWindowStandardTrafficLightCluster.Coordinator) {
        guard buttonsByAction.isEmpty else {
            retargetButtons(to: target)
            return
        }

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = NSWindow.standardWindowButton(
                action.buttonType,
                for: SumiBrowserChromeConfiguration.requiredStyleMask
            ) else { continue }

            button.identifier = NSUserInterfaceItemIdentifier(action.accessibilityIdentifier)
            button.setAccessibilityIdentifier(action.accessibilityIdentifier)
            button.setAccessibilityLabel(action.accessibilityLabel)
            button.translatesAutoresizingMaskIntoConstraints = true
            button.autoresizingMask = []
            addSubview(button)
            buttonsByAction[action] = button
        }

        glyphOverlayView.translatesAutoresizingMaskIntoConstraints = true
        glyphOverlayView.autoresizingMask = [.width, .height]
        glyphOverlayView.setAccessibilityElement(false)
        addSubview(glyphOverlayView)

        retargetButtons(to: target)
    }

    func clearTargets() {
        setButtonsVisible(false)
        for button in buttonsByAction.values {
            button.target = nil
            button.action = nil
        }
    }

    func update(actionProvider: BrowserWindowTrafficLightActionProvider, isVisible: Bool) {
        self.actionProvider = actionProvider
        isHidden = !isVisible
        alphaValue = isVisible ? 1 : 0
        setAccessibilityElement(isVisible)

        setButtonsVisible(isVisible)
        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttonsByAction[action] else { continue }
            let isEnabled = isVisible && actionProvider.isEnabled(action)
            button.isEnabled = isEnabled
            button.setAccessibilityLabel(actionProvider.accessibilityLabel(for: action))
        }
        updateHoverGlyphRendering()

        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            guard let button = buttonsByAction[action] else { continue }
            let fallbackSize = NSSize(
                width: BrowserWindowTrafficLightMetrics.buttonDiameter,
                height: BrowserWindowTrafficLightMetrics.buttonDiameter
            )
            let size = button.frame.size == .zero ? fallbackSize : button.frame.size
            let x = CGFloat(index) * BrowserWindowTrafficLightMetrics.buttonCenterSpacing
            let y = max((bounds.height - size.height) / 2, 0)
            button.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        }
        glyphOverlayView.frame = bounds
        glyphOverlayView.buttonFramesByAction = buttonsByAction.mapValues(\.frame)
    }

    func retargetButtons(to target: BrowserWindowStandardTrafficLightCluster.Coordinator) {
        buttonsByAction[.close]?.target = target
        buttonsByAction[.close]?.action = #selector(BrowserWindowStandardTrafficLightCluster.Coordinator.closeWindow(_:))
        buttonsByAction[.minimize]?.target = target
        buttonsByAction[.minimize]?.action = #selector(BrowserWindowStandardTrafficLightCluster.Coordinator.minimizeWindow(_:))
        buttonsByAction[.zoom]?.target = target
        buttonsByAction[.zoom]?.action = #selector(BrowserWindowStandardTrafficLightCluster.Coordinator.zoomWindow(_:))
    }

    private func setButtonsVisible(_ isVisible: Bool) {
        for button in buttonsByAction.values {
            button.isHidden = !isVisible
            button.alphaValue = isVisible ? 1 : 0
            button.isEnabled = isVisible
            button.setAccessibilityElement(isVisible)
        }
        glyphOverlayView.isHidden = !isVisible
        glyphOverlayView.alphaValue = isVisible ? 1 : 0
    }

    private func updateHoverStateFromCurrentMouseLocation() {
        guard let window else {
            isClusterHovered = false
            return
        }

        isClusterHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func updateHoverGlyphRendering() {
        glyphOverlayView.isClusterHovered = isClusterHovered
        updateGlyphOverlayActions()
    }

    private func updateGlyphOverlayActions() {
        guard let actionProvider else {
            glyphOverlayView.enabledActions = []
            return
        }

        var overlayActions = Set(BrowserWindowTrafficLightAction.allCases.filter(actionProvider.isEnabled))
        if let pressedAction {
            overlayActions.remove(pressedAction)
        }
        glyphOverlayView.enabledActions = overlayActions
    }

    private func action(at point: NSPoint) -> BrowserWindowTrafficLightAction? {
        buttonsByAction.first { _, button in
            button.frame.contains(point)
        }?.key
    }
}

@MainActor
private final class BrowserWindowTrafficLightGlyphOverlayView: NSView {
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
        guard isClusterHovered,
              let context = NSGraphicsContext.current?.cgContext
        else { return }

        context.saveGState()
        defer { context.restoreGState() }

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

/// MiniWindow still uses AppKit's native titlebar buttons. This spacer reserves
/// the same leading width as Sumi's browser traffic-light cluster.
struct BrowserWindowNativeTrafficLightSpacer: View {
    var isVisible: Bool = true

    var body: some View {
        Color.clear
            .frame(
                width: isVisible ? BrowserWindowTrafficLightMetrics.sidebarReservedWidth : 0,
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
