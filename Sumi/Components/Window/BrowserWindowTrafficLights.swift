import AppKit
import SwiftUI

enum BrowserWindowControlsAccessibilityIdentifiers {
    static let closeButton = "browser-window-close-button"
    static let minimizeButton = "browser-window-minimize-button"
    static let zoomButton = "browser-window-zoom-button"
    static let miniBrowserWindow = "mini-browser-window"

    static let allButtonIdentifiers: Set<String> = [
        closeButton,
        minimizeButton,
        zoomButton,
    ]

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
    static let close = Color(hex: "EC6A5E")
    static let minimize = Color(hex: "F4BF4F")
    static let zoom = Color(hex: "62C554")
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
}

@MainActor
struct BrowserWindowTrafficLightActionProvider {
    weak var targetWindow: NSWindow?
    var close: @MainActor (NSWindow) -> Void
    var minimize: @MainActor (NSWindow) -> Void
    var zoom: @MainActor (NSWindow) -> Void

    init(
        targetWindow: NSWindow?,
        close: @escaping @MainActor (NSWindow) -> Void = { $0.performClose(nil) },
        minimize: @escaping @MainActor (NSWindow) -> Void = { $0.miniaturize(nil) },
        zoom: @escaping @MainActor (NSWindow) -> Void = { $0.performZoom(nil) }
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
        targetWindow?.isKeyWindow != false
    }
}

struct BrowserWindowTrafficLights: View {
    var actionProvider: BrowserWindowTrafficLightActionProvider
    var isVisible: Bool = true

    @State private var isClusterHovered = false

    init(
        actionProvider: BrowserWindowTrafficLightActionProvider,
        isVisible: Bool = true
    ) {
        self.actionProvider = actionProvider
        self.isVisible = isVisible
    }

    var body: some View {
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
        .accessibilityElement(children: .contain)
    }

    private func trafficLightButton(_ action: BrowserWindowTrafficLightAction) -> some View {
        let isEnabled = actionProvider.isEnabled(action)

        return Button {
            actionProvider.perform(action)
        } label: {
            ZStack {
                Circle()
                    .fill(fillColor(for: action, isEnabled: isEnabled))
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.14), lineWidth: 0.75)
                    }

                Image(systemName: action.symbolName)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(isEnabled ? 0.58 : 0.22))
                    .opacity(isClusterHovered && isEnabled ? 1 : 0)
            }
            .frame(
                width: BrowserWindowTrafficLightMetrics.buttonDiameter,
                height: BrowserWindowTrafficLightMetrics.buttonDiameter
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityIdentifier(action.accessibilityIdentifier)
    }

    private func fillColor(
        for action: BrowserWindowTrafficLightAction,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled, actionProvider.drawsActivePalette else {
            return BrowserWindowTrafficLightPalette.inactive
        }

        return action.paletteColor
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
