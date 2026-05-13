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
private final class BrowserWindowTrafficLightActivationObserver {
    private var observerTokens: [NSObjectProtocol] = []

    init(onChange: @escaping @MainActor () -> Void) {
        let notificationCenter = NotificationCenter.default
        let windowNotifications: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
        ]
        let applicationNotifications: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ]

        observerTokens = (windowNotifications + applicationNotifications).map { notificationName in
            notificationCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onChange()
                }
            }
        }
    }

    isolated deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

@MainActor
private final class BrowserWindowStandardTrafficLightClusterView: NSView {
    private var buttonsByAction: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private let glyphOverlayView = BrowserWindowTrafficLightGlyphOverlayView()
    private var trackingArea: NSTrackingArea?
    private var activationObserver: BrowserWindowTrafficLightActivationObserver?
    private var actionProvider: BrowserWindowTrafficLightActionProvider?
    private var isClusterVisible = false
    private var hostingWindowDrawsActiveControls = false {
        didSet {
            guard hostingWindowDrawsActiveControls != oldValue else { return }
            updateHoverGlyphRendering()
        }
    }
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
        activationObserver = BrowserWindowTrafficLightActivationObserver { [weak self] in
            self?.refreshHostingWindowActivationState()
        }
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
        refreshHostingWindowActivationState()
        isClusterHovered = true
    }

    override func mouseMoved(with event: NSEvent) {
        refreshHostingWindowActivationState()
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
        refreshHostingWindowActivationState()
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
        isClusterVisible = isVisible
        for button in buttonsByAction.values {
            button.isHidden = !isVisible
            button.alphaValue = isVisible ? 1 : 0
            button.isEnabled = isVisible
            button.setAccessibilityElement(isVisible)
        }
        updateHoverGlyphRendering()
    }

    private func updateHoverStateFromCurrentMouseLocation() {
        refreshHostingWindowActivationState()
        guard let window else {
            isClusterHovered = false
            return
        }

        isClusterHovered = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func updateHoverGlyphRendering() {
        let shouldEnableOverlaySurface = isClusterVisible && hostingWindowDrawsActiveControls
        glyphOverlayView.isHidden = !shouldEnableOverlaySurface
        glyphOverlayView.alphaValue = shouldEnableOverlaySurface ? 1 : 0
        glyphOverlayView.isClusterHovered = isClusterHovered && shouldEnableOverlaySurface
        updateGlyphOverlayActions()
    }

    private func updateGlyphOverlayActions() {
        guard isClusterVisible,
              hostingWindowDrawsActiveControls,
              let actionProvider
        else {
            glyphOverlayView.enabledActions = []
            return
        }

        var overlayActions = Set(BrowserWindowTrafficLightAction.allCases.filter(actionProvider.isEnabled))
        if let pressedAction {
            overlayActions.remove(pressedAction)
        }
        glyphOverlayView.enabledActions = overlayActions
    }

    private func refreshHostingWindowActivationState() {
        guard NSApplication.shared.isActive,
              let hostingWindow = window
        else {
            hostingWindowDrawsActiveControls = false
            return
        }

        let browserWindow = actionProvider?.targetWindow ?? hostingWindow
        hostingWindowDrawsActiveControls = hostingWindow.isKeyWindow
            || hostingWindow.isMainWindow
            || NSApplication.shared.keyWindow?.belongsToBrowserChromeFocusGroup(of: browserWindow) == true
            || NSApplication.shared.mainWindow?.belongsToBrowserChromeFocusGroup(of: browserWindow) == true
    }

    private func action(at point: NSPoint) -> BrowserWindowTrafficLightAction? {
        buttonsByAction.first { _, button in
            button.frame.contains(point)
        }?.key
    }
}

private extension NSWindow {
    @MainActor
    func belongsToBrowserChromeFocusGroup(of browserWindow: NSWindow) -> Bool {
        if self === browserWindow {
            return true
        }

        var candidate = parent
        while let window = candidate {
            if window === browserWindow {
                return true
            }
            candidate = window.parent
        }

        return false
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
