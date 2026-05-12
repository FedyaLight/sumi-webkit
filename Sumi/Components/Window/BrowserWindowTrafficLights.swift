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
