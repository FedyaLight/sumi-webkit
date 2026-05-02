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

enum BrowserWindowTrafficLightPalette {
    static let close = Color(hex: "FF5F57")
    static let closeActive = Color(hex: "FF7B72")
    static let closeGlyph = Color(hex: "6E0802")
    static let minimize = Color(hex: "FFBD2E")
    static let minimizeActive = Color(hex: "FFD15C")
    static let minimizeGlyph = Color(hex: "805300")
    static let zoom = Color(hex: "28C840")
    static let zoomActive = Color(hex: "54D96A")
    static let zoomGlyph = Color(hex: "006400")
    static let inactive = Color(hex: "4E4F52")
}

enum BrowserWindowTrafficLightAction: CaseIterable, Hashable {
    case close
    case minimize
    case zoom

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

    var paletteColor: Color {
        switch self {
        case .close:
            return BrowserWindowTrafficLightPalette.close
        case .minimize:
            return BrowserWindowTrafficLightPalette.minimize
        case .zoom:
            return BrowserWindowTrafficLightPalette.zoom
        }
    }

    var activePaletteColor: Color {
        switch self {
        case .close:
            return BrowserWindowTrafficLightPalette.closeActive
        case .minimize:
            return BrowserWindowTrafficLightPalette.minimizeActive
        case .zoom:
            return BrowserWindowTrafficLightPalette.zoomActive
        }
    }

    var glyphColor: Color {
        switch self {
        case .close:
            return BrowserWindowTrafficLightPalette.closeGlyph
        case .minimize:
            return BrowserWindowTrafficLightPalette.minimizeGlyph
        case .zoom:
            return BrowserWindowTrafficLightPalette.zoomGlyph
        }
    }
}

@MainActor
struct BrowserWindowTrafficLightActionProvider {
    weak var targetWindow: NSWindow?
    var close: @MainActor (NSWindow) -> Void
    var minimize: @MainActor (NSWindow) -> Void
    var zoom: @MainActor (NSWindow) -> Void

    init(
        targetWindow: NSWindow?,
        close: @escaping @MainActor (NSWindow) -> Void = { $0.close() },
        minimize: @escaping @MainActor (NSWindow) -> Void = { $0.miniaturizeFromCustomBrowserChrome() },
        zoom: @escaping @MainActor (NSWindow) -> Void = { $0.toggleFullScreen(nil) }
    ) {
        self.targetWindow = targetWindow
        self.close = close
        self.minimize = minimize
        self.zoom = zoom
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

    func perform(_ action: BrowserWindowTrafficLightAction) {
        guard let targetWindow else { return }

        switch action {
        case .close:
            close(targetWindow)
        case .minimize:
            minimize(targetWindow)
        case .zoom:
            zoom(targetWindow)
        }
    }

    var drawsActivePalette: Bool {
        guard let targetWindow else { return true }
        return targetWindow.isMiniaturized == false
    }
}

struct BrowserWindowTrafficLights: View {
    var actionProvider: BrowserWindowTrafficLightActionProvider
    var isVisible: Bool = true

    @State private var isClusterHovered = false
    @State private var windowActivationRevision: UInt = 0

    init(
        actionProvider: BrowserWindowTrafficLightActionProvider,
        isVisible: Bool = true
    ) {
        self.actionProvider = actionProvider
        self.isVisible = isVisible
    }

    var body: some View {
        let _ = windowActivationRevision

        HStack(spacing: BrowserWindowTrafficLightMetrics.buttonSpacing) {
            ForEach(BrowserWindowTrafficLightAction.allCases, id: \.self) { action in
                trafficLightButton(action)
            }
        }
        .frame(
            width: isVisible ? BrowserWindowTrafficLightMetrics.sidebarReservedWidth : 0,
            height: BrowserWindowTrafficLightMetrics.clusterHeight,
            alignment: .leading
        )
        .offset(x: BrowserWindowTrafficLightMetrics.clusterHorizontalOffset)
        .opacity(isVisible ? 1 : 0)
        .onHover { isClusterHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            handleWindowActivationNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) {
            handleWindowActivationNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeMainNotification)) {
            handleWindowActivationNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignMainNotification)) {
            handleWindowActivationNotification($0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshWindowActivationState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            refreshWindowActivationState()
        }
        .accessibilityElement(children: .contain)
    }

