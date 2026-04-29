import AppKit
import SwiftUI

enum BrowserWindowTrafficLightKind: CaseIterable, Identifiable, Equatable {
    case close
    case minimize
    case zoom

    var id: Self { self }

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
            return "Close window"
        case .minimize:
            return "Minimize window"
        case .zoom:
            return "Zoom window"
        }
    }

    var symbolName: String {
        switch self {
        case .close:
            return "xmark"
        case .minimize:
            return "minus"
        case .zoom:
            return "plus"
        }
    }

    var color: Color {
        switch self {
        case .close:
            return Color(red: 1.0, green: 0.373, blue: 0.341)
        case .minimize:
            return Color(red: 1.0, green: 0.741, blue: 0.180)
        case .zoom:
            return Color(red: 0.173, green: 0.784, blue: 0.251)
        }
    }
}

enum BrowserWindowTrafficLightInteractionState: Equatable {
    case idle
    case hovered
    case pressed
}

struct BrowserWindowTrafficLightAppearance: Equatable {
    let fillOpacity: Double
    let symbolOpacity: Double
    let strokeOpacity: Double
    let overlayOpacity: Double
    let scale: CGFloat
}

enum BrowserWindowTrafficLightAppearanceResolver {
    static func appearance(
        isEnabled: Bool,
        isWindowActive: Bool,
        interactionState: BrowserWindowTrafficLightInteractionState
    ) -> BrowserWindowTrafficLightAppearance {
        guard isEnabled else {
            return BrowserWindowTrafficLightAppearance(
                fillOpacity: 0.22,
                symbolOpacity: 0,
                strokeOpacity: 0.16,
                overlayOpacity: 0,
                scale: 1
            )
        }

        let activeFillOpacity = isWindowActive ? 1.0 : 0.36
        switch interactionState {
        case .idle:
            return BrowserWindowTrafficLightAppearance(
                fillOpacity: activeFillOpacity,
                symbolOpacity: 0,
                strokeOpacity: isWindowActive ? 0.16 : 0.12,
                overlayOpacity: 0,
                scale: 1
            )
        case .hovered:
            return BrowserWindowTrafficLightAppearance(
                fillOpacity: isWindowActive ? 1.0 : 0.62,
                symbolOpacity: isWindowActive ? 0.72 : 0.38,
                strokeOpacity: 0.18,
                overlayOpacity: 0,
                scale: 1
            )
        case .pressed:
            return BrowserWindowTrafficLightAppearance(
                fillOpacity: isWindowActive ? 0.94 : 0.54,
                symbolOpacity: isWindowActive ? 0.78 : 0.42,
                strokeOpacity: 0.22,
                overlayOpacity: 0.18,
                scale: 0.92
            )
        }
    }
}

enum BrowserWindowTrafficLightMetrics {
    static let buttonDiameter: CGFloat = 12
    static let buttonSpacing: CGFloat = 8
    static let sidebarReservedWidth: CGFloat = 60
    static let windowLeadingInset: CGFloat = SidebarChromeMetrics.horizontalPadding
        + SidebarChromeMetrics.windowControlsLeadingInset
    static let windowTopInset: CGFloat = floor(
        (SidebarChromeMetrics.controlStripHeight - buttonDiameter) / 2
    )
    static let hitTargetSize: CGFloat = 20

    static var clusterWidth: CGFloat {
        buttonDiameter * CGFloat(BrowserWindowTrafficLightKind.allCases.count)
            + buttonSpacing * CGFloat(BrowserWindowTrafficLightKind.allCases.count - 1)
    }
}

enum BrowserWindowTrafficLightAvailability {
    static func isEnabled(
        kind: BrowserWindowTrafficLightKind,
        window: NSWindow?
    ) -> Bool {
        guard let window,
              window.attachedSheet == nil
        else {
            return false
        }

        return isEnabled(kind: kind, styleMask: window.styleMask, hasAttachedSheet: false)
    }

