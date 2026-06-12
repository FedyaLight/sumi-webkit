import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"

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

    static func sidebarReservedWidth(isVisible: Bool) -> CGFloat {
        isVisible ? sidebarReservedWidth : 0
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

    func resolvedTargetWindow(preferred preferredWindow: NSWindow? = nil) -> NSWindow? {
        preferredWindow ?? targetWindow
    }

    func isEnabled(
        _ action: BrowserWindowTrafficLightAction,
        preferred preferredWindow: NSWindow? = nil
    ) -> Bool {
        guard let targetWindow = resolvedTargetWindow(preferred: preferredWindow) else { return false }

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

    func accessibilityLabel(
        for action: BrowserWindowTrafficLightAction,
        preferred preferredWindow: NSWindow? = nil
    ) -> String {
        let targetWindow = resolvedTargetWindow(preferred: preferredWindow)
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
            width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(isVisible: isVisible),
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .offset(x: BrowserWindowTrafficLightMetrics.clusterHorizontalOffset)
        .opacity(isVisible ? 1 : 0)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(!isVisible)
    }
}

@MainActor
private struct BrowserWindowStandardTrafficLightCluster: NSViewRepresentable {
    var actionProvider: BrowserWindowTrafficLightActionProvider
    var isVisible: Bool

    func makeNSView(context: Context) -> BrowserWindowStandardTrafficLightClusterView {
        let view = BrowserWindowStandardTrafficLightClusterView()
        view.configure()
        view.update(actionProvider: actionProvider, isVisible: isVisible)
        return view
    }

    func updateNSView(_ nsView: BrowserWindowStandardTrafficLightClusterView, context: Context) {
        nsView.update(actionProvider: actionProvider, isVisible: isVisible)
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowStandardTrafficLightClusterView,
        coordinator: Void
    ) {
        nsView.clearWindowActionTargets()
    }
}

@MainActor
private final class BrowserWindowStandardTrafficLightClusterView: NSView {
    private var buttonsByAction: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private let glyphOverlayView = BrowserWindowTrafficLightRolloverGlyphOverlayView()
    private var actionProvider: BrowserWindowTrafficLightActionProvider?
    private var rolloverTrackingArea: NSTrackingArea?
    private var pressEventMonitor: Any?
    private var isRolloverHighlighted = false
    private var pressedAction: BrowserWindowTrafficLightAction? {
        didSet {
            guard pressedAction != oldValue else { return }
            updateGlyphOverlayState()
        }
    }
    private var isClusterVisible = false

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    init() {
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        removePressEventMonitor()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshRolloverTrackingArea()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateButtonStates()
        syncPressEventMonitor()
        refreshRolloverTrackingArea()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isClusterVisible,
              isHidden == false,
              alphaValue > 0
        else { return nil }

        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    func configure() {
        guard buttonsByAction.isEmpty else {
            updateButtonStates()
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

        updateButtonStates()
    }

    func clearWindowActionTargets() {
        isClusterVisible = false
        pressedAction = nil
        setRolloverHighlighted(false)
        refreshRolloverTrackingArea()
        syncPressEventMonitor()
        updateButtonStates()
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
        let visibilityChanged = isClusterVisible != isVisible
        isClusterVisible = isVisible
        updateButtonStates()
        syncPressEventMonitor()
        if visibilityChanged {
            refreshRolloverTrackingArea()
        } else {
            syncRolloverHighlightWithCurrentMouseLocation()
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        for (index, action) in BrowserWindowTrafficLightAction.allCases.enumerated() {
            guard let button = buttonsByAction[action] else { continue }
            let size = Self.buttonSize(for: button)
            let x = CGFloat(index) * BrowserWindowTrafficLightMetrics.buttonCenterSpacing
            let y = max((bounds.height - size.height) / 2, 0)
            button.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        }
        syncRolloverHighlightWithCurrentMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        setRolloverHighlighted(true)
    }

    override func mouseMoved(with event: NSEvent) {
        setRolloverHighlighted(bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        pressedAction = nil
        setRolloverHighlighted(false)
    }

    private func updateButtonStates() {
        let targetWindow = actionProvider?.resolvedTargetWindow(preferred: window) ?? window

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttonsByAction[action] else { continue }

            button.target = targetWindow
            button.action = action.selector
            button.identifier = NSUserInterfaceItemIdentifier(action.accessibilityIdentifier)
            button.setAccessibilityIdentifier(action.accessibilityIdentifier)
            button.isHidden = !isClusterVisible
            button.alphaValue = isClusterVisible ? 1 : 0
            button.isEnabled = isClusterVisible
                && (actionProvider?.isEnabled(action, preferred: window) ?? false)
            button.isHighlighted = false
            button.setAccessibilityLabel(
                actionProvider?.accessibilityLabel(for: action, preferred: window)
                    ?? action.accessibilityLabel
            )
            button.setAccessibilityElement(isClusterVisible)
            button.setAccessibilityHidden(!isClusterVisible)
        }

        updateGlyphOverlayState()
    }

    private static func buttonSize(for button: NSButton) -> NSSize {
        let currentSize = button.frame.size
        guard currentSize.width > 0, currentSize.height > 0 else {
            return NSSize(
                width: BrowserWindowTrafficLightMetrics.buttonDiameter,
                height: BrowserWindowTrafficLightMetrics.buttonDiameter
            )
        }
        return currentSize
    }

    private func refreshRolloverTrackingArea() {
        if let rolloverTrackingArea {
            removeTrackingArea(rolloverTrackingArea)
            self.rolloverTrackingArea = nil
        }

        guard isClusterVisible, window != nil else {
            setRolloverHighlighted(false)
            return
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        rolloverTrackingArea = trackingArea
        syncRolloverHighlightWithCurrentMouseLocation()
    }

    private func syncPressEventMonitor() {
        if isClusterVisible, window != nil {
            installPressEventMonitorIfNeeded()
        } else {
            pressedAction = nil
            removePressEventMonitor()
        }
    }

    private func installPressEventMonitorIfNeeded() {
        guard pressEventMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        pressEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handlePressEvent(event)
            }
            return event
        }
    }

    private func removePressEventMonitor() {
        guard let pressEventMonitor else { return }
        NSEvent.removeMonitor(pressEventMonitor)
        self.pressEventMonitor = nil
    }

    private func handlePressEvent(_ event: NSEvent) {
        guard event.window === window else {
            if event.type == .leftMouseUp {
                pressedAction = nil
            }
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .leftMouseDown:
            pressedAction = action(at: localPoint)
            setRolloverHighlighted(bounds.contains(localPoint))
        case .leftMouseDragged:
            guard pressedAction != nil else { return }
            setRolloverHighlighted(bounds.contains(localPoint))
        case .leftMouseUp:
            pressedAction = nil
            setRolloverHighlighted(bounds.contains(localPoint))
        default:
            break
        }
    }

    func syncRolloverHighlightWithCurrentMouseLocation() {
        guard isClusterVisible,
              isHidden == false,
              alphaValue > 0,
              let window
        else {
            setRolloverHighlighted(false)
            return
        }

        let localPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setRolloverHighlighted(bounds.contains(localPoint))
    }

    private func setRolloverHighlighted(_ isHighlighted: Bool) {
        isRolloverHighlighted = isHighlighted
        updateGlyphOverlayState()
    }

    private func updateGlyphOverlayState() {
        glyphOverlayView.frame = bounds
        glyphOverlayView.buttonFramesByAction = buttonsByAction.mapValues(\.frame)
        let shouldShowGlyphs = isRolloverHighlighted
            && isClusterVisible
        glyphOverlayView.isClusterHovered = shouldShowGlyphs
        var enabledActions = Set(BrowserWindowTrafficLightAction.allCases.filter { action in
            buttonsByAction[action]?.isEnabled == true
        })
        if let pressedAction {
            enabledActions.remove(pressedAction)
        }
        glyphOverlayView.enabledActions = enabledActions
        glyphOverlayView.isHidden = !shouldShowGlyphs
        glyphOverlayView.needsDisplay = true
    }

    private func action(at point: NSPoint) -> BrowserWindowTrafficLightAction? {
        for action in BrowserWindowTrafficLightAction.allCases {
            guard buttonsByAction[action]?.frame.contains(point) == true else { continue }
            return action
        }
        return nil
    }
}

@MainActor
private final class BrowserWindowTrafficLightRolloverGlyphOverlayView: NSView {
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

private extension BrowserWindowTrafficLightAction {
    var selector: Selector {
        switch self {
        case .close:
            return #selector(NSWindow.performCloseFromBrowserChrome(_:))
        case .minimize:
            return #selector(NSWindow.miniaturize(_:))
        case .zoom:
            return #selector(NSWindow.toggleFullScreen(_:))
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
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth(isVisible: isVisible),
                height: BrowserWindowTrafficLightMetrics.clusterHeight
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