    private func trafficLightButton(_ action: BrowserWindowTrafficLightAction) -> some View {
        BrowserWindowTrafficLightButton(
            action: action,
            actionProvider: actionProvider,
            isClusterHovered: isClusterHovered
        )
    }

    private func handleWindowActivationNotification(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow else {
            return
        }

        guard let targetWindow = actionProvider.targetWindow else {
            refreshWindowActivationState()
            return
        }

        if notificationWindow === targetWindow || notificationWindow.parent === targetWindow {
            refreshWindowActivationState()
        }
    }

    private func refreshWindowActivationState() {
        windowActivationRevision &+= 1
    }
}

@MainActor
private struct BrowserWindowTrafficLightButton: View {
    let action: BrowserWindowTrafficLightAction
    let actionProvider: BrowserWindowTrafficLightActionProvider
    let isClusterHovered: Bool

    @State private var isPressedByAppKitHitTarget = false

    var body: some View {
        let isEnabled = actionProvider.isEnabled(action)

        Button(action: performAction) {
            EmptyView()
        }
        .buttonStyle(
            BrowserWindowTrafficLightButtonStyle(
                action: action,
                isEnabled: isEnabled,
                isClusterHovered: isClusterHovered,
                isPressedByAppKitHitTarget: isPressedByAppKitHitTarget,
                drawsActivePalette: actionProvider.drawsActivePalette
            )
        )
        .disabled(!isEnabled)
        .accessibilityIdentifier(action.accessibilityIdentifier)
        .overlay {
            BrowserWindowTrafficLightActionHitTarget(
                isEnabled: isEnabled,
                onPressedChanged: { isPressedByAppKitHitTarget = $0 },
                action: performAction
            )
            .frame(
                width: BrowserWindowTrafficLightMetrics.buttonDiameter,
                height: BrowserWindowTrafficLightMetrics.buttonDiameter
            )
            .accessibilityHidden(true)
        }
    }

    private func performAction() {
        actionProvider.perform(action)
    }
}

private struct BrowserWindowTrafficLightActionHitTarget: NSViewRepresentable {
    let isEnabled: Bool
    let onPressedChanged: @MainActor (Bool) -> Void
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPressedChanged: onPressedChanged,
            action: action
        )
    }

    func makeNSView(context: Context) -> BrowserWindowTrafficLightActionHitTargetView {
        let view = BrowserWindowTrafficLightActionHitTargetView(frame: .zero)
        view.coordinator = context.coordinator
        view.isActionEnabled = isEnabled
        return view
    }

    func updateNSView(_ nsView: BrowserWindowTrafficLightActionHitTargetView, context: Context) {
        context.coordinator.onPressedChanged = onPressedChanged
        context.coordinator.action = action
        nsView.coordinator = context.coordinator
        nsView.isActionEnabled = isEnabled
    }

    static func dismantleNSView(
        _ nsView: BrowserWindowTrafficLightActionHitTargetView,
        coordinator: Coordinator
    ) {
        nsView.coordinator = nil
        nsView.isActionEnabled = false
    }

    @MainActor
    final class Coordinator {
        var onPressedChanged: @MainActor (Bool) -> Void
        var action: @MainActor () -> Void

        init(
            onPressedChanged: @escaping @MainActor (Bool) -> Void,
            action: @escaping @MainActor () -> Void
        ) {
            self.onPressedChanged = onPressedChanged
            self.action = action
        }

        func setPressed(_ isPressed: Bool) {
            onPressedChanged(isPressed)
        }

        func performAction() {
            action()
        }
    }
}

@MainActor
private final class BrowserWindowTrafficLightActionHitTargetView: NSView {
    weak var coordinator: BrowserWindowTrafficLightActionHitTarget.Coordinator?

    var isActionEnabled: Bool = true {
        didSet {
            if !isActionEnabled {
                setPressed(false)
            }
        }
    }

    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActionEnabled,
              !isHidden,
              alphaValue > 0.01,
              bounds.contains(point)
        else {
            return nil
        }

        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard isActionEnabled else { return }

        setPressed(bounds.contains(convert(event.locationInWindow, from: nil)))

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let isInside = bounds.contains(convert(nextEvent.locationInWindow, from: nil))
            setPressed(isInside)