    static func isEnabled(
        kind: BrowserWindowTrafficLightKind,
        styleMask: NSWindow.StyleMask,
        hasAttachedSheet: Bool
    ) -> Bool {
        guard hasAttachedSheet == false else {
            return false
        }

        switch kind {
        case .close:
            return styleMask.contains(.closable)
        case .minimize:
            return styleMask.contains(.miniaturizable)
                && styleMask.contains(.fullScreen) == false
        case .zoom:
            return styleMask.contains(.resizable)
        }
    }
}

@MainActor
enum BrowserWindowTrafficLightActionRouter {
    static func perform(
        _ kind: BrowserWindowTrafficLightKind,
        window: NSWindow?
    ) {
        guard let window,
              BrowserWindowTrafficLightAvailability.isEnabled(kind: kind, window: window)
        else {
            return
        }

        switch kind {
        case .close:
            window.performClose(nil)
        case .minimize:
            window.miniaturize(nil)
        case .zoom:
            window.performZoom(nil)
        }
    }
}

struct BrowserWindowTrafficLights: View {
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isClusterHovered = false
    @State private var notificationRevision: UInt = 0

    private var window: NSWindow? {
        windowState.window
    }

    private var isWindowActive: Bool {
        guard let window else { return false }
        return NSApp.isActive && (window.isKeyWindow || window.isMainWindow)
    }

    var body: some View {
        let _ = notificationRevision

        HStack(spacing: BrowserWindowTrafficLightMetrics.buttonSpacing) {
            ForEach(BrowserWindowTrafficLightKind.allCases) { kind in
                Button {
                    BrowserWindowTrafficLightActionRouter.perform(kind, window: window)
                } label: {
                    EmptyView()
                }
                .buttonStyle(
                    BrowserWindowTrafficLightButtonStyle(
                        kind: kind,
                        isClusterHovered: isClusterHovered,
                        isWindowActive: isWindowActive
                    )
                )
                .disabled(
                    BrowserWindowTrafficLightAvailability.isEnabled(
                        kind: kind,
                        window: window
                    ) == false
                )
                .accessibilityIdentifier(kind.accessibilityIdentifier)
                .accessibilityLabel(kind.accessibilityLabel)
                .help(kind.accessibilityLabel)
            }
        }
        .frame(
            width: BrowserWindowTrafficLightMetrics.clusterWidth,
            height: BrowserWindowTrafficLightMetrics.hitTargetSize
        )
        .padding(.leading, BrowserWindowTrafficLightMetrics.windowLeadingInset)
        .padding(.top, BrowserWindowTrafficLightMetrics.windowTopInset)
        .onHover { isClusterHovered = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            notificationRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            notificationRevision &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { notification in
            updateRevisionIfNeeded(notification)
        }
    }

    private func updateRevisionIfNeeded(_ notification: Notification) {
        guard let notificationWindow = notification.object as? NSWindow,
              notificationWindow === window
        else {
            return
        }

        notificationRevision &+= 1
    }
}

private struct BrowserWindowTrafficLightButtonStyle: ButtonStyle {
    let kind: BrowserWindowTrafficLightKind
    let isClusterHovered: Bool
    let isWindowActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let interactionState: BrowserWindowTrafficLightInteractionState = configuration.isPressed
            ? .pressed
            : (isClusterHovered ? .hovered : .idle)
        let appearance = BrowserWindowTrafficLightAppearanceResolver.appearance(
            isEnabled: isEnabled,
            isWindowActive: isWindowActive,
            interactionState: interactionState
        )

        ZStack {
            Circle()
                .fill(kind.color.opacity(appearance.fillOpacity))
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(appearance.strokeOpacity), lineWidth: 0.5)
                }
                .overlay {
                    Circle()
                        .fill(Color.black.opacity(appearance.overlayOpacity))
                }

            Image(systemName: kind.symbolName)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.68))
                .opacity(appearance.symbolOpacity)
                .accessibilityHidden(true)
        }
        .frame(
            width: BrowserWindowTrafficLightMetrics.buttonDiameter,
            height: BrowserWindowTrafficLightMetrics.buttonDiameter
        )
        .frame(
            width: BrowserWindowTrafficLightMetrics.hitTargetSize,
            height: BrowserWindowTrafficLightMetrics.hitTargetSize
        )
        .scaleEffect(appearance.scale)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        .animation(.easeOut(duration: 0.12), value: isClusterHovered)
    }
}
