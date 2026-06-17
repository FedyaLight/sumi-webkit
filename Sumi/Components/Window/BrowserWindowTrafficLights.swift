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

// Hosts the window's LIVE standard window buttons (close, minimize, zoom) repositioned from the
// theme frame into the sidebar header. Because these are the real instances returned by
// `window.standardWindowButton(_:)` (per Apple's documentation: "the window button of a given
// kind in the window's view hierarchy"), AppKit keeps driving their active/inactive dimming and
// hover glyphs. Reparenting via `addSubview` implicitly detaches a view from its previous parent
// (documented NSView behavior), so no explicit detach call is needed. All three buttons therefore
// behave identically — close, minimize and zoom are no longer asymmetric.
@MainActor
private final class BrowserWindowStandardTrafficLightClusterView: NSView {
    private var buttonsByAction: [BrowserWindowTrafficLightAction: NSButton] = [:]
    private var actionProvider: BrowserWindowTrafficLightActionProvider?
    private var isClusterVisible = false
    private var reclamationObservers: [NSObjectProtocol] = []

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
        if reclamationObservers.isEmpty == false {
            let center = NotificationCenter.default
            for observer in reclamationObservers {
                center.removeObserver(observer)
            }
            reclamationObservers.removeAll()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installReclamationObserversIfNeeded()
        configure()
        updateButtonStates()
    }

    // AppKit's theme frame reclaims the live standardWindowButton instances on certain window
    // transitions (sheet attachment, key become/resign) and repositions them back into the
    // titlebar. We cannot prevent that, so we reactively undo it: on each such transition we check
    // whether the buttons are still descendants of this cluster and, if not, re-parent them back
    // here. This keeps the buttons pinned to the sidebar header even while a sheet (e.g. the Cmd+Q
    // confirmation) is attached. `didEndSheet` covers the documented re-grab case; the key
    // notifications cover activation transitions. Main/occlusion overlap with key for a browser
    // window and were trimmed to avoid redundant fires.
    private func installReclamationObserversIfNeeded() {
        guard reclamationObservers.isEmpty, let window else { return }
        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reclaimButtonsIfNeeded()
            }
        }
        for name in [
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didEndSheetNotification,
        ] {
            reclamationObservers.append(
                center.addObserver(forName: name, object: window, queue: .main, using: handler)
            )
        }
    }

    private func reclaimButtonsIfNeeded() {
        guard buttonsByAction.isEmpty == false,
              buttonsByAction.values.contains(where: { $0.isDescendant(of: self) == false })
        else { return }
        configure()
        needsLayout = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isClusterVisible, isHidden == false else { return nil }

        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }

    func configure() {
        // Re-fetch the live buttons whenever the hosting window changes or AppKit reclaims them.
        // `standardWindowButton` returns the window's own button instance; `addSubview` reparents
        // it here implicitly, and is skipped when the button is already in the cluster to avoid
        // redundant will/didAddSubview churn.
        guard let window else {
            buttonsByAction.removeAll()
            return
        }

        var didReparent = false
        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = window.standardWindowButton(action.buttonType) else { continue }
            buttonsByAction[action] = button
            applyIdentity(to: button, for: action)
            if button.isDescendant(of: self) == false {
                button.translatesAutoresizingMaskIntoConstraints = true
                button.autoresizingMask = []
                addSubview(button)
                didReparent = true
            }
        }

        if didReparent {
            needsLayout = true
        }
    }

    // The identifier is constant for a given action, so it is set once at configure time. The
    // accessibility label is handled in updateButtonStates because it can flip between
    // "Enter"/"Exit Full Screen" based on the window's fullScreen style-mask bit.
    private func applyIdentity(to button: NSButton, for action: BrowserWindowTrafficLightAction) {
        button.identifier = NSUserInterfaceItemIdentifier(action.accessibilityIdentifier)
        button.setAccessibilityIdentifier(action.accessibilityIdentifier)
    }

    func clearWindowActionTargets() {
        // On dismantle we only stop observing and mark invisible. We deliberately do NOT nil the
        // buttons' target/action: these are the window's live instances, which AppKit may reuse
        // (e.g. when the titlebar buttons resurface during fullscreen). Stripping their wiring
        // would leave dead buttons until the cluster is recreated. deinit owns observer removal.
        isClusterVisible = false
        if reclamationObservers.isEmpty == false {
            let center = NotificationCenter.default
            for observer in reclamationObservers {
                center.removeObserver(observer)
            }
            reclamationObservers.removeAll()
        }
    }

    func update(actionProvider: BrowserWindowTrafficLightActionProvider, isVisible: Bool) {
        self.actionProvider = actionProvider
        isHidden = !isVisible
        setAccessibilityElement(isVisible)
        isClusterVisible = isVisible
        // Re-grab in case AppKit reclaimed the live instances (sheet/key transition) since the
        // last update; configure() is cheap when the buttons are already in the cluster.
        configure()
        updateButtonStates()
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
    }

    private func updateButtonStates() {
        let targetWindow = actionProvider?.resolvedTargetWindow(preferred: window) ?? window

        for action in BrowserWindowTrafficLightAction.allCases {
            guard let button = buttonsByAction[action] else { continue }

            button.target = targetWindow
            button.action = action.selector
            button.isHidden = !isClusterVisible
            button.alphaValue = isClusterVisible ? 1 : 0
            button.isEnabled = isClusterVisible
                && (actionProvider?.isEnabled(action, preferred: window) ?? false)
            button.setAccessibilityLabel(
                actionProvider?.accessibilityLabel(for: action, preferred: window)
                    ?? action.accessibilityLabel
            )
            button.setAccessibilityHidden(!isClusterVisible)
        }
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