            if nextEvent.type == .leftMouseUp {
                let shouldPerformAction = isActionEnabled && isInside
                setPressed(false)
                if shouldPerformAction {
                    DispatchQueue.main.async { [weak coordinator] in
                        coordinator?.performAction()
                    }
                }
                return
            }
        }

        setPressed(false)
    }

    private func setPressed(_ isPressed: Bool) {
        guard self.isPressed != isPressed else { return }
        self.isPressed = isPressed
        coordinator?.setPressed(isPressed)
    }
}

private struct BrowserWindowTrafficLightButtonStyle: ButtonStyle {
    let action: BrowserWindowTrafficLightAction
    let isEnabled: Bool
    let isClusterHovered: Bool
    let isPressedByAppKitHitTarget: Bool
    let drawsActivePalette: Bool

    func makeBody(configuration: Configuration) -> some View {
        BrowserWindowTrafficLightButtonFace(
            action: action,
            isEnabled: isEnabled,
            isClusterHovered: isClusterHovered,
            isPressed: configuration.isPressed || isPressedByAppKitHitTarget,
            drawsActivePalette: drawsActivePalette
        )
    }
}

private struct BrowserWindowTrafficLightButtonFace: View {
    let action: BrowserWindowTrafficLightAction
    let isEnabled: Bool
    let isClusterHovered: Bool
    let isPressed: Bool
    let drawsActivePalette: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(fillColor)
                .overlay {
                    Circle()
                        .stroke(borderColor, lineWidth: 0.6)
                }

            glyph
                .foregroundStyle(action.glyphColor)
                .opacity(showsGlyph ? 1 : 0)
        }
        .frame(
            width: BrowserWindowTrafficLightMetrics.buttonDiameter,
            height: BrowserWindowTrafficLightMetrics.buttonDiameter
        )
        .contentShape(Circle())
    }

    @ViewBuilder
    private var glyph: some View {
        let diameter = BrowserWindowTrafficLightMetrics.buttonDiameter
        let lineThickness = max(1.35, diameter * 0.13)

        switch action {
        case .close:
            ZStack {
                Capsule()
                    .frame(width: diameter * 0.64, height: lineThickness)
                    .rotationEffect(.degrees(45))
                Capsule()
                    .frame(width: diameter * 0.64, height: lineThickness)
                    .rotationEffect(.degrees(-45))
            }
        case .minimize:
            Capsule()
                .frame(width: diameter * 0.70, height: lineThickness)
        case .zoom:
            BrowserWindowTrafficLightMirroredZoomGlyph()
                .frame(width: diameter * 1.12, height: diameter * 1.12)
        }
    }

    private var fillColor: Color {
        guard isEnabled, drawsActivePalette else {
            return BrowserWindowTrafficLightPalette.inactive
        }

        return isPressed ? action.activePaletteColor : action.paletteColor
    }

    private var borderColor: Color {
        guard isEnabled, drawsActivePalette else {
            return Color.black.opacity(0.10)
        }

        return Color.black.opacity(isPressed ? 0.24 : 0.18)
    }

    private var showsGlyph: Bool {
        isEnabled && drawsActivePalette && (isClusterHovered || isPressed)
    }
}

private struct BrowserWindowTrafficLightMirroredZoomGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let referenceSize: CGFloat = 85.4
        let scale = min(rect.width, rect.height) / referenceSize
        let origin = CGPoint(
            x: rect.midX - referenceSize * scale / 2,
            y: rect.midY - referenceSize * scale / 2
        )

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }

        var path = Path()

        path.move(to: point(54.2, 20.8))
        path.addLine(to: point(27.5, 20.8))
        path.addCurve(
            to: point(21.0, 27.3),
            control1: point(23.9, 20.8),
            control2: point(21.0, 23.7)
        )
        path.addLine(to: point(21.0, 54.0))
        path.closeSubpath()

        path.move(to: point(31.0, 64.5))
        path.addLine(to: point(57.8, 64.5))
        path.addCurve(
            to: point(64.3, 58.0),
            control1: point(61.4, 64.5),
            control2: point(64.3, 61.6)
        )
        path.addLine(to: point(64.3, 31.2))
        path.closeSubpath()

        return path
    }
}

/// MiniWindow still uses AppKit's native titlebar buttons. This spacer reserves
/// the same leading width as Sumi's custom browser traffic-light cluster.
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
